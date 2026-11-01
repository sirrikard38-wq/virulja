import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:virulja/src/domain/models.dart';
import 'package:virulja/src/domain/reminders.dart';
import 'package:virulja/src/domain/session.dart';

import 'web_push.dart';

/// Run once a day by .github/workflows/remind.yml: sends the phones that turned
/// notifications on the reminders due today. `--test` sends every such phone one
/// message right away.
///
/// The repo is public and so are the logs of its runs: print only counts.
const String _contact = 'https://sirrikard38-wq.github.io/virulja/';
const int _keepForSeconds = 86400;

final HttpClient _client = HttpClient();

Future<({int status, String body})> _call(
  String method,
  Uri url, {
  Map<String, String> headers = const {},
  List<int>? body,
}) async {
  final request = await _client.openUrl(method, url);
  headers.forEach(request.headers.set);
  if (body != null) request.add(body);
  final response = await request.close();
  return (
    status: response.statusCode,
    body: await response.transform(utf8.decoder).join(),
  );
}

String _secret(String name) {
  final value = Platform.environment[name] ?? '';
  if (value.isEmpty) throw StateError('$name is missing');
  return value;
}

Future<String> _token(OnlineConfig config, String refreshToken) async {
  final reply = await _call(
    'POST',
    Uri.parse('${OnlineConfig.tokenBase}/v1/token?key=${config.apiKey}'),
    headers: {'Content-Type': 'application/x-www-form-urlencoded'},
    body: utf8.encode('grant_type=refresh_token&refresh_token=$refreshToken'),
  );
  if (reply.status != 200) throw StateError('sign-in answered ${reply.status}');
  return (jsonDecode(reply.body) as Map)['id_token'] as String;
}

/// Sends one message and says what the phone's push service answered.
Future<int> _send(Map<dynamic, dynamic> device, Object message, Uint8List privateKey) async {
  final endpoint = device['endpoint'] as String;
  final reply = await _call(
    'POST',
    Uri.parse(endpoint),
    headers: {
      'Authorization': vapidHeader(endpoint, privateKey, _contact, DateTime.now()),
      'Content-Encoding': 'aes128gcm',
      'Content-Type': 'application/octet-stream',
      'TTL': '$_keepForSeconds',
    },
    body: encryptPush(
      utf8.encode(jsonEncode(message)),
      fromBase64Url(device['p256dh'] as String),
      fromBase64Url(device['auth'] as String),
    ),
  );
  return reply.status;
}

Future<void> main(List<String> args) async {
  final testing = args.contains('--test');
  final config = OnlineConfig.tryParse(File('web/online.json').readAsStringSync())!;
  final privateKey = fromBase64Url(_secret('VAPID_PRIVATE'));
  final token = await _token(config, _secret('ROBOT_TOKEN'));

  Uri address(String path) =>
      Uri.parse('${config.databaseUrl}/$path.json?auth=$token');

  final reply = await _call('GET', address('push'));
  if (reply.status != 200) throw StateError('database answered ${reply.status}');
  final devices = (jsonDecode(reply.body) as Map?) ?? const {};

  final now = today();
  var sent = 0, failed = 0, gone = 0;
  for (final entry in devices.entries) {
    final device = entry.value as Map;
    final trips = (device['trips'] as Map?) ?? const {};
    final messages = [
      if (testing) {'title': 'VIRULJA', 'body': 'Obavijesti rade.', 'route': '#/'},
      if (!testing)
        for (final trip in trips.entries)
          if (reminderText(parseDay((trip.value as Map)['start'] as String), now)
              case final text?)
            {
              'title': (trip.value as Map)['city'],
              'body': text,
              'route': '#/p/${trip.key}',
            },
    ];
    for (final message in messages) {
      final status = await _send(device, message, privateKey);
      if (status == 404 || status == 410) {
        // That phone turned notifications off or no longer has the app.
        gone++;
        await _call('DELETE', address('push/${entry.key}'));
        break;
      }
      if (status >= 200 && status < 300) {
        sent++;
      } else {
        failed++;
        stdout.writeln('A push service answered $status');
      }
    }
  }
  stdout.writeln('Phones: ${devices.length}, sent: $sent, failed: $failed, gone: $gone');
  _client.close();
  if (failed > 0) exitCode = 1;
}
