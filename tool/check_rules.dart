/// Checks the database rules against the real database: a member and a
/// stranger, both new anonymous sign-ins, try what each may and may not do on a
/// test trip. Prints one line per check, with no tokens or ids.
///
///     dart run tool/check_rules.dart
///
/// The rules keep a trip from being wiped, so a few bytes of the test trip
/// (`trips/<id>/access`) stay behind; they can be deleted in the Firebase console.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

late final String _database;
late final String _apiKey;
final HttpClient _client = HttpClient();

class _User {
  _User(this.token, this.uid);
  final String token;
  final String uid;
}

Future<(int, Object?)> _call(String method, Uri url, [Object? body]) async {
  final request = await _client.openUrl(method, url);
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final reply = await request.close();
  final text = await reply.transform(utf8.decoder).join();
  Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    json = text;
  }
  return (reply.statusCode, json);
}

Future<_User> _signUp() async {
  final (status, body) = await _call(
    'POST',
    Uri.parse('https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_apiKey'),
    {'returnSecureToken': true},
  );
  if (status != 200) throw StateError('sign-in answered $status');
  final json = body as Map;
  return _User(json['idToken'] as String, json['localId'] as String);
}

Future<int> _as(_User user, String method, String path, [Object? body]) async {
  final url = Uri.parse('$_database/$path.json').replace(queryParameters: {'auth': user.token});
  final (status, _) = await _call(method, url, body);
  return status;
}

Future<Object?> _read(_User user, String path) async {
  final url = Uri.parse('$_database/$path.json').replace(queryParameters: {'auth': user.token});
  return (await _call('GET', url)).$2;
}

var _failed = 0;

Future<void> _check(String what, Future<int> Function() attempt, {required bool allowed}) async {
  final status = await attempt();
  final ok = (status == 200) == allowed;
  if (!ok) _failed++;
  print('${ok ? 'OK  ' : 'FAIL'} $what: ${status == 200 ? 'allowed' : 'refused ($status)'}');
}

String _random(int length) {
  const letters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final random = Random.secure();
  return List.generate(length, (_) => letters[random.nextInt(letters.length)]).join();
}

Future<void> main() async {
  final config = jsonDecode(File('web/online.json').readAsStringSync()) as Map;
  _database = (config['databaseUrl'] as String).replaceAll(RegExp(r'/+$'), '');
  _apiKey = config['apiKey'] as String;

  final member = await _signUp();
  final stranger = await _signUp();
  final trip = 'test-${_random(16)}';
  final code = _random(10);
  const key = 'ana_12345678';

  await _check('a member makes a new trip', () => _as(member, 'PATCH', 'trips/$trip', {
        'city': 'Proba',
        'country': 'Hrvatska',
        'start': '2030-01-01',
        'end': '2030-01-02',
        'people/ana/name': 'Ana',
        'access/${member.uid}': 'ana',
        'keys/$key': 'ana',
      }), allowed: true);
  await _check('the member gives it a code', () => _as(member, 'PUT', 'codes/$code', trip), allowed: true);
  await _check('the member puts a picture in', () => _as(member, 'PUT', 'blobs/$trip/p1', 'abc'), allowed: true);

  await _check('a stranger finds the trip by its code', () => _as(stranger, 'GET', 'codes/$code'), allowed: true);
  final read = await _read(stranger, 'trips/$trip');
  final sawTrip = read is Map && read.containsKey('people');
  if (sawTrip) _failed++;
  print('${sawTrip ? 'FAIL' : 'OK  '} a stranger reads the trip: ${sawTrip ? 'allowed' : 'refused'}');
  await _check('a stranger reads the city', () => _as(stranger, 'GET', 'trips/$trip/city'), allowed: true);
  await _check('a stranger changes the city', () => _as(stranger, 'PUT', 'trips/$trip/city', 'X'), allowed: false);
  await _check('a stranger lists the keys', () => _as(stranger, 'GET', 'trips/$trip/keys'), allowed: false);
  await _check('a stranger asks to join', () => _as(stranger, 'PATCH', 'trips/$trip/requests/${stranger.uid}', {'name': 'Iva'}), allowed: true);
  await _check('a stranger sees the own request', () => _as(stranger, 'GET', 'trips/$trip/requests/${stranger.uid}'), allowed: true);
  await _check('a stranger approves the own request', () => _as(stranger, 'PUT', 'trips/$trip/requests/${stranger.uid}/approvals/ana', true), allowed: false);
  await _check('a stranger writes another request', () => _as(stranger, 'PUT', 'trips/$trip/requests/${member.uid}/name', 'X'), allowed: false);
  await _check('a stranger lets itself in', () => _as(stranger, 'PUT', 'trips/$trip/access/${stranger.uid}', 'ana'), allowed: false);
  await _check('a stranger lets itself in with a wrong key', () => _as(stranger, 'PATCH', 'trips/$trip', {
        'claims/${stranger.uid}': 'ivo_87654321',
        'access/${stranger.uid}': 'ana',
      }), allowed: false);
  await _check('a stranger reads a picture', () => _as(stranger, 'GET', 'blobs/$trip/p1'), allowed: false);
  await _check('a stranger puts a picture in', () => _as(stranger, 'PUT', 'blobs/$trip/p2', 'abc'), allowed: false);
  await _check('a stranger moves the code to another trip', () => _as(stranger, 'PUT', 'codes/$code', 'test-${_random(16)}'), allowed: false);
  await _check('a stranger deletes the code', () => _as(stranger, 'DELETE', 'codes/$code'), allowed: false);

  await _check('the member wipes the whole trip', () => _as(member, 'DELETE', 'trips/$trip'), allowed: false);
  await _check('the member takes the lock off', () => _as(member, 'PATCH', 'trips/$trip', {'access': null}), allowed: false);
  await _check('the member changes the trip', () => _as(member, 'PUT', 'trips/$trip/city', 'Proba 2'), allowed: true);

  await _check('the same person comes back with name and number', () => _as(stranger, 'PATCH', 'trips/$trip', {
        'claims/${stranger.uid}': key,
        'access/${stranger.uid}': 'ana',
      }), allowed: true);
  await _check('... and then reads the trip', () => _as(stranger, 'GET', 'trips/$trip'), allowed: true);

  // As much away as the rules let go.
  await _as(member, 'DELETE', 'codes/$code');
  await _as(member, 'DELETE', 'blobs/$trip/p1');
  await _as(member, 'PATCH', 'trips/$trip', {
    'country': null, 'start': null, 'end': null, 'people': null, 'keys': null,
    'requests': null, 'claims': null, 'city': null,
  });
  await _as(member, 'DELETE', 'trips/$trip'); // goes only while the rules are open
  print(_failed == 0 ? 'All checks passed.' : '$_failed checks failed.');
  _client.close();
  exit(_failed == 0 ? 0 : 1);
}
