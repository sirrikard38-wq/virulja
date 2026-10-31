import 'dart:js_interop';

import 'package:virulja/ui/app.dart';
import 'package:virulja/ui/install.dart';
import 'package:virulja/ui/store.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  final store = await AppStore.open();
  final app = ViruljaApp(web.document.querySelector('#app')!, store);
  app.render();

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
