import 'dart:js_interop';

import 'package:virulja/ui/app.dart';
import 'package:virulja/ui/cloud.dart';
import 'package:virulja/ui/install.dart';
import 'package:virulja/ui/store.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final store = await AppStore.open();
  final config = await loadOnlineConfig(); // null: everything stays on this phone
  final cloud = config == null ? null : CloudSync(config, store);
  final app = ViruljaApp(web.document.querySelector('#app')!, store, cloud);
  app.render();
  cloud?.start();

  // A newer version of the app arrives by itself; show it on the home screen,
  // never in the middle of filling in a form.
  var updateWaiting = false;
  void reloadIfIdle() {
    if (updateWaiting && app.isIdle) web.window.location.reload();
  }

  web.window.addEventListener(
    'hashchange',
    ((web.Event event) {
      reloadIfIdle();
    }).toJS,
  );
  registerServiceWorker(updateReady: () {
    updateWaiting = true;
    reloadIfIdle();
  }); // lets the installed app work offline
}
