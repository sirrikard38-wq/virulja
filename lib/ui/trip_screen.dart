import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
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
          icon('note'),
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
    el('div', cls: 'two', children: [
      secondaryButton('Dodaj fotografije', () => ui.go(ui.tripRoute(trip, 'slike'))),
      secondaryButton('Dodaj trošak', () => ui.go(ui.tripRoute(trip, 'troskovi'))),
    ]),
    el('div', cls: 'two', children: [
      secondaryButton('Plan puta', () => ui.go(ui.tripRoute(trip, 'put'))),
      secondaryButton('Hrana i piće', () => ui.go(ui.tripRoute(trip, 'hrana'))),
    ]),
    newPollButton(ui, trip),
  ]);
}

web.HTMLElement tripScreen(Ui ui, Trip trip, String tab) {
  final cover = trip.coverId;
  const tabs = {'plan': 'Plan', 'slike': 'Uspomene'};
  return el('div', children: [
    el('div', cls: 'hero', children: [
      if (cover != null)
        storedImage(ui, trip, cover, cls: 'hero-photo', alt: trip.city)
      else
        el('div', cls: 'hero-blank'),
    ]),
    el('div', cls: 'head-row', children: [
      el('div', children: [
        el('div', attrs: {'style': 'display:flex;align-items:center;gap:4px'}, children: [
          el('h1', cls: 'title big', text: trip.city),
          button(
            cls: 'icon-button',
            ariaLabel: 'Postavke',
            onTap: () => ui.go(ui.tripRoute(trip, 'uredi')),
            children: [icon('tool', size: 20)],
          ),
        ]),
        el('p', cls: 'soft', text: '${dateRange(trip.start, trip.end)} · '
            '${peopleCount(trip.people)}', attrs: {'style': 'margin-top:4px;font-size:15px'}),
      ]),
      el('div', attrs: {'style': 'text-align:right;flex:none'}, children: [
        el('div', cls: 'small', text: 'po osobi'),
        el('div', cls: 'title', text: euros(Budget.of(trip).plannedPerPerson)),
      ]),
    ]),
    el('div', cls: 'tabs', children: [
      for (final entry in tabs.entries)
        button(
          cls: entry.key == tab ? 'tab on' : 'tab',
          text: entry.value,
          onTap: () => ui.go(ui.tripRoute(trip, entry.key)),
        ),
    ]),
    if (tab == 'slike') galleryTab(ui, trip) else _planTab(ui, trip),
  ]);
}
