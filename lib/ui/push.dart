import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// False where a page cannot get notifications; on an iPhone that means the app
/// has not been added to the home screen.
bool get pushWorks =>
    web.window.has('PushManager') &&
    web.window.has('Notification') &&
    web.window.navigator.has('serviceWorker');

const Duration _workerWait = Duration(seconds: 10);

Future<web.PushManager> _manager() async {
  final worker =
      await web.window.navigator.serviceWorker.ready.toDart.timeout(_workerWait);
  return worker.pushManager;
}

String _text(web.PushSubscription subscription, String name) {
  final key = subscription.getKey(name)!.toDart.asUint8List();
  return base64Url.encode(key).replaceAll('=', '');
}

Map<String, String> _device(web.PushSubscription subscription) => {
      'endpoint': subscription.endpoint,
      'p256dh': _text(subscription, 'p256dh'),
      'auth': _text(subscription, 'auth'),
    };

/// This phone's address for notifications, or null when they are off.
Future<Map<String, String>?> pushDevice() async {
  if (!pushWorks || web.Notification.permission != 'granted') return null;
  final subscription = await (await _manager()).getSubscription().toDart;
  return subscription == null ? null : _device(subscription);
}

/// Asks the phone for permission and turns notifications on. Must be called
/// inside a tap. Null when the person says no.
Future<Map<String, String>?> turnOnPush(String publicKey) async {
  final answer = await web.Notification.requestPermission().toDart;
  if (answer.toDart != 'granted') return null;
  final Uint8List key = base64Url.decode(base64Url.normalize(publicKey));
  final subscription = await (await _manager())
      .subscribe(web.PushSubscriptionOptionsInit(
        userVisibleOnly: true,
        applicationServerKey: key.toJS,
      ))
      .toDart;
  return _device(subscription);
}

Future<void> turnOffPush() async {
  final subscription = await (await _manager()).getSubscription().toDart;
  await subscription?.unsubscribe().toDart;
}
