import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/models.dart';
import '../src/domain/session.dart';
import '../src/domain/tree.dart';
import '../src/domain/trip_tree.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// Sends the invitation for [trip]: the phone's own sharing menu where there is
/// one, otherwise the link is copied.
Future<void> shareInvite(Ui ui, Trip trip) async {
  final link = ui.inviteLink(trip);
  final text = 'Pridruži se putovanju ${trip.city} u aplikaciji VIRULJA';
  try {
    await web.window.navigator
        .share(web.ShareData(title: 'VIRULJA', text: text, url: link))
        .toDart;
    return;
  } on Object {
    // No sharing menu here, or it was closed: copying still helps.
  }
  try {
    await web.window.navigator.clipboard.writeText(link).toDart;
    ui.toast('Link pozivnice je kopiran.');
  } on Object {
    web.window.prompt('Kopiraj link pozivnice:', link);
  }
}

/// The trip id inside a pasted invitation link, or null.
String? inviteIdIn(String text) {
  final link = RegExp(r'pridruzi/([0-9a-z]+)').firstMatch(text);
  if (link != null) return link[1];
  final bare = text.trim();
  return RegExp(r'^[0-9a-f]{16,}$').hasMatch(bare) ? bare : null;
}

web.HTMLElement _message(String title, String text, {web.Node? action}) => el(
      'div',
      children: [
        topBar(title, plain: true),
        el('p', cls: 'soft pad', text: text),
        if (action != null) action,
      ],
    );

web.HTMLElement _invitation(
  Ui ui,
  ({CloudTrip trip, Tree tree}) invited,
) {
  final cloud = invited.trip;
  final trip = cloud.trip;

  void join({String? claimedId}) {
    ui.cloud!.join(invited, claimedId: claimedId);
    ui.openTrip(trip);
  }

  return el('div', children: [
    topBar('Pozivnica', plain: true),
    el('div', cls: 'pad', children: [
      el('h1', cls: 'title big', text: trip.city),
      el('p', cls: 'soft gap-top', text: '${trip.country} · '
          '${dateRange(trip.start, trip.end)} · ${peopleCount(trip.people)}'),
    ]),
    primaryButton('Pridruži se kao ${ui.nameOf(ui.meId)}', join),
    if (cloud.names.isNotEmpty) ...[
      el('p', cls: 'soft pad gap-top', text: 'Već si na popisu? Odaberi svoje ime:'),
      el('div', cls: 'checks', children: [
        for (final entry in cloud.names.entries)
          chip(entry.value, () => join(claimedId: entry.key)),
      ]),
    ],
  ]);
}

/// Opens an invitation link: shows the trip and lets the person join.
web.HTMLElement joinScreen(Ui ui, String tripId) {
  final screen = el('div');
  show(screen, _message('Pozivnica', 'Tražim putovanje...'));

  Future<void> load() async {
    final cloud = ui.cloud;
    if (cloud == null) {
      show(screen, _message('Pozivnica', 'Dijeljenje trenutačno nije dostupno.'));
      return;
    }
    try {
      final invited = await cloud.fetchTrip(tripId);
      if (invited == null) {
        show(screen, _message('Pozivnica', 'Ova pozivnica ne vrijedi.'));
      } else {
        show(screen, _invitation(ui, invited));
      }
    } on OnlineException {
      show(screen, _couldNotLoad(load));
    } on Object {
      show(screen, _couldNotLoad(load));
    }
  }

  load();
  return screen;
}

web.HTMLElement _couldNotLoad(Future<void> Function() retry) => _message(
      'Pozivnica',
      'Trenutačno ne mogu doći do putovanja. Provjeri internet.',
      action: primaryButton('Pokušaj ponovno', retry),
    );
