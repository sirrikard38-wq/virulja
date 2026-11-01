import 'dart:convert';
import 'dart:io';

import 'package:virulja/src/domain/session.dart';

import 'web_push.dart';

/// Run once: makes the notification keys and the sender's own sign-in. The two
/// secrets go to the file named on the command line, which must stay out of the
/// repo; the public key and the sender's id are printed, for `web/online.json`
/// and `firebase/database.rules.json`.
Future<void> main(List<String> args) async {
  final config = OnlineConfig.tryParse(File('web/online.json').readAsStringSync())!;
  final privateKey = newPrivateKey();

  final client = HttpClient();
  final request = await client.postUrl(Uri.parse(
      '${OnlineConfig.authBase}/v1/accounts:signUp?key=${config.apiKey}'));
  request.headers.contentType = ContentType.json;
  request.write(jsonEncode({'returnSecureToken': true}));
  final response = await request.close();
  final json = jsonDecode(await response.transform(utf8.decoder).join()) as Map;
  client.close();
  if (response.statusCode != 200) throw StateError('sign-up answered ${response.statusCode}');

  File(args.first).writeAsStringSync('VAPID_PRIVATE\n'
      '${toBase64Url(privateKey)}\n\n'
      'ROBOT_TOKEN\n'
      '${json['refreshToken']}\n');
  stdout.writeln('pushKey ${toBase64Url(publicKeyOf(privateKey))}');
  stdout.writeln('robot ${json['localId']}');
}
