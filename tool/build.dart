// Builds the static site into build/: dart run tool/build.dart
import 'dart:io';

Future<void> main() async {
  final out = Directory('build')..createSync(recursive: true);
  File('web/styles.css').copySync('${out.path}/styles.css');
  File('web/manifest.webmanifest').copySync('${out.path}/manifest.webmanifest');
  // Where the shared data lives (empty = everything stays on the phone).
  File('web/online.json').copySync('${out.path}/online.json');
  _copyDir(Directory('web/icons'), Directory('${out.path}/icons'));

  // GitHub Pages lets browsers keep files for 10 minutes. A build stamp on the
  // script and stylesheet addresses makes every deploy load fresh copies, and
  // the same stamp names the offline cache in the service worker.
  final stamp = DateTime.now().millisecondsSinceEpoch;
  File('${out.path}/index.html').writeAsStringSync(File('web/index.html')
      .readAsStringSync()
      .replaceAll('href="styles.css"', 'href="styles.css?v=$stamp"')
      .replaceAll('src="main.dart.js"', 'src="main.dart.js?v=$stamp"'));
  File('${out.path}/sw.js').writeAsStringSync(
      File('web/sw.js').readAsStringSync().replaceAll('__BUILD__', '$stamp'));

  final result = await Process.run(
    Platform.resolvedExecutable,
    ['compile', 'js', '-O2', 'web/main.dart', '-o', '${out.path}/main.dart.js'],
  );
  stdout.write(result.stdout);
  stderr.write(result.stderr);
  if (result.exitCode != 0) exit(result.exitCode);
  stdout.writeln('Built into ${out.path}/');
}

/// Copies the files of [from] into [to] (does nothing if [from] is missing).
void _copyDir(Directory from, Directory to) {
  if (!from.existsSync()) return;
  to.createSync(recursive: true);
  for (final file in from.listSync().whereType<File>()) {
    file.copySync('${to.path}/${file.uri.pathSegments.last}');
  }
}
