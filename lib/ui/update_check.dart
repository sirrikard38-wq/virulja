// Is the page this window shows older than the app that has just taken over? (No
// browser needed, so it can be tested.)
//
// After a deploy the old service worker still serves the page, but it fetches the
// page from the network first, so the page is often ALREADY the newest build when
// the new worker takes over a moment later. Reloading it then shows nothing new.

/// The names of the caches the service worker keeps start with this, then the
/// build stamp (`virulja-1792130584657`, see web/sw.js).
const String cachePrefix = 'virulja-';

/// The build stamp in the address of a script ("main.dart.js?v=1792130584657"), or
/// null when it has none.
String? buildOfScriptSrc(String? src) {
  if (src == null) return null;
  return RegExp(r'[?&]v=([^&#]+)').firstMatch(src)?.group(1);
}

/// Does the page have to reload to show the app that has taken over?
///
/// Build stamps are the time of the build, so a bigger one is a newer build. In
/// any doubt (the page does not know its build, no cache of the app can be seen)
/// it reloads.
bool updateNeeded({required String? runningBuild, required List<String> cacheNames}) {
  final running = int.tryParse(runningBuild ?? '');
  final builds = [
    for (final name in cacheNames)
      if (name.startsWith(cachePrefix)) int.tryParse(name.substring(cachePrefix.length)),
  ].whereType<int>().toList();
  if (running == null || builds.isEmpty) return true;
  return builds.any((build) => build > running);
}
