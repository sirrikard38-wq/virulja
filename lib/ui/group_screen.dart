import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'install.dart';
import 'join_screen.dart';
import 'language_section.dart';
import 'notifications_section.dart';
import 'profile_section.dart';
import 'widgets.dart';

/// This phone's settings: who you are, and how the app looks.
web.HTMLElement groupScreen(Ui ui) {
  final me = ui.data.personById(ui.meId)!;
  final name = input(value: me.name);
  final phone = input(type: 'tel', value: me.phone ?? '');

  final help = installHelp;
  final cloud = ui.cloud;
  return el('div', children: [
    topBar(tr('Postavke'), plain: true),
    profilePhoto(ui),
    field(tr('Ime'), name),
    field(tr('Broj mobitela'), phone),
    primaryButton(tr('Spremi'), () {
      if (name.value.trim().isEmpty) return;
      me
        ..name = name.value.trim()
        ..phone = phone.value.trim();
      ui.changed();
      ui.toast(tr('Spremljeno.'));
    }),
    if (cloud != null) ...[
      if (ui.data.trips.any((trip) => trip.code != null)) ...[
        sectionTitle(tr('Šifre putovanja')),
        for (final trip in ui.data.trips)
          if (trip.code != null) codeRow(trip),
      ],
      el('hr', cls: 'divider'),
      sectionTitle(tr('Imaš šifru putovanja?')),
      codeField(ui),
      if (cloud.reachable)
        el('p', cls: 'small pad gap-top', text: tr('Putovanja se dijele s grupom.')),
    ],
    if (cloud?.pushKey != null) ...[
      sectionTitle(tr('Obavijesti')),
      notificationsSection(ui),
    ],
    sectionTitle(tr('Izgled')),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:2px'}, children: [
      for (final theme in ThemeChoice.values)
        chip(theme.label, () {
          ui.data.theme = theme;
          ui.changed();
        }, on: ui.data.theme == theme),
    ]),
    if (help == InstallHelp.prompt) ...[
      sectionTitle(tr('Aplikacija')),
      el('div', cls: 'pad', children: [
        secondaryButton(tr('Stavi na mobitel'), promptInstall),
      ]),
    ],
    if (help == InstallHelp.ios) ...[
      sectionTitle(tr('Aplikacija')),
      el('p', cls: 'soft pad',
          text: tr('U Safariju dodirni Dijeli, zatim Dodaj na početni zaslon.')),
    ],
    sectionTitle(tr('Jezik')),
    languageChips(ui),
    if (builtAt case final built?)
      el('p', cls: 'small pad gap-top', text: tr('Verzija {0} u {1}', [
        dayAndMonth(built),
        '${built.hour.toString().padLeft(2, '0')}:${built.minute.toString().padLeft(2, '0')}',
      ])),
  ]);
}
