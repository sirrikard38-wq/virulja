import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/show.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'show_builder.dart';
import 'show_player.dart';
import 'widgets.dart';

/// One presentation: a tap anywhere on it plays it over the whole screen, the
/// box votes for it, and its maker changes it with the brush.
web.HTMLElement _showCard(Ui ui, Trip trip, Show show, String me, Show? best) {
  final voted = trip.showPicks[me] == show.id;
  final number = showsBy(trip, show.addedBy).indexOf(show) + 1;
  final ofTheDay = identical(show, best);
  final card = el('div', cls: ofTheDay ? 'poll card show-card best' : 'poll card show-card', attrs: {
    'role': 'button',
    'tabindex': '0',
    'aria-label': tr('Gledaj preko cijelog zaslona: {0}', [show.name]),
  }, children: [
    el('div', cls: 'grow', children: [
      if (ofTheDay) el('span', cls: 'badge', text: tr('Prezentacija dana')),
      el('div', cls: 'label', children: [
        web.document.createTextNode(show.name),
        el('span', cls: 'show-count', text: ' $number/$showsEach'),
      ]),
      el('div', cls: 'small', text: ui.nameOf(show.addedBy)),
      el('div', cls: 'show-actions', children: [
        tick(tr('Glasaj'), voted, () {
          voted ? trip.showPicks.remove(me) : trip.showPicks[me] = show.id;
          keepShowOfTheDay(trip);
          ui.changed();
        }),
        el('span', cls: 'show-votes', text: votesCount(picksOf(trip, show))),
      ]),
    ]),
    if (show.addedBy == me)
      button(
        cls: 'icon-button brush',
        ariaLabel: tr('Uredi'),
        onTap: () => openShowBuilder(ui, trip, show),
        children: [icon('brush', size: 28)],
      ),
  ]);
  card.onClick.listen((event) {
    // The vote and the brush have their own taps.
    if ((event.target as web.Element?)?.closest('button') != null) return;
    watchShow(ui, trip, show);
  });
  card.onKeyDown.listen((event) {
    if (event.key == 'Enter' && event.target == card) watchShow(ui, trip, show);
  });
  return card;
}

/// "Prezentacija dana" at the top of Uspomene: a tap unfolds the presentations
/// the group made, to watch them and vote. The one with most votes plays on the
/// trip's cover.
web.HTMLElement showsSection(Ui ui, Trip trip) {
  final me = ui.meIn(trip);
  final best = showOfTheDay(trip);
  final open = ui.showsOpen;
  final mine = showsBy(trip, me);
  return el('div', cls: 'shows', children: [
    button(
      cls: open ? 'fold open' : 'fold',
      onTap: () {
        ui.showsOpen = !open;
        ui.rerender();
      },
      children: [
        icon(open ? 'minus' : 'plus', size: 22),
        el('span', cls: 'section', text: tr('Prezentacija dana')),
      ],
    )..setAttribute('aria-expanded', '$open'),
    if (!open && best != null)
      el('p', cls: 'small pad', text: '${best.name} · ${votesCount(picksOf(trip, best))}'),
    if (open) ...[
      if (trip.shows.isEmpty)
        el('p', cls: 'soft pad', text: tr('Još nema prezentacija. Napravi prvu od fotografija iz Uspomena.')),
      // In the order they were made; the one of the day is green, not moved.
      for (final show in trip.shows) _showCard(ui, trip, show, me, best),
      if (mine.length < showsEach && trip.photos.isNotEmpty)
        primaryButton('${tr('Napravi prezentaciju')} ${mine.length + 1}/$showsEach',
            () => openShowBuilder(ui, trip, null)),
      el('p', cls: 'small pad gap-top', text: tr('Na naslovnoj stranici putovanja prikazuje se prezentacija s najviše glasova. Svatko ima jedan glas i može napraviti do 3 prezentacije.')),
    ],
  ]);
}

/// A presentation over the whole screen, each photo whole.
web.HTMLElement watchScreen(Ui ui, Trip trip, String? showId) {
  Show? show;
  for (final item in trip.shows) {
    if (item.id == showId) show = item;
  }
  if (show == null) {
    return el('p', cls: 'soft pad', attrs: {'style': 'padding-top:80px'},
        text: tr('Te prezentacije više nema.'));
  }
  return el('div', cls: 'watch', children: [
    keptPlayer(ui, trip, show, 'watch').element,
    el('div', cls: 'watch-name', children: [
      el('div', cls: 'title', text: show.name),
      el('div', cls: 'small', text: ui.nameOf(show.addedBy)),
    ]),
  ]);
}
