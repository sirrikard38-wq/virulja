import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/show.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'show_builder.dart';
import 'show_player.dart';
import 'widgets.dart';

web.HTMLElement _showCard(Ui ui, Trip trip, Show show, String me, Show? best) {
  final picked = trip.showPicks[me] == show.id;
  return el('div', cls: 'poll card', children: [
    el('div', cls: 'label', text: show.name),
    if (identical(show, best))
      el('div', cls: 'small', attrs: {'style': 'color:var(--accent);font-weight:700'},
          text: tr('Prezentacija dana')),
    el('div', cls: 'small',
        text: tr('{0} · glasova: {1}', [ui.nameOf(show.addedBy), picksOf(trip, show)])),
    el('div', cls: 'show-actions', children: [
      secondaryButton(tr('Gledaj'), () {
        forgetPlayer('watch');
        ui.go(ui.tripRoute(trip, 'gledaj/${show.id}'));
      }),
      tick(tr('Na mom zaslonu'), picked, () {
        picked ? trip.showPicks.remove(me) : trip.showPicks[me] = show.id;
        ui.changed();
      }),
      if (show.addedBy == me)
        button(cls: 'text-button', text: tr('Uredi'), onTap: () => openShowBuilder(ui, trip)),
    ]),
  ]);
}

/// "Prezentacija dana" at the top of Uspomene: a tap unfolds the presentations
/// the group made, to watch them and to pick the one that plays on your screen,
/// which is also your vote.
web.HTMLElement showsSection(Ui ui, Trip trip) {
  final me = ui.meIn(trip);
  final best = showOfTheDay(trip);
  final open = ui.showsOpen;
  final ranked = [
    for (var i = 0; i < trip.shows.length; i++) (show: trip.shows[i], at: i),
  ]..sort((a, b) {
      final picks = picksOf(trip, b.show).compareTo(picksOf(trip, a.show));
      return picks != 0 ? picks : b.at.compareTo(a.at);
    });
  return el('div', cls: 'shows', children: [
    button(
      cls: open ? 'fold open' : 'fold',
      onTap: () {
        ui.showsOpen = !open;
        ui.rerender();
      },
      children: [
        el('span', cls: 'section', text: tr('Prezentacija dana')),
        icon('plus', size: 22),
      ],
    )..setAttribute('aria-expanded', '$open'),
    if (!open && best != null)
      el('p', cls: 'small pad', text: tr('{0} · glasova: {1}', [best.name, picksOf(trip, best)])),
    if (open) ...[
      if (trip.shows.isEmpty)
        el('p', cls: 'soft pad', text: tr('Još nema prezentacija. Napravi prvu od fotografija iz Uspomena.')),
      for (final item in ranked) _showCard(ui, trip, item.show, me, best),
      if (showBy(trip, me) == null && trip.photos.any((photo) => !photo.isVideo))
        primaryButton(tr('Napravi prezentaciju'), () => openShowBuilder(ui, trip)),
      el('p', cls: 'small pad gap-top', text: tr('Prezentacija koju staviš na svoj zaslon svira na naslovnoj slici putovanja i to je tvoj glas. Ona s najviše glasova je prezentacija dana. Svatko može imati jednu.')),
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
