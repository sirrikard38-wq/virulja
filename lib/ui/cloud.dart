import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import '../src/domain/session.dart';
import '../src/domain/tree.dart';
import '../src/domain/trip_tree.dart';
import 'push.dart';
import 'store.dart';

/// Web requests through the browser's `fetch`.
class BrowserJsonHttp implements JsonHttp {
  @override
  Future<HttpReply> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final init = web.RequestInit(
      method: method,
      headers: headers.jsify() as JSObject,
      body: body?.toJS,
    );
    final response = await web.window.fetch(url.toString().toJS, init).toDart;
    final text = (await response.text().toDart).toDart;
    return HttpReply(response.status, text);
  }
}

/// Reads `online.json` next to the page. Null (everything stays on this phone)
/// when the file is missing or unfinished. It is always checked with the server.
Future<OnlineConfig?> loadOnlineConfig() async {
  try {
    final response = await web.window
        .fetch('online.json'.toJS, web.RequestInit(cache: 'no-cache'))
        .toDart;
    if (!response.ok) return null;
    return OnlineConfig.tryParse((await response.text().toDart).toDart);
  } on Object {
    return null;
  }
}

/// Keeps every trip the same on all the phones of the group.
///
///  * Changes go to the Realtime Database value by value (see `tree.dart`), so
///    nothing is overwritten and changes made offline wait until there is a
///    connection.
///  * The trip that is open follows the database live; the others are read when
///    the app opens or comes back to the screen.
///  * Pictures and sounds are stored in the same database, apart from the trips
///    so a trip stays small, and each phone keeps what it has seen.
class CloudSync {
  CloudSync(this._config, this._store) {
    _session = FirebaseSession(_config, _http, _store);
  }

  static const Duration _pushDelay = Duration(milliseconds: 600);
  static const Duration _retryDelay = Duration(seconds: 20);
  static const Duration _streamRetryDelay = Duration(seconds: 5);
  static const Duration _waitingCheck = Duration(seconds: 30);

  /// The database rules refuse anything bigger.
  static const int _maxBlobLength = 3000000;

  final OnlineConfig _config;
  final AppStore _store;
  final JsonHttp _http = BrowserJsonHttp();
  late final FirebaseSession _session;
  final Map<String, Future<web.Blob?>> _fetching = {};

  web.EventSource? _stream;
  String? _watched;
  Timer? _pushTimer;
  Timer? _streamTimer;
  bool _pushing = false;
  bool _pushAgain = false;

  /// Called when something new has arrived from the group.
  void Function()? onChange;

  /// A short message for whoever holds the phone.
  void Function(String message)? onNotice;

  /// False while the cloud cannot be reached; changes then wait on the phone.
  bool reachable = true;

  AppData get _data => _store.data;

  String _nameOf(String id) => _data.personById(id)?.name ?? 'Netko';

  Flat _flat(Trip trip) => flatten(
      tripToTree(trip, _nameOf, (id) => _data.personById(id)?.phone));

  /// Null while notifications are not set up.
  String? get pushKey => _config.pushKey;

  /// Tells the daily sender about this phone and the trips it is on.
  Future<void> savePushDevice(Map<String, String> device) async {
    await _session.token();
    await _send('PUT', 'push/${_session.uid}', json: {
      ...device,
      'trips': {
        for (final trip in _data.trips)
          trip.id: {'city': trip.city, 'start': dayKey(trip.start)},
      },
    });
  }

  Future<void> removePushDevice() async {
    await _session.token();
    await _send('DELETE', 'push/${_session.uid}');
  }

  /// Dates change and trips come and go, so this is repeated with every refresh.
  Future<void> _updatePushDevice() async {
    try {
      final device = pushKey == null ? null : await pushDevice();
      if (device != null) await savePushDevice(device);
    } on Object {
      // Only reminders are late; the next refresh tries again.
    }
  }

  String _meIn(Trip trip) => _data.identities[trip.id] ?? _data.meId!;

  /// Ten characters with at least one capital, small letter, digit and sign.
  /// Look-alikes are left out; the signs are safe in a database key and an
  /// address, and the length matches the database rules.
  String newCode() {
    const capitals = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const smalls = 'abcdefghijkmnpqrstuvwxyz';
    const digits = '23456789';
    const signs = '!-_';
    const every = capitals + smalls + digits + signs;
    final random = Random.secure();
    String pick(String from) => from[random.nextInt(from.length)];
    return ([
      pick(capitals),
      pick(smalls),
      pick(digits),
      pick(signs),
      for (var i = 0; i < 6; i++) pick(every),
    ]..shuffle(random))
        .join();
  }

  /// Gives a trip what sharing needs: a code, an admin, and this phone's id.
  Future<void> _prepare(Trip trip) async {
    await _session.token();
    final me = _meIn(trip);
    trip.code ??= newCode();
    if (trip.adminIds.isEmpty) trip.adminIds = [me];
    final uid = _session.uid;
    if (uid != null) trip.uids[me] = uid;
  }

  /// A new code for [trip]; the old one stops working, members stay.
  Future<void> changeCode(Trip trip) async {
    final old = trip.code;
    trip.code = newCode();
    _store.save();
    if (old != null) {
      await _send('DELETE', 'codes/$old');
    }
    await _push();
  }

  /// Removes someone from the trip and locks them out of it.
  Future<void> removeMember(Trip trip, String personId) async {
    final uid = trip.uids[personId];
    if (uid != null) await _send('PUT', 'banned/${trip.id}/$uid', json: true);
    trip.memberIds.remove(personId);
    trip.adminIds.remove(personId);
    trip.uids.remove(personId);
    _store.save();
    await _push();
  }

  /// The trip behind a code. Null when no trip has that code.
  Future<({CloudTrip trip, Tree tree})?> findTrip(String code) async {
    final id = jsonDecode((await _send('GET', 'codes/$code')).body);
    return id is String ? fetchTrip(id) : null;
  }

  Future<Uri> _address(String path) async =>
      Uri.parse('${_config.databaseUrl}/$path.json')
          .replace(queryParameters: {'auth': await _session.token()});

  Future<HttpReply> _send(String method, String path, {Object? json}) async {
    final reply = await _http.send(
      method,
      await _address(path),
      headers: json == null ? const {} : const {'Content-Type': 'application/json'},
      body: json == null ? null : jsonEncode(json),
    );
    if (reply.status == 401) _session.tokenRefused();
    if (!reply.ok) throw OnlineException('$method answered ${reply.status}');
    return reply;
  }

  /// The address of the stored picture or sound [id] of [tripId]. A database key
  /// cannot have a dot in it.
  String _blobPath(String tripId, String id) =>
      'blobs/$tripId/${id.replaceAll('.', '_')}';

  void start() {
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event event) {
        if (web.document.visibilityState == 'visible') {
          _refresh();
        } else {
          _closeStream();
        }
      }).toJS,
    );
    web.window.addEventListener(
      'online',
      ((web.Event event) {
        _refresh();
      }).toJS,
    );
    Timer.periodic(_waitingCheck, (_) {
      if (_data.waiting.isNotEmpty && web.document.visibilityState == 'visible') {
        _checkWaiting();
      }
    });
    _refresh();
  }

  /// Asks the group to let this phone into [invited].
  Future<void> askToJoin(({CloudTrip trip, Tree tree}) invited) async {
    final trip = invited.trip.trip;
    await _session.token();
    await _send('PATCH', 'trips/${trip.id}/requests/${_session.uid}', json: {
      'name': _nameOf(_data.meId!),
      'phone': _data.personById(_data.meId!)?.phone,
    });
    _data.waiting[trip.id] = trip.city;
    _store.save();
  }

  /// Sees what the groups decided about this phone.
  Future<void> _checkWaiting() async {
    try {
      await _session.token();
      for (final entry in _data.waiting.entries.toList()) {
        final found = await fetchTrip(entry.key);
        if (found == null) continue;
        final trip = found.trip.trip;
        final mine = trip.requests.where((item) => item.id == _session.uid);
        if (mine.isEmpty) {
          _data.waiting.remove(entry.key);
          _store.save();
          onNotice?.call('${entry.value}: zahtjev je odbijen.');
          onChange?.call();
        } else if (mine.first.approvals.length >= trip.approvalsNeeded) {
          _data.waiting.remove(entry.key);
          trip.requests.remove(mine.first);
          join(found);
          onNotice?.call('${entry.value}: grupa te prihvatila.');
          onChange?.call();
        }
      }
    } on Object {
      // Asked again soon.
    }
  }

  /// Everything new from the cloud, then everything waiting on this phone.
  Future<void> _refresh() async {
    await _checkWaiting();
    try {
      for (final trip in _data.trips.toList()) {
        // Asked with a fresh token, a refusal can only mean a locked door.
        _session.tokenRefused();
        final reply = await _http.send('GET', await _address('trips/${trip.id}'));
        if (reply.status == 401) {
          _forget(trip);
        } else if (reply.ok) {
          _receive(trip, 'put', '/', jsonDecode(reply.body));
        }
      }
      reachable = true;
    } on Object {
      reachable = false;
    }
    final watched = _watched;
    if (watched != null && _stream == null) _openStream(watched);
    await _push();
    await _updatePushDevice();
  }

  /// Sends changes soon, so a burst of changes is one request.
  void pushSoon() {
    _pushTimer?.cancel();
    _pushTimer = Timer(_pushDelay, _push);
  }

  Future<void> _push() async {
    if (_pushing) {
      _pushAgain = true;
      return;
    }
    _pushing = true;
    try {
      for (final trip in _data.trips.toList()) {
        await _prepare(trip);
        final mirror = _store.mirrorOf(trip.id);
        // First, so that the code works even if something else cannot be sent.
        final codeMark = 'code:${trip.code}';
        if (!mirror.uploaded.contains(codeMark)) {
          await _send('PUT', 'codes/${trip.code}', json: trip.id);
          mirror.uploaded.add(codeMark);
          _store.save();
        }
        final pending = mirror.pending(_flat(trip));
        if (pending.isNotEmpty) {
          await _send('PATCH', 'trips/${trip.id}', json: pending);
          mirror.confirm(pending);
          _store.save();
        }
      }
      await _uploadBlobs();
      reachable = true;
    } on Object {
      reachable = false;
      _pushTimer?.cancel();
      _pushTimer = Timer(_retryDelay, _push);
    }
    _pushing = false;
    if (_pushAgain) {
      _pushAgain = false;
      pushSoon();
    }
  }

  /// Takes news from the cloud into the trip on this phone.
  void _receive(Trip trip, String event, String path, Object? data) {
    final mirror = _store.mirrorOf(trip.id);
    if (event == 'put' && path == '/' && data == null) {
      // The cloud has lost this trip or never had it: this phone sends it again.
      mirror.server = {};
      pushSoon();
      return;
    }
    final before = _flat(trip);
    final merged = mirror.receive(before, event, path, data);
    _store.save();
    if (sameFlat(before, merged)) return;
    final cloud = tripFromTree(trip.id, unflatten(merged));
    if (cloud == null) return;
    if (!cloud.trip.memberIds.contains(_meIn(trip))) {
      _forget(trip);
      return;
    }
    trip.copyFrom(cloud.trip);
    _learnNames(cloud.names);
    cloud.phones.forEach((id, phone) => _data.personById(id)?.phone = phone);
    onChange?.call();
  }

  /// An admin has removed this person: the trip leaves this phone.
  void _forget(Trip trip) {
    _data.trips.remove(trip);
    _store.forgetMirror(trip.id);
    _store.save();
    onChange?.call();
  }

  void _learnNames(Map<String, String> names) {
    names.forEach((id, name) {
      final person = _data.personById(id);
      if (person == null) {
        _data.people.add(Person(id: id, name: name));
      } else {
        person.name = name;
      }
    });
  }

  /// Sends the pictures and sounds this phone has and the cloud does not. When a
  /// photo is safely there, the group is told it can be seen.
  Future<void> _uploadBlobs() async {
    for (final trip in _data.trips.toList()) {
      final mirror = _store.mirrorOf(trip.id);
      for (final id in blobIds(trip).toList()) {
        if (mirror.uploaded.contains(id)) continue;
        final blob = await _store.getBlob(id);
        if (blob == null) continue; // someone else's, still on its way
        final bytes = await blob.arrayBuffer().toDart;
        final text = base64Encode(Uint8List.view(bytes.toDart));
        if (text.length <= _maxBlobLength) {
          await _send('PUT', _blobPath(trip.id, id), json: text);
        }
        mirror.uploaded.add(id);
        _store.save();
      }
      var ready = false;
      for (final photo in trip.photos) {
        if (!photo.stored &&
            mirror.uploaded.containsAll([photo.id, thumbId(photo.id)])) {
          photo.stored = true;
          ready = true;
        }
      }
      if (ready) _pushAgain = true;
    }
  }

  /// A picture or sound another phone has put in the cloud. Null when it is not
  /// there yet or there is no connection.
  Future<web.Blob?> fetchBlob(Trip trip, String id) =>
      _fetching[id] ??= _fetchBlob(trip, id).whenComplete(() {
        _fetching.remove(id);
      });

  Future<web.Blob?> _fetchBlob(Trip trip, String id) async {
    try {
      final reply = await _send('GET', _blobPath(trip.id, id));
      final text = jsonDecode(reply.body);
      if (text is! String) return null;
      final blob = web.Blob(
        [base64Decode(text).toJS].toJS,
        web.BlobPropertyBag(type: id == trip.anthemClipId ? 'audio/wav' : 'image/jpeg'),
      );
      await _store.putBlob(id, blob);
      _store.mirrorOf(trip.id).uploaded.add(id);
      _store.save();
      return blob;
    } on Object {
      return null;
    }
  }

  /// Removes a picture or sound from the cloud; failing is harmless.
  Future<void> removeBlob(Trip trip, String id) async {
    try {
      await _send('DELETE', _blobPath(trip.id, id));
    } on Object {
      // It only stays as an unused file.
    }
  }

  /// The trip of an invitation, as it is in the cloud. Null when there is no such
  /// trip; throws when the cloud cannot be reached.
  Future<({CloudTrip trip, Tree tree})?> fetchTrip(String id) async {
    final reply = await _send('GET', 'trips/$id');
    final tree = jsonDecode(reply.body);
    if (tree is! Map) return null;
    final cloud = tripFromTree(id, tree.cast<String, dynamic>());
    return cloud == null ? null : (trip: cloud, tree: tree.cast<String, dynamic>());
  }

  /// Puts a trip on this phone: the right code is all it takes to be in it.
  void join(({CloudTrip trip, Tree tree}) invited) {
    final trip = invited.trip.trip;
    _learnNames(invited.trip.names);
    _store.mirrorOf(trip.id).server = flatten(invited.tree);
    if (!trip.memberIds.contains(_data.meId)) {
      trip.memberIds.add(_data.meId!);
    }
    _data.trips.add(trip);
    _store.save();
    pushSoon();
  }

  /// Follows [tripId] live, or nothing when it is null.
  void watch(String? tripId) {
    if (tripId == _watched) return;
    _closeStream();
    _watched = tripId;
    if (tripId != null) _openStream(tripId);
  }

  Future<void> _openStream(String tripId) async {
    _streamTimer?.cancel();
    final Uri address;
    try {
      address = await _address('trips/$tripId');
    } on Object {
      _reopenLater();
      return;
    }
    if (_watched != tripId || _stream != null) return;
    final stream = web.EventSource(address.toString());
    _stream = stream;

    void listen(String name) {
      stream.addEventListener(
        name,
        ((web.MessageEvent event) {
          final message = jsonDecode((event.data as JSString).toDart) as Map;
          final trip = _data.tripById(tripId);
          if (trip != null) {
            _receive(trip, name, message['path'] as String, message['data']);
          }
        }).toJS,
      );
    }

    void restart(web.Event event) {
      _session.tokenRefused();
      _closeStream();
      _reopenLater();
      if (event.type == 'cancel') _refresh(); // the rules no longer let us in
    }

    listen('put');
    listen('patch');
    stream.addEventListener('auth_revoked', restart.toJS);
    stream.addEventListener('cancel', restart.toJS);
    stream.onerror = ((web.Event event) {
      if (stream.readyState == web.EventSource.CLOSED) restart(event);
    }).toJS;
  }

  void _reopenLater() {
    _streamTimer?.cancel();
    _streamTimer = Timer(_streamRetryDelay, () {
      final watched = _watched;
      if (watched != null && _stream == null) _openStream(watched);
    });
  }

  void _closeStream() {
    _streamTimer?.cancel();
    _stream?.close();
    _stream = null;
  }
}
