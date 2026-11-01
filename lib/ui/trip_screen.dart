import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

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
import 'swipes.dart';
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

/// A change of tab on its way through the address: the tab it leaves, where the
/// line under that tab is, and how far the page is scrolled.
typedef _TabChange = ({int from, double left, double width, double scroll});

_TabChange? _tabChange;

/// Shows a change of tab once the screen has been drawn. The page stays where it
/// was, with the tabs in sight, and the list slides in. A redraw replaces the tabs,
/// so for a moment a line stands in for the one under the chosen tab and glides
/// over while the words change colour.
void _showTabChange(_TabChange change, int index) {
  web.window.scrollTo(0.toJS, change.scroll);
  final row = web.document.querySelector('.tabs') as web.HTMLElement?;
  final chosen = row?.querySelector('.tab.on') as web.HTMLElement?;
  if (row == null || chosen == null) return;
  row.scrollIntoView(web.ScrollIntoViewOptions(block: 'nearest'));
  slideIn(index > change.from ? 1 : -1);
  if (wantsLessMotion) return;
  final leaving = row.querySelectorAll('.tab').item(change.from) as web.HTMLElement?;
  final toLeft = chosen.offsetLeft.toDouble();
  final toWidth = chosen.offsetWidth.toDouble();
  final line = el('span', cls: 'tab-line');
  line.style
    ..left = '${change.left}px'
    ..width = '${change.width}px';
  leaving?.classList.add('leaving');
  row
    ..append(line)
    ..classList.add('gliding')
    ..classList.add('glide-start');
  row.getBoundingClientRect(); // so that the browser sees the colours they start from
  row.classList.remove('glide-start');
  animate(glideTime, (progress) {
    line.style
      ..left = '${change.left + (toLeft - change.left) * progress}px'
      ..width = '${change.width + (toWidth - change.width) * progress}px';
  }, () {
    line.remove();
    leaving?.classList.remove('leaving');
    row.classList.remove('gliding');
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
  final keys = tabs.keys.toList();
  final index = max(keys.indexOf(tab), 0);
  final change = _tabChange;
  _tabChange = null;
  if (change != null) scheduleMicrotask(() => _showTabChange(change, index));

  void show(String next) {
    if (next == keys[index]) return;
    final line = web.document.querySelector('.tab.on') as web.HTMLElement?;
    _tabChange = (
      from: index,
      left: line?.offsetLeft.toDouble() ?? 0,
      width: line?.offsetWidth.toDouble() ?? 0,
      scroll: web.window.scrollY,
    );
    ui.swap(ui.tripRoute(trip, next));
  }

  final sliding = el('div', cls: 'slide-page', children: [
    switch (tab) {
      'slike' => galleryTab(ui, trip),
      'ankete' => pollsTab(ui, trip),
      'napad' => attackTab(ui, trip),
      _ => _planTab(ui, trip),
    },
  ]);
  final page = el('div', cls: 'swipe-area', children: [
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
          onTap: () => show(entry.key),
        )..setAttribute('data-label', entry.value),
    ]),
    el('div', cls: 'slide-clip', children: [sliding]),
  ]);
  bool canMove(int step) {
    final next = index + step;
    return next >= 0 && next < keys.length;
  }

  followSwipes(page, sliding, canMove, (step) => show(keys[index + step]));
  return page;
}
