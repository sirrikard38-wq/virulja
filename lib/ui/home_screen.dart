import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

web.HTMLElement _brand() => el('div', cls: 'brand', children: [
      logoMark(),
      el('span', cls: 'brand-name', text: 'VIRULJA'),
    ]);

/// The first visit: the app only needs to know who is holding the phone.
web.HTMLElement _welcome(Ui ui) {
  final name = input(placeholder: 'Ana');
  final error = errorLine();
  void start() {
    final text = name.value.trim();
    if (text.isEmpty) {
      error.textContent = 'Upiši svoje ime.';
      return;
    }
    final me = Person(id: ui.store.newId(), name: text);
    ui.data.people.add(me);
    ui.data.meId = me.id;
    ui.changed();
  }

  return el('div', children: [
    _brand(),
    el('div', cls: 'welcome', children: [
      el('h1', cls: 'title big', text: 'Dobro došli'),
      el('p', cls: 'soft gap-top', text: 'Vaša putovanja, od plana do uspomena.'),
    ]),
    field('Kako se zoveš?', name),
    error,
    primaryButton('Kreni', start),
  ]);
}

web.HTMLElement _bigPostcard(Ui ui, Trip trip, String when) {
  final cover = trip.coverId;
  return el('div', children: [
    el('div', cls: 'head-row', children: [
      el('span', cls: 'label', text: 'Sljedeće putovanje'),
      el('span', cls: 'soft', text: when),
    ]),
    button(
      cls: 'postcard card gap-top',
      ariaLabel: 'Otvori putovanje ${trip.city}',
      onTap: () => ui.openTrip(trip),
      children: [
        if (cover != null)
          storedImage(ui, trip, cover, cls: 'postcard-photo', alt: trip.city)
        else
          el('span', cls: 'postcard-blank', text: trip.city),
        stamp(trip.city, trip.start.year),
        el('span', cls: 'title', text: trip.city),
        el('span', cls: 'soft', text: '${trip.country} · '
            '${dateRange(trip.start, trip.end)} · ${peopleCount(trip.people)}'),
      ],
    ),
  ]);
}

web.HTMLElement _miniPostcard(Ui ui, Trip trip, String detail) {
  final cover = trip.coverId;
  return button(
    cls: 'mini card',
    ariaLabel: 'Otvori putovanje ${trip.city}',
    onTap: () => ui.openTrip(trip),
    children: [
      if (cover != null)
        storedImage(ui, trip, thumbId(cover), cls: 'mini-photo', alt: trip.city)
      else
        el('span', cls: 'mini-photo'),
      el('span', cls: 'label', text: trip.city),
      el('span', cls: 'small', text: detail),
    ],
  );
}

web.HTMLElement homeScreen(Ui ui) {
  if (ui.data.meId == null) return _welcome(ui);
  final now = today();
  final trips = ui.data.trips.toList()
    ..sort((a, b) => a.start.compareTo(b.start));
  final ahead =
      trips.where((trip) => trip.phaseOn(now) != TripPhase.past).toList();
  final past = trips
      .where((trip) => trip.phaseOn(now) == TripPhase.past)
      .toList()
      .reversed
      .toList();

  return el('div', children: [
    _brand(),
    if (trips.isEmpty)
      el('div', cls: 'welcome', children: [
        el('h1', cls: 'title', text: 'Napravite prvo putovanje'),
        el('p', cls: 'soft gap-top',
            text: 'Odaberite državu i grad, a plan, troškovi i fotografije '
                'bit će na jednom mjestu.'),
      ]),
    if (ahead.isNotEmpty)
      _bigPostcard(
        ui,
        ahead.first,
        ahead.first.phaseOn(now) == TripPhase.active
            ? 'upravo traje'
            : daysUntil(now, ahead.first.start),
      ),
    if (ahead.length > 1) ...[
      sectionTitle('U planu'),
      el('div', cls: 'cards', children: [
        for (final trip in ahead.skip(1))
          _miniPostcard(ui, trip, dateRange(trip.start, trip.end)),
      ]),
    ],
    if (past.isNotEmpty) ...[
      sectionTitle('Uspomene'),
      el('div', cls: 'cards', children: [
        for (final trip in past.take(3))
          _miniPostcard(ui, trip, photosCount(trip.photos.length)),
      ]),
    ],
    button(
      cls: 'primary wide',
      onTap: () => ui.go('#/novo'),
      children: [
        icon('plus', size: 20),
        web.document.createTextNode('Novo putovanje'),
      ],
    ),
  ]);
}

/// Every trip with its photos, newest first.
web.HTMLElement memoriesListScreen(Ui ui) {
  final trips = ui.data.trips.toList()
    ..sort((a, b) => b.start.compareTo(a.start));
  return el('div', children: [
    topBar('Uspomene', plain: true),
    if (trips.isEmpty)
      el('p', cls: 'soft pad', text: 'Ovdje će biti vaša putovanja i fotografije.')
    else
      el('div', cls: 'cards two-up', children: [
        for (final trip in trips)
          _miniPostcard(ui, trip, photosCount(trip.photos.length)),
      ]),
  ]);
}
