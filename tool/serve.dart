// Serves build/ : dart run tool/serve.dart [port] [--lan]
//
// By default only this computer can reach it (http://localhost:8090).
// With --lan it listens on the local network too, so a phone on the same
// Wi-Fi can open http://<this-computer's-ip>:8090 .
import 'dart:io';

const _types = {
  'html': 'text/html; charset=utf-8',
  'css': 'text/css; charset=utf-8',
  'js': 'application/javascript; charset=utf-8',
  'map': 'application/json',
  'json': 'application/json',
  'webmanifest': 'application/manifest+json',
  'png': 'image/png',
  'svg': 'image/svg+xml',
};

Future<void> main(List<String> args) async {
  final lan = args.contains('--lan');
  final numbers = args.where((a) => int.tryParse(a) != null);
  final port = numbers.isNotEmpty ? int.parse(numbers.first) : 8090;
  final server = await HttpServer.bind(
    lan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4,
    port,
  );
  // build/ next to this tool, so the server works from any folder.
  final project = File.fromUri(Platform.script).parent.parent.path;
  final root = '$project${Platform.pathSeparator}build';
  stdout.writeln('Serving build/ at http://localhost:$port'
      '${lan ? '  (and on your local network)' : ''}');
  await for (final request in server) {
    final path = request.uri.path == '/' ? '/index.html' : request.uri.path;
    final file = File('$root${path.replaceAll('/', Platform.pathSeparator)}');
    // Refuse path traversal outside build/.
    if (path.contains('..') || !await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    final ext = path.split('.').last;
    request.response.headers.contentType =
        ContentType.parse(_types[ext] ?? 'application/octet-stream');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }
}
