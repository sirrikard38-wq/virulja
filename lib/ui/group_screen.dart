import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'install.dart';
import 'join_screen.dart';
import 'language_section.dart';
import 'notifications_section.dart';
import 'profile_section.dart';
import 'widgets.dart';

/// The trips whose codes are listed, [hidden] or not: the next one on top, then
/// each after it, then those gone by, the longest ago last.
List<Trip> _codes(Ui ui, {bool hidden = false}) {
  final now = today();
  final trips = [
    for (final trip in ui.data.trips)
      if (trip.code != null && ui.data.hiddenCodes.contains(trip.id) == hidden) trip,
  ];
  final coming = trips.where((trip) => !trip.end.isBefore(now)).toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final gone = trips.where((trip) => trip.end.isBefore(now)).toList()
    ..sort((a, b) => b.end.compareTo(a.end));
  return [...coming, ...gone];
}

/// Šifre putovanja. With codes hidden, a tap on the heading folds them open
/// under the others, faded, each with Prikaži to bring it back.
List<web.HTMLElement> _codesSection(Ui ui) {
  final shown = _codes(ui);
  final hidden = _codes(ui, hidden: true);
  if (shown.isEmpty && hidden.isEmpty) return [];
  final open = ui.hiddenCodesOpen && hidden.isNotEmpty;

  web.HTMLElement line(Trip trip, {required bool isHidden}) => el('div', cls: isHidden ? 'code-line faded' : 'code-line', children: [
        el('div', cls: 'grow', children: [codeRow(trip)]),
        button(
          cls: 'hide-code',
          ariaLabel: isHidden ? tr('Prikaži šifru: {0}', [trip.city]) : tr('Sakrij šifru: {0}', [trip.city]),
          onTap: () {
            if (isHidden) {
              ui.data.hiddenCodes.remove(trip.id);
              ui.changed();
              return;
            }
            ui.data.hiddenCodes.add(trip.id);
            ui.changed();
            ui.offerUndo(tr('Sakriveno'), () {
              ui.data.hiddenCodes.remove(trip.id);
              ui.changed();
            });
          },
          children: isHidden
              ? [icon('plus', size: 18), el('span', text: tr('Prikaži'))]
              : [icon('close', size: 18), el('span', text: tr('Sakrij'))],
        ),
      ]);

  return [
    if (hidden.isEmpty)
      sectionTitle(tr('Šifre putovanja'))
    else
      button(
        cls: open ? 'fold open' : 'fold',
        onTap: () {
          ui.hiddenCodesOpen = !open;
          ui.rerender();
        },
        children: [
          icon(open ? 'minus' : 'plus', size: 22),
          el('span', cls: 'section', text: tr('Šifre putovanja')),
        ],
      )..setAttribute('aria-expanded', '$open'),
    for (final trip in shown) line(trip, isHidden: false),
    if (open) ...[
      el('p', cls: 'small pad gap-top', text: tr('Skrivene')),
      for (final trip in hidden) line(trip, isHidden: true),
    ],
  ];
}

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
      ..._codesSection(ui),
      el('hr', cls: 'divider'),
      sectionTitle(tr('Imaš šifru putovanja?')),
      codeField(ui),
      if (cloud.reachable)
        el('p', cls: 'small pad gap-top', text: tr('Putovanja se dijele s grupom.')),
    ],
    if (cloud?.pushKey != null) notificationsSection(ui),
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
    if (ui.mayOpenAll) ...[
      sectionTitle(tr('Prezentacije')),
      el('div', cls: 'ticks', children: [
        tick(tr('Svi prijelazi odmah'), ui.data.allTransitions, () {
          ui.data.allTransitions = !ui.data.allTransitions;
          ui.changed();
        }),
        el('p', cls: 'small', text: tr('Otvara svih 15 prijelaza u izradi prezentacije, bez čekanja dana. Vidiš to samo ti.')),
      ]),
    ],
    if (builtAt case final built?)
      el('p', cls: 'small pad gap-top', text: tr('Verzija {0} u {1}', [
        dayAndMonth(built),
        '${built.hour.toString().padLeft(2, '0')}:${built.minute.toString().padLeft(2, '0')}',
      ])),
  ]);
}
