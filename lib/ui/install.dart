import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'update_check.dart';

/// Registers the service worker, which saves the app on the phone so it opens
/// with no connection. Quietly does nothing where it is not allowed (an address
/// that is not https or localhost, or an old browser).
///
/// [updateReady] is called when a newer version of the app has taken over from
/// the one this page is showing (never on the very first install).
Future<void> registerServiceWorker({void Function()? updateReady}) async {
  try {
    final container = web.window.navigator.serviceWorker;
    final hadOlderVersion = container.controller != null;
    if (hadOlderVersion && updateReady != null) {
      container.addEventListener(
        'controllerchange',
        ((web.Event event) {
          _notifyIfNewer(updateReady); // checks in the background
        }).toJS,
      );
    }
    await container.register('sw.js'.toJS).toDart;
  } on Object {
    // The app works without it; it just cannot be used offline.
  }
}

Future<void> _notifyIfNewer(void Function() updateReady) async {
  var needed = true; // when in doubt, show the newest
  try {
    final keys = await web.window.caches.keys().toDart;
    final script = web.document.querySelector('script[src*="main.dart.js"]');
    needed = updateNeeded(
      runningBuild: buildOfScriptSrc(script?.getAttribute('src')),
      cacheNames: [for (final key in keys.toDart) key.toDart],
    );
  } on Object {
    // The caches cannot be read: reload.
  }
  if (needed) updateReady();
}

/// What the group screen should offer to help install the app.
enum InstallHelp {
  /// Nothing: it is already installed, or this browser cannot install it.
  none,

  /// Android / desktop Chrome: a real "Install app" button.
  prompt,

  /// iPhone / iPad: there is no button; people must use Share.
  ios,
}

JSObject? _installEvent;

/// Remembers the browser's "install" offer (Chrome fires `beforeinstallprompt`)
/// and calls [changed] when the offer appears or the app gets installed.
void watchForInstall(void Function() changed) {
  web.window.addEventListener(
    'beforeinstallprompt',
    ((web.Event event) {
      event.preventDefault(); // keep the offer for our own button
      _installEvent = event;
      changed();
    }).toJS,
  );
  web.window.addEventListener(
    'appinstalled',
    ((web.Event event) {
      _installEvent = null;
      changed();
    }).toJS,
  );
}

/// True when the app is running from the home screen, not in a browser tab.
bool get isInstalledApp {
  try {
    if (web.window.matchMedia('(display-mode: standalone)').matches) return true;
    final standalone = (web.window.navigator as JSObject).getProperty('standalone'.toJS);
    return standalone.dartify() == true; // iOS Safari's own flag
  } on Object {
    return false;
  }
}

bool get _isIos {
  final nav = web.window.navigator;
  final ua = nav.userAgent;
  if (RegExp(r'iPhone|iPad|iPod').hasMatch(ua)) return true;
  // iPadOS pretends to be a Mac; a Mac with a touch screen is an iPad.
  return ua.contains('Macintosh') && nav.maxTouchPoints > 1;
}

/// Which install help to show right now.
InstallHelp get installHelp {
  if (isInstalledApp) return InstallHelp.none;
  if (_installEvent != null) return InstallHelp.prompt;
  if (_isIos) return InstallHelp.ios;
  return InstallHelp.none;
}

/// Shows the browser's own install dialog.
void promptInstall() {
  final event = _installEvent;
  if (event == null) return;
  event.callMethod('prompt'.toJS);
}
