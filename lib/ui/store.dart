import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import '../src/domain/session.dart';
import '../src/domain/tree.dart';

/// IndexedDB, the browser's storage for big things like pictures.
class _Database {
  _Database(this._db);

  static const String _dataStore = 'data';
  static const String _blobStore = 'blobs';

  final web.IDBDatabase _db;

  static Future<_Database?> open() {
    final done = Completer<_Database?>();
    try {
      final request = web.window.indexedDB.open('virulja', 1);
      request.onupgradeneeded = ((web.Event event) {
        final db = request.result as web.IDBDatabase;
        db.createObjectStore(_dataStore);
        db.createObjectStore(_blobStore);
      }).toJS;
      request.onsuccess = ((web.Event event) {
        done.complete(_Database(request.result as web.IDBDatabase));
      }).toJS;
      request.onerror = ((web.Event event) {
        done.complete(null);
      }).toJS;
    } on Object {
      done.complete(null);
    }
    return done.future;
  }

  Future<JSAny?> _read(String store, String key) {
    final done = Completer<JSAny?>();
    final request =
        _db.transaction(store.toJS, 'readonly').objectStore(store).get(key.toJS);
    request.onsuccess = ((web.Event event) {
      done.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event event) {
      done.complete(null);
    }).toJS;
    return done.future;
  }

  Future<void> _write(String store, void Function(web.IDBObjectStore) change) {
    final done = Completer<void>();
    final transaction = _db.transaction(store.toJS, 'readwrite');
    transaction.oncomplete = ((web.Event event) {
      done.complete();
    }).toJS;
    transaction.onabort = ((web.Event event) {
      if (!done.isCompleted) done.completeError(StateError('save failed'));
    }).toJS;
    transaction.onerror = ((web.Event event) {
      if (!done.isCompleted) done.completeError(StateError('save failed'));
    }).toJS;
    change(transaction.objectStore(store));
    return done.future;
  }

  Future<String?> readText(String key) async {
    final value = await _read(_dataStore, key);
    return (value as JSString?)?.toDart;
  }

  Future<void> writeText(String key, String text) =>
      _write(_dataStore, (store) => store.put(text.toJS, key.toJS));

  Future<web.Blob?> readBlob(String id) async =>
      await _read(_blobStore, id) as web.Blob?;

  Future<void> writeBlob(String id, web.Blob blob) =>
      _write(_blobStore, (store) => store.put(blob, id.toJS));

  Future<void> deleteBlob(String id) =>
      _write(_blobStore, (store) => store.delete(id.toJS));
}

/// Everything saved on this phone: the data of the app and the pictures and
/// sounds. Where the browser allows no storage (a private window) it all stays
/// in memory, so the app still runs.
class AppStore implements KeyValueStore {
  AppStore._(this.data, this._mirrors, this._db);

  static const String _dataKey = 'app';
  static const String _mirrorsKey = 'mirrors';
  static const Duration _saveDelay = Duration(milliseconds: 200);

  final AppData data;
  final Map<String, TripMirror> _mirrors;
  final _Database? _db;
  final Random _random = Random.secure();
  final Map<String, web.Blob> _memoryBlobs = {};
  final Map<String, String> _memoryValues = {};
  final Map<String, String> _addresses = {};
  Timer? _saveTimer;

  static Future<AppStore> open() async {
    final db = await _Database.open();
    final text = await db?.readText(_dataKey);
    var data = AppData();
    if (text != null) {
      try {
        data = AppData.fromJson(jsonDecode(text) as Json);
      } on Object {
        // Never overwrite something that cannot be read: keep it aside.
        await db?.writeText('damaged-${DateTime.now().millisecondsSinceEpoch}', text);
      }
    }
    final mirrors = <String, TripMirror>{};
    final saved = await db?.readText(_mirrorsKey);
    if (saved != null) {
      try {
        (jsonDecode(saved) as Json).forEach((id, value) {
          mirrors[id] = TripMirror.fromJson(value as Json);
        });
      } on Object {
        // Without the mirrors the next sync compares everything again.
        mirrors.clear();
      }
    }
    final store = AppStore._(data, mirrors, db);
    store._keepStorage();
    store._saveWhenLeaving();
    return store;
  }

  /// Asks the browser not to clear the app's storage when the phone runs low.
  void _keepStorage() {
    try {
      web.window.navigator.storage.persist();
    } on Object {
      // The app works without it.
    }
  }

  void _saveWhenLeaving() {
    web.document.addEventListener(
      'visibilitychange',
      ((web.Event event) {
        if (web.document.visibilityState == 'hidden') _saveNow();
      }).toJS,
    );
  }

  /// Saves soon, so a burst of changes is one write.
  void save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDelay, _saveNow);
  }

  void _saveNow() {
    _saveTimer?.cancel();
    _db?.writeText(_dataKey, jsonEncode(data.toJson()));
    _db?.writeText(
      _mirrorsKey,
      jsonEncode({
        for (final entry in _mirrors.entries) entry.key: entry.value.toJson(),
      }),
    );
  }

  /// What this phone last saw of a trip in the cloud.
  TripMirror mirrorOf(String tripId) => _mirrors[tripId] ??= TripMirror();

  void forgetMirror(String tripId) => _mirrors.remove(tripId);

  String _randomHex(int length) => [
        for (var i = 0; i < length; i++) _random.nextInt(16).toRadixString(16),
      ].join();

  /// A new id. Ids sort by age, so lists keep their order on every phone.
  String newId() {
    final now = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${now.padLeft(9, '0')}${_randomHex(8)}';
  }

  /// An id nobody can guess: having it is what lets someone into a trip.
  String newSecretId() => _randomHex(32);

  @override
  Future<String?> readValue(String key) async =>
      _memoryValues[key] ?? await _db?.readText(key);

  @override
  Future<void> writeValue(String key, String value) async {
    _memoryValues[key] = value;
    await _db?.writeText(key, value);
  }

  Future<void> putBlob(String id, web.Blob blob) async {
    final db = _db;
    if (db == null) {
      _memoryBlobs[id] = blob;
    } else {
      await db.writeBlob(id, blob);
    }
  }

  Future<web.Blob?> getBlob(String id) async =>
      _memoryBlobs[id] ?? await _db?.readBlob(id);

  Future<void> removeBlob(String id) async {
    _memoryBlobs.remove(id);
    final address = _addresses.remove(id);
    if (address != null) web.URL.revokeObjectURL(address);
    await _db?.deleteBlob(id);
  }

  /// An address an <img> can show the stored picture from.
  Future<String?> blobAddress(String id) async {
    final known = _addresses[id];
    if (known != null) return known;
    final blob = await getBlob(id);
    if (blob == null) return null;
    return _addresses[id] = web.URL.createObjectURL(blob);
  }
}
