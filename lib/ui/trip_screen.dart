import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/show.dart';
import 'attack_tab.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'memories_screen.dart';
import 'people_section.dart';
import 'polls_section.dart';
import 'requests_section.dart';
import 'show_player.dart';
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
      // Each shows only what was really spent on it.
      _tile(tr('Hrana i piće'), euros(budget.line(CostCategory.food).actual),
          () => ui.go(ui.tripRoute(trip, 'hrana'))),
      // Dućan: every cost of its kind, as Trošak dućana at its foot.
      _tile(tr('Dućan'), euros(shopSpent(trip)),
          () => ui.go(ui.tripRoute(trip, 'ducan'))),
      // Prijevoz: as Prijevoz ukupno at its foot.
      _tile(tr('Prijevoz'), euros(transportTotal(trip)),
          () => ui.go(ui.tripRoute(trip, 'put'))),
      _tile(tr('Smještaj'), euros(budget.line(CostCategory.stay).actual),
          () => ui.go(ui.tripRoute(trip, 'smjestaj'))),
      _tile(tr('Troškovi'), euros(budget.actualTotal),
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
  // A swipe brought the tab and its line in already.
  if (justSwiped) return;
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

/// What one tab of a trip shows.
web.HTMLElement _drawTab(Ui ui, Trip trip, String tab) => switch (tab) {
      'slike' => galleryTab(ui, trip),
      'ankete' => pollsTab(ui, trip),
      'napad' => attackTab(ui, trip),
      _ => _planTab(ui, trip),
    };

/// The tab drawn beside the open one during a swipe. When the swipe lands on
/// it, it is put in place as it is: drawing a long tab twice, once beside and
/// once landed, made the phone stop for a moment. Any other drawing of a tab
/// throws it away, so it is never older than the last change.
({Trip trip, String tab, web.HTMLElement content, DateTime at})? _beside;

web.HTMLElement _tabContent(Ui ui, Trip trip, String tab) {
  final kept = _beside;
  _beside = null;
  if (kept != null &&
      identical(kept.trip, trip) &&
      kept.tab == tab &&
      DateTime.now().difference(kept.at) < const Duration(seconds: 2)) {
    kept.content.remove();
    return kept.content;
  }
  return _drawTab(ui, trip, tab);
}

web.HTMLElement _peekTab(Ui ui, Trip trip, String tab) {
  final content = _drawTab(ui, trip, tab);
  _beside = (trip: trip, tab: tab, content: content, at: DateTime.now());
  return content;
}

/// How many presentations, polls and plans there are, after the tab's name.
Map<String, int> _tabCounts(Trip trip) => {
      'slike': trip.shows.length,
      'ankete': trip.polls.length,
      'napad': planOfAttack(trip, DateTime.now()).length,
    };

/// Draws the open tab of a trip again in its place, with the counts on the
/// tabs, and nothing else: the cover, the header and where the page is
/// scrolled stay as they are. A full redraw made an iPhone jump.
void redrawTripTab(Ui ui, Trip trip) {
  final page = web.document.querySelector('.slide-page');
  final parts = web.window.location.hash.split('/');
  if (page == null || parts.length < 3) {
    ui.rerender();
    return;
  }
  final tab = parts.length > 3 ? parts[3] : defaultTab(trip);
  final at = web.window.scrollY;
  page.textContent = '';
  page.append(_tabContent(ui, trip, tab));
  final counts = _tabCounts(trip);
  final tabs = web.document.querySelectorAll('[data-tab-key]');
  for (var i = 0; i < tabs.length; i++) {
    final button = tabs.item(i) as web.HTMLElement;
    final count = counts[button.getAttribute('data-tab-key')];
    final shown = button.querySelector('.tab-count');
    if (count == null || shown == null) continue;
    shown.textContent = ' ($count)';
    final label = button.getAttribute('data-label') ?? '';
    button.setAttribute('data-label', label.replaceFirst(RegExp(r' \(\d+\)$'), ' ($count)'));
  }
  if ((web.window.scrollY - at).abs() > 1) web.window.scrollTo(0.toJS, at);
  scheduleMicrotask(markEdges);
}

web.HTMLElement tripScreen(Ui ui, Trip trip, String tab) {
  // Whatever came from another phone: a whole yes goes into Plan napada, and the
  // presentation of the day changes only for more votes.
  final yeses = trip.polls.any((poll) => wholeYesChanged(trip, poll));
  if (yeses) addWholeYeses(trip, ui.meIn(trip));
  final moved = moveOldDrive(trip);
  if (keepShowOfTheDay(trip) || yeses || moved) ui.saved();
  final peopleShown = ui.showPeople; // still drawn while it folds shut
  _foldPeople(ui);
  final cover = trip.coverId;
  // The presentation with most votes plays in place of the cover.
  final playing = onCover(trip);
  final player = playing == null ? null : keptPlayer(ui, trip, playing, 'hero');
  // How many presentations, polls and plans there are, after the tab's name.
  final tabs = {
    'plan': tr('Plan'),
    'slike': tr('Uspomene'),
    'ankete': tr('Ankete'),
    'napad': tr('Plan napada'),
  };
  final counts = _tabCounts(trip);
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

  final sliding = el('div', cls: 'slide-page', children: [_tabContent(ui, trip, tab)]);
  final page = el('div', cls: 'swipe-area', children: [
    if (playing != null && player != null)
      button(
        cls: 'hero tappable',
        ariaLabel: tr('Gledaj preko cijelog zaslona: {0}', [playing.name]),
        onTap: () => watchShow(ui, trip, playing, from: player.seconds),
        children: [
          player.element..classList.add('hero-show'),
          el('span', cls: 'hero-caption', text: playing.name),
        ],
      )
    else
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
            el('div', cls: 'small', text: tr('tvoj trošak')),
            el('div', cls: 'title', text: euros(Budget.shareOf(trip, ui.meIn(trip)))),
            if (alsoIn(Budget.shareOf(trip, ui.meIn(trip))) case final also when also.isNotEmpty)
              el('div', cls: 'small also', text: also),
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
          onTap: () => show(entry.key),
          children: [
            web.document.createTextNode(entry.value),
            if (counts[entry.key] != null)
              el('span', cls: 'tab-count', text: ' (${counts[entry.key]})'),
          ],
        )
          ..setAttribute('data-tab-key', entry.key)
          ..setAttribute('data-label',
              counts[entry.key] == null ? entry.value : '${entry.value} (${counts[entry.key]})'),
    ]),
    el('div', cls: 'slide-clip', children: [sliding]),
  ]);
  bool canMove(int step) {
    final next = index + step;
    return next >= 0 && next < keys.length;
  }

  final tabsRow = page.querySelector('.tabs') as web.HTMLElement?;
  final mark = tabsRow == null ? null : SwipeMark(tabsRow, line: true);
  followSwipes(
    page,
    sliding,
    canMove,
    (step) => show(keys[index + step]),
    peek: (step) => el('div', children: [_peekTab(ui, trip, keys[index + step])]),
    follow: (step, fraction) =>
        mark?.follow(tabsRow?.querySelectorAll('.tab').item(index + step) as web.HTMLElement?, fraction),
  );
  return page;
}
