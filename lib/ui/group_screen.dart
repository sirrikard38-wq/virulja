import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'install.dart';
import 'join_screen.dart';
import 'widgets.dart';

bool _inUse(Ui ui, Person person) =>
    person.id == ui.data.meId ||
    ui.data.trips.any((trip) => trip.memberIds.contains(person.id));

/// Pasting the link matters on iPhones: there, a link opens in Safari, not in
/// the app on the home screen.
web.HTMLElement _joinByLink(Ui ui) {
  final link = input(placeholder: 'Zalijepi link pozivnice');
  final error = errorLine();

  void open() {
    final id = inviteIdIn(link.value);
    if (id == null) {
      error.textContent = 'To nije link pozivnice.';
    } else {
      ui.go('#/pridruzi/$id');
    }
  }

  return el('div', children: [
    sectionTitle('Imaš pozivnicu?'),
    el('div', cls: 'fields', attrs: {'style': 'margin-top:4px'}, children: [
      field('Link', link, tight: true),
      el('div', attrs: {'style': 'align-self:end'}, children: [
        secondaryButton('Otvori', open),
      ]),
    ]),
    error,
  ]);
}

web.HTMLElement groupScreen(Ui ui) {
  final name = input(placeholder: 'Ime');
  final error = errorLine();

  void add() {
    final text = name.value.trim();
    if (text.isEmpty) {
      error.textContent = 'Upiši ime.';
      return;
    }
    ui.data.people.add(Person(id: ui.store.newId(), name: text));
    ui.changed();
  }

  final help = installHelp;
  final cloud = ui.cloud;
  return el('div', children: [
    topBar('Grupa', plain: true),
    for (final person in ui.data.people)
      el('div', cls: 'row', children: [
        avatar(person.name),
        el('div', cls: 'grow', text: person.name),
        if (person.id == ui.data.meId) el('span', cls: 'small', text: 'ovo si ti'),
        if (!_inUse(ui, person))
          removeButton(person.name, () {
            ui.data.people.remove(person);
            ui.changed();
          }),
      ]),
    el('div', cls: 'fields', children: [
      field('Dodaj osobu', name, tight: true),
      el('div', attrs: {'style': 'align-self:end'}, children: [
        secondaryButton('Dodaj', add),
      ]),
    ]),
    error,
    if (cloud != null) ...[
      el('p', cls: 'small pad gap-top', text: cloud.reachable
          ? 'Putovanja se dijele s grupom.'
          : 'Nema veze: promjene čekaju i poslat će se same.'),
      _joinByLink(ui),
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
