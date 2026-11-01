import 'dart:convert';

/// One answer to a web request.
class HttpReply {
  const HttpReply(this.status, this.body);

  final int status;
  final String body;

  bool get ok => status >= 200 && status < 300;
}

/// The only thing the cloud code needs from the web: send a request, get the
/// answer. The browser version is in `lib/ui/cloud.dart`; tests use a fake.
abstract interface class JsonHttp {
  Future<HttpReply> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  });
}

/// Where this phone keeps its sign-in.
abstract interface class KeyValueStore {
  Future<String?> readValue(String key);

  Future<void> writeValue(String key, String value);
}

/// Something went wrong talking to the cloud.
class OnlineException implements Exception {
  const OnlineException(this.message);

  final String message;

  @override
  String toString() => 'OnlineException: $message';
}

/// Where the shared data lives: a Firebase Realtime Database. Read from
/// `web/online.json`; without it the app simply stays on this phone.
class OnlineConfig {
  const OnlineConfig({required this.databaseUrl, required this.apiKey});

  static const String authBase = 'https://identitytoolkit.googleapis.com';
  static const String tokenBase = 'https://securetoken.googleapis.com';

  /// `https://...firebasedatabase.app` (no trailing slash).
  final String databaseUrl;

  /// The Firebase web API key. It is not a secret: it only says which project
  /// the sign-in belongs to. The database rules are what protect the data.
  final String apiKey;

  /// Reads `online.json`. Null when it is empty, unfinished or not valid.
  static OnlineConfig? tryParse(String text) {
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      var url = ((json['databaseUrl'] as String?) ?? '').trim();
      while (url.endsWith('/')) {
        url = url.substring(0, url.length - 1);
      }
      final key = ((json['apiKey'] as String?) ?? '').trim();
      if (url.isEmpty || key.isEmpty || !url.startsWith('https://')) return null;
      return OnlineConfig(databaseUrl: url, apiKey: key);
    } on Object {
      return null;
    }
  }
}

/// The anonymous Firebase sign-in: no password, no account to make. The first
/// time, Firebase hands out an id; it is kept on the phone and the short-lived
/// token that goes with it is renewed when it runs out.
class FirebaseSession {
  FirebaseSession(this._config, this._http, this._storage, {DateTime Function()? now})
      : _now = now ?? DateTime.now;

  static const String storageKey = 'session';

  final OnlineConfig _config;
  final JsonHttp _http;
  final KeyValueStore _storage;
  final DateTime Function() _now;

  bool _loaded = false;
  String? _id;
  String? _refreshToken;
  String? _token;
  DateTime _expires = DateTime.fromMillisecondsSinceEpoch(0);
  Future<String>? _asking;

  /// A valid token, signing in or renewing as needed. Requests made at the same
  /// moment share one answer, so they never each sign in as a new person.
  Future<String> token() =>
      _asking ??= _obtain().whenComplete(() => _asking = null);

  Future<String> _obtain() async {
    await _load();
    final token = _token;
    if (token != null &&
        _now().isBefore(_expires.subtract(const Duration(minutes: 1)))) {
      return token;
    }
    if (_refreshToken != null && await _renew()) return _token!;
    await _signUp();
    return _token!;
  }

  /// This phone's sign-in id, once signed in.
  String? get uid => _id;

  /// Forgets the token, so the next request gets a fresh one.
  void tokenRefused() {
    _token = null;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _storage.readValue(storageKey);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, Object?>;
      _id = json['id'] as String?;
      _refreshToken = json['refreshToken'] as String?;
    } on Object {
      _id = null;
      _refreshToken = null;
    }
  }

  Future<void> _save() => _storage.writeValue(
      storageKey, jsonEncode({'id': _id, 'refreshToken': _refreshToken}));

  /// Gets a new token with the saved refresh token. False when Firebase says the
  /// sign-in no longer exists (then a new one is made); anything else wrong (no
  /// connection, a server error) is an error.
  Future<bool> _renew() async {
    final reply = await _http.send(
      'POST',
      Uri.parse('${OnlineConfig.tokenBase}/v1/token')
          .replace(queryParameters: {'key': _config.apiKey}),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'grant_type=refresh_token&refresh_token='
          '${Uri.encodeQueryComponent(_refreshToken!)}',
    );
    if (reply.status == 400 || reply.status == 401) {
      _refreshToken = null;
      return false;
    }
    if (!reply.ok) throw OnlineException('token renewal failed (${reply.status})');
    final json = jsonDecode(reply.body) as Map<String, Object?>;
    _take(
      id: (json['user_id'] as String?) ?? _id,
      token: json['id_token'] as String?,
      refreshToken: (json['refresh_token'] as String?) ?? _refreshToken,
      expiresInSeconds: json['expires_in'],
    );
    await _save();
    return true;
  }

  Future<void> _signUp() async {
    final reply = await _http.send(
      'POST',
      Uri.parse('${OnlineConfig.authBase}/v1/accounts:signUp')
          .replace(queryParameters: {'key': _config.apiKey}),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'returnSecureToken': true}),
    );
    if (!reply.ok) throw OnlineException('sign-in failed (${reply.status})');
    final json = jsonDecode(reply.body) as Map<String, Object?>;
    _take(
      id: json['localId'] as String?,
      token: json['idToken'] as String?,
      refreshToken: json['refreshToken'] as String?,
      expiresInSeconds: json['expiresIn'],
    );
    await _save();
  }

  void _take({
    required String? id,
    required String? token,
    required String? refreshToken,
    required Object? expiresInSeconds,
  }) {
    if (id == null || token == null || refreshToken == null) {
      throw const OnlineException('sign-in answer is incomplete');
    }
    _id = id;
    _token = token;
    _refreshToken = refreshToken;
    final seconds = int.tryParse('$expiresInSeconds') ?? 3600;
    _expires = _now().add(Duration(seconds: seconds));
  }
}
