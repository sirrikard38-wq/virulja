import 'dart:js_interop';

import 'package:virulja/ui/app.dart';
import 'package:virulja/ui/cloud.dart';
import 'package:virulja/ui/install.dart';
import 'package:virulja/ui/splash.dart';
import 'package:virulja/ui/store.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  // Opened anew (not a reload for a newer version): VIRULJA comes up in the
  // middle, and the app starts on the trips.
  var fresh = true;
  try {
    fresh = web.window.sessionStorage.getItem('opened') == null;
    web.window.sessionStorage.setItem('opened', '1');
  } on Object {
    // No storage: count it as a fresh start.
  }
  if (fresh) {
    // Through history, which fires no change of address before the app
    // listens: a first step under Putovanja, then Putovanja.
    web.window.history.replaceState({'step': 0}.jsify(), '', '#/start');
    web.window.history.pushState({'step': 1, 'afterStart': true}.jsify(), '', '#/');
    showSplash();
  }
  final store = await AppStore.open();
  final config = await loadOnlineConfig(); // null: everything stays on this phone
  final cloud = config == null ? null : CloudSync(config, store);
  final app = ViruljaApp(web.document.querySelector('#app')!, store, cloud);
  app.render();
  cloud?.start();

  // A newer version of the app arrives by itself; show it at the next change of
  // screen, never in the middle of filling in a form.
  var updateWaiting = false;
  void reloadIfIdle() {
    if (updateWaiting && app.isIdle) web.window.location.reload();
  }

  // On the next change of screen, or when the app comes back to the screen.
  web.window.addEventListener(
    'hashchange',
    ((web.Event event) {
      reloadIfIdle();
    }).toJS,
  );
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event event) {
      if (web.document.visibilityState == 'visible') reloadIfIdle();
    }).toJS,
  );
  registerServiceWorker(updateReady: () {
    updateWaiting = true;
    reloadIfIdle();
  }); // lets the installed app work offline
}
