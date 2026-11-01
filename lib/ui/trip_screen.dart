import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import '../src/domain/attack.dart';
import 'memories_screen.dart';
import 'polls_section.dart';
import 'widgets.dart';

/// The tab a trip opens on: what matters at this moment.
String defaultTab(Trip trip) {
  return trip.phaseOn(today()) == TripPhase.past ? 'slike' : 'plan';
}

web.HTMLElement _tile(String label, String value, void Function() onTap) =>
    button(cls: 'tile card', onTap: onTap, children: [
      el('span', cls: 'small', text: label),
      el('span', cls: 'value', text: value),
    ]);

web.HTMLElement _planTab(Ui ui, Trip trip) {
  final budget = Budget.of(trip);
  final chosen = trip.chosenOffer;
  final anthem = trip.anthemTitle;
  return el('div', children: [
    el('div', cls: 'pad', attrs: {'style': 'margin-top:10px'}, children: [
      button(
        cls: 'card row',
        onTap: () => ui.go(ui.tripRoute(trip, 'playlista')),
        children: [
          el('span', attrs: {'style': 'display:flex;padding:10px;margin:-10px'}, children: [icon('note')])
            ..onClick.listen((event) {
              // With no anthem yet the tap just opens the playlist.
              if (trip.anthemClipId == null) return;
              event.stopPropagation();
              ui.startAnthem(trip);
            }),
          el('span', cls: 'grow', children: [
            el('span', cls: 'small', text: 'Himna putovanja',
                attrs: {'style': 'display:block'}),
            el('span', cls: 'label', text: anthem ?? 'Dodaj himnu',
                attrs: {'style': 'display:block'}),
          ]),
          el('span', cls: 'soft', text: 'Playlista · ${trip.songs.length}'),
        ],
      )..setAttribute('style', 'margin:0;padding:6px 12px;width:100%'),
    ]),
    el('div', cls: 'two', children: [
      _tile('Smještaj', euros(budget.line(CostCategory.stay).planned),
          () => ui.go(ui.tripRoute(trip, 'smjestaj'))),
      _tile('Hrana i piće', euros(budget.line(CostCategory.food).planned),
          () => ui.go(ui.tripRoute(trip, 'hrana'))),
      _tile('Plan puta', '${trip.dayCount} dana',
          () => ui.go(ui.tripRoute(trip, 'put'))),
      _tile('Troškovi', euros(budget.plannedTotal),
          () => ui.go(ui.tripRoute(trip, 'troskovi'))),
    ]),
    if (chosen != null) ...[
      sectionTitle('Odabrani smještaj'),
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', children: [
          el('div', cls: 'label', text: chosen.name),
          el('div', cls: 'small', text: offerFacts(chosen)),
        ]),
        el('div', cls: 'price', text: '${euros(chosen.pricePerNight)}/noć'),
      ]),
    ],
  ]);
}

/// What comes next, biggest first, then the rest in order.
web.HTMLElement _attackTab(Trip trip) {
  final items = planOfAttack(trip, DateTime.now());
  String when(NextUp item) => [
        weekdayAndDate(trip.dayAt(item.dayIndex)),
        if (item.time.isNotEmpty) item.time,
      ].join(' · ');
  if (items.isEmpty) {
    return el('p', cls: 'soft pad gap-top', text: 'Još nema ničega u planu.');
  }
  final first = items.first;
  return el('div', children: [
    el('div', cls: 'poll card', children: [
      el('div', cls: 'small', text: when(first)),
      el('div', cls: 'title', text: first.title),
      if (first.detail != null) el('div', cls: 'label', text: first.detail),
    ]),
    for (final item in items.skip(1))
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', children: [
          el('div', cls: 'label', text: item.title),
          el('div', cls: 'small', text: [
            when(item),
            if (item.detail != null) item.detail!,
          ].join(' · ')),
        ]),
      ]),
  ]);
}

web.HTMLElement tripScreen(Ui ui, Trip trip, String tab) {
  final cover = trip.coverId;
  const tabs = {
    'plan': 'Plan',
    'slike': 'Uspomene',
    'ankete': 'Ankete',
    'napad': 'Plan napada',
  };
  return el('div', children: [
    el('div', cls: 'hero', children: [
      if (cover != null)
        storedImage(ui, trip, cover, cls: 'hero-photo', alt: trip.city)
      else
        el('div', cls: 'hero-blank'),
    ]),
    el('div', cls: 'head-row', children: [
      el('div', children: [
        button(
          cls: 'title-link',
          onTap: () => ui.go(ui.tripRoute(trip, 'uredi')),
          children: [el('h1', cls: 'title big', text: trip.city)],
        ),
        el('p', cls: 'soft', text: '${dateRange(trip.start, trip.end)} · '
            '${peopleCount(trip.people)}', attrs: {'style': 'margin-top:4px;font-size:15px'}),
      ]),
      button(
        cls: 'title-link',
        onTap: () => ui.go(ui.tripRoute(trip, 'troskovi')),
        children: [
          el('div', attrs: {'style': 'text-align:right;flex:none'}, children: [
            el('div', cls: 'small', text: 'po osobi'),
            el('div', cls: 'title', text: euros(Budget.of(trip).plannedPerPerson)),
          ]),
        ],
      ),
    ]),
    el('div', cls: 'tabs', children: [
      for (final entry in tabs.entries)
        button(
          cls: entry.key == tab ? 'tab on' : 'tab',
          text: entry.value,
          onTap: () => ui.swap(ui.tripRoute(trip, entry.key)),
        ),
    ]),
    if (tab == 'slike')
      galleryTab(ui, trip)
    else if (tab == 'ankete')
      pollsTab(ui, trip)
    else if (tab == 'napad')
      _attackTab(trip)
    else
      _planTab(ui, trip),
  ]);
}
