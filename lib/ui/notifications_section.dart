import 'dart:async';

import 'package:web/web.dart' as web;

import 'context.dart';
import 'dom.dart';
import 'push.dart';

/// The switch for trip reminders on this phone.
web.HTMLElement notificationsSection(Ui ui) {
  if (!pushWorks) {
    return el('p', cls: 'soft pad', text: 'Za obavijesti prvo stavi aplikaciju na '
        'početni zaslon. iPhone treba imati iOS 16.4 ili noviji.');
  }
  var on = false;
  late final web.HTMLElement toggle;

  Future<void> tap() async {
    final cloud = ui.cloud;
    final key = cloud?.pushKey;
    if (cloud == null || key == null) return;
    try {
      if (on) {
        await turnOffPush();
        await cloud.removePushDevice();
      } else {
        final Map<String, String>? device;
        try {
          device = await turnOnPush(key);
        } on Object {
          ui.toast('Mobitel nije dopustio prijavu za obavijesti.');
          return;
        }
        if (device == null) {
          ui.toast('Obavijesti nisu dopuštene u postavkama mobitela.');
          return;
        }
        await cloud.savePushDevice(device);
        ui.toast('Obavijesti su uključene.');
      }
    } on Object {
      ui.toast('Mobitel je prijavljen, ali spremanje nije uspjelo.');
    }
    ui.rerender();
  }

  toggle = button(cls: 'secondary wide', text: 'Uključi obavijesti', onTap: tap);
  unawaited(pushDevice().then((device) {
    on = device != null;
    if (on) toggle.textContent = 'Isključi obavijesti';
  }).catchError((Object _) {}));
  return el('div', children: [
    el('p', cls: 'soft pad', text: 'Podsjetnik za putovanje'),
    toggle,
  ]);
}
