import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/trip_events.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'push.dart';
import 'widgets.dart';

/// Whether this phone is signed up for notifications, as last seen, so that a
/// redraw does not blink.
bool? _signedUp;

final Set<String> _everyKind = {for (final notice in Notice.values) notice.name};

/// The kinds of notification this phone gets: from every trip, or with [trip]
/// from that one only. It stays folded until "Obavijesti" is tapped.
web.HTMLElement notificationsSection(Ui ui, {Trip? trip}) {
  final open = ui.noticesOpen;
  final heading = button(
    cls: open ? 'fold open' : 'fold',
    onTap: () {
      ui.noticesOpen = !open;
      ui.rerender();
    },
    children: [
      el('span', cls: 'section',
          text: trip == null ? tr('Obavijesti') : tr('Obavijesti za ovo putovanje')),
      icon('plus', size: 22),
    ],
  )..setAttribute('aria-expanded', '$open');
  if (!open) return heading;
  if (!pushWorks) {
    return el('div', children: [
      heading,
      el('p', cls: 'soft pad', text: tr('Za obavijesti prvo stavi aplikaciju na početni zaslon. iPhone treba imati iOS 16.4 ili noviji.')),
    ]);
  }
  final cloud = ui.cloud!;
  final key = cloud.pushKey!;
  final everywhere = ui.data.noticesOff;
  Set<String> here() => trip == null
      ? everywhere
      : ui.data.tripNoticesOff.putIfAbsent(trip.id, () => {});
  final body = el('div', cls: 'ticks');

  late void Function() fill;

  Future<void> tellSender() async {
    try {
      final device = await pushDevice();
      if (device != null) await cloud.savePushDevice(device);
    } on Object {
      ui.toast(tr('Mobitel je prijavljen, ali spremanje nije uspjelo.'));
    }
  }

  /// Signs this phone up inside the tap, which a phone asks for. Then [choose]
  /// says what it should get.
  Future<void> signUp(void Function() choose) async {
    final Map<String, String>? device;
    try {
      device = await turnOnPush(key);
    } on Object {
      ui.toast(tr('Mobitel nije dopustio prijavu za obavijesti.'));
      return;
    }
    if (device == null) {
      ui.toast(tr('Obavijesti nisu dopuštene u postavkama mobitela.'));
      return;
    }
    _signedUp = true;
    choose();
    ui.store.save();
    fill();
    try {
      await cloud.savePushDevice(device);
      ui.toast(tr('Obavijesti su uključene.'));
    } on Object {
      ui.toast(tr('Mobitel je prijavljen, ali spremanje nije uspjelo.'));
    }
  }

  void change(void Function() choose) {
    if (_signedUp != true) {
      unawaited(signUp(choose));
      return;
    }
    choose();
    ui.store.save();
    fill();
    unawaited(tellSender());
  }

  Future<void> signOut() async {
    try {
      await turnOffPush();
      await cloud.removePushDevice();
    } on Object {
      ui.toast(tr('Nema veze. Pokušaj ponovno.'));
      return;
    }
    _signedUp = false;
    fill();
  }

  fill = () {
    final on = _signedUp == true;
    bool locked(Notice notice) => trip != null && everywhere.contains(notice.name);
    bool gets(Notice notice) => on && !everywhere.contains(notice.name) && !here().contains(notice.name);
    final free = Notice.values.where((notice) => !locked(notice));
    final all = free.isNotEmpty && free.every(gets);
    body.textContent = '';
    for (final part in [
      el('p', cls: 'small', text: trip == null
          ? tr('Vrijedi za sva putovanja.')
          : tr('Vrijedi samo za ovo putovanje.')),
      tick(tr('Primaj sve obavijesti'), all, () => change(() {
            here().clear();
            if (all) here().addAll(_everyKind);
          })),
      for (final notice in Notice.values)
        tick(notice.label, gets(notice), () => change(() {
              if (!on) {
                here()
                  ..addAll(_everyKind)
                  ..remove(notice.name);
              } else if (!here().remove(notice.name)) {
                here().add(notice.name);
              }
            }), locked: locked(notice)),
      if (Notice.values.any(locked))
        el('p', cls: 'small', text: tr('Sivo je isključeno za sva putovanja u Postavkama.')),
      if (trip == null && on)
        button(cls: 'text-button', text: tr('Isključi obavijesti na ovom mobitelu'), onTap: signOut),
    ]) {
      body.append(part);
    }
  };

  fill();
  unawaited(pushDevice().then((device) {
    final now = device != null;
    if (now == _signedUp) return;
    _signedUp = now;
    fill();
  }).catchError((Object _) {}));
  return el('div', children: [heading, body]);
}
