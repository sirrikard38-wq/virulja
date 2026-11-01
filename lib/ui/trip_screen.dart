import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'attack_tab.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'memories_screen.dart';
import 'people_section.dart';
import 'polls_section.dart';
import 'requests_section.dart';
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
            el('span', cls: 'small', text: tr('Himna putovanja'),
                attrs: {'style': 'display:block'}),
            el('span', cls: 'label', text: anthem ?? tr('Dodaj himnu'),
                attrs: {'style': 'display:block'}),
          ]),
          el('span', cls: 'soft', text: tr('Playlista · {0}', [trip.songs.length])),
        ],
      )..setAttribute('style', 'margin:0;padding:6px 12px;width:100%'),
    ]),
    el('div', cls: 'two', children: [
      _tile(tr('Smještaj'), euros(budget.line(CostCategory.stay).planned),
          () => ui.go(ui.tripRoute(trip, 'smjestaj'))),
      _tile(tr('Hrana i piće'), euros(budget.line(CostCategory.food).planned),
          () => ui.go(ui.tripRoute(trip, 'hrana'))),
      _tile(tr('Plan puta'), daysCount(trip.dayCount),
          () => ui.go(ui.tripRoute(trip, 'put'))),
      _tile(tr('Troškovi'), euros(budget.plannedTotal),
          () => ui.go(ui.tripRoute(trip, 'troskovi'))),
    ]),
    if (chosen != null) ...[
      sectionTitle(tr('Odabrani smještaj')),
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', children: [
          el('div', cls: 'label', text: chosen.name),
          el('div', cls: 'small', text: offerFacts(chosen)),
        ]),
        el('div', cls: 'price', text: tr('{0}/noć', [euros(chosen.pricePerNight)])),
      ]),
    ],
  ]);
}

const Duration _foldTime = Duration(milliseconds: 200);

/// Folds the list of people open or shut, once the screen has been drawn.
void _foldPeople(Ui ui) {
  final fold = ui.peopleFold;
  if (fold == null) return;
  ui.peopleFold = null;
  final closing = fold == PeopleFold.closing;
  if (closing) ui.showPeople = false; // a redraw meanwhile leaves it out
  scheduleMicrotask(() {
    final list = web.document.querySelector('.people-list') as web.HTMLElement?;
    if (list == null) return;
    final height = '${list.scrollHeight}px';
    list.style
      ..transition = 'none'
      ..height = closing ? height : '0px';
    list.getBoundingClientRect(); // so that the browser sees where it starts
    list.style
      ..transition = 'height 200ms ease'
      ..height = closing ? '0px' : height;
    Timer(_foldTime, () {
      if (closing) {
        list.remove();
      } else {
        list.style.height = '';
      }
    });
  });
}

web.HTMLElement tripScreen(Ui ui, Trip trip, String tab) {
  final peopleShown = ui.showPeople; // still drawn while it folds shut
  _foldPeople(ui);
  final cover = trip.coverId;
  final tabs = {
    'plan': tr('Plan'),
    'slike': tr('Uspomene'),
    'ankete': tr('Ankete'),
    'napad': tr('Plan napada'),
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
        el('p', cls: 'soft', attrs: {'style': 'margin-top:4px;font-size:15px'}, children: [
          web.document.createTextNode('${dateRange(trip.start, trip.end)} · '),
          button(
            cls: 'people-link',
            text: peopleCount(trip.people),
            onTap: () {
              ui.peopleFold = ui.showPeople ? PeopleFold.closing : PeopleFold.opening;
              ui.showPeople = true;
              ui.rerender();
            },
          ),
        ]),
      ]),
      button(
        cls: 'title-link',
        onTap: () => ui.go(ui.tripRoute(trip, 'troskovi')),
        children: [
          el('div', attrs: {'style': 'text-align:right;flex:none'}, children: [
            el('div', cls: 'small', text: tr('po osobi')),
            el('div', cls: 'title', text: euros(Budget.of(trip).plannedPerPerson)),
          ]),
        ],
      ),
    ]),
    if (peopleShown)
      el('div', cls: 'people-list', children: [
        for (final id in trip.memberIds) memberRow(ui, trip, id),
      ]),
    for (final request in trip.requests) requestCard(ui, trip, request),
    for (final id in trip.kickVotes.keys)
      if (id != ui.meIn(trip)) kickCard(ui, trip, id),
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
      attackTab(ui, trip)
    else
      _planTab(ui, trip),
  ]);
}
