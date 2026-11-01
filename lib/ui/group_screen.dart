import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'install.dart';
import 'join_screen.dart';
import 'widgets.dart';

/// This phone's settings: who you are, and how the app looks.
web.HTMLElement groupScreen(Ui ui) {
  final me = ui.data.personById(ui.meId)!;
  final name = input(value: me.name);
  final phone = input(type: 'tel', value: me.phone ?? '');

  final help = installHelp;
  final cloud = ui.cloud;
  return el('div', children: [
    topBar('Postavke', plain: true),
    field('Ime', name),
    field('Broj mobitela', phone),
    primaryButton('Spremi', () {
      if (name.value.trim().isEmpty) return;
      me
        ..name = name.value.trim()
        ..phone = phone.value.trim();
      ui.changed();
      ui.toast('Spremljeno.');
    }),
    if (cloud != null) ...[
      if (ui.data.trips.any((trip) => trip.code != null)) ...[
        sectionTitle('Šifre putovanja'),
        for (final trip in ui.data.trips)
          if (trip.code != null) codeRow(trip),
      ],
      el('hr', cls: 'divider'),
      sectionTitle('Imaš šifru putovanja?'),
      codeField(ui),
      el('p', cls: 'small pad gap-top', text: cloud.reachable
          ? 'Putovanja se dijele s grupom.'
          : 'Nema veze: promjene čekaju i poslat će se same.'),
    ],
    sectionTitle('Izgled'),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:2px'}, children: [
      for (final theme in ThemeChoice.values)
        chip(theme.label, () {
          ui.data.theme = theme;
          ui.changed();
        }, on: ui.data.theme == theme),
    ]),
    if (help == InstallHelp.prompt) ...[
      sectionTitle('Aplikacija'),
      el('div', cls: 'pad', children: [
        secondaryButton('Stavi na mobitel', promptInstall),
      ]),
    ],
    if (help == InstallHelp.ios) ...[
      sectionTitle('Aplikacija'),
      el('p', cls: 'soft pad',
          text: 'U Safariju dodirni Dijeli, zatim Dodaj na početni zaslon.'),
    ],
  ]);
}
