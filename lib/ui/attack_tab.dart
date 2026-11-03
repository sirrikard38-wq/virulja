import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

/// The days the group agreed on, or that it has not yet.
String _when(Trip trip, NextUp item) {
  if (item.days.isEmpty) return tr('Dan još nije dogovoren');
  return [
    item.days.map((day) => weekdayAndDate(trip.dayAt(day))).join(', '),
    if (item.time.isNotEmpty) item.time,
  ].join(' · ');
}

/// Takes [item] out of the plan of attack, with a moment to change your mind.
/// A poll stays in Ankete, a stop in Plan puta and a place in Hrana i piće.
void _remove(Ui ui, Trip trip, NextUp item) {
  final poll = item.poll, stop = item.stop, place = item.place;
  final active = poll?.active, activeBy = poll?.activeBy;
  final planned = place?.planned, plannedBy = place?.plannedBy;
  final polls = {
    for (final other in trip.polls)
      if (place != null && placeOf(trip, other) == place) other: other.active,
  };
  if (poll != null) setPollInAttack(trip, poll, false, ui.meIn(trip));
  if (place != null) setPlaceInAttack(trip, place, false, ui.meIn(trip));
  stop?.hiddenInAttack = true;
  ui.changed();
  ui.offerUndo(tr('Maknuto iz Plana napada'), () {
    poll
      ?..active = active!
      ..activeBy = activeBy;
    place
      ?..planned = planned!
      ..plannedBy = plannedBy;
    polls.forEach((other, wasActive) => other.active = wasActive);
    stop?.hiddenInAttack = false;
    ui.changed();
  });
}

/// Which of the days left suit each person. A day enough of the group can go
/// is marked.
web.HTMLElement _dayVotes(Ui ui, Trip trip, NextUp item) {
  final me = ui.meIn(trip);
  final votes = item.dayVotes;
  return el('div', children: [
    el('div', cls: 'small', attrs: {'style': 'margin-top:8px'}, text: tr('Koji dan idemo?')),
    el('div', cls: 'checks', attrs: {'style': 'margin:6px 0 0'}, children: [
      for (final day in remainingDays(trip, DateTime.now()))
        chip(tr('Dan {0} · {1}', [day + 1, votes[day]?.length ?? 0]), () {
          toggleDayVote(votes, day, me);
          ui.changed();
        }, on: votes[day]?.contains(me) ?? false)
          ..classList.toggle('agreed', item.days.contains(day)),
    ]),
  ]);
}

web.HTMLElement _card(Ui ui, Trip trip, NextUp item) {
  final detail = item.detail;
  return el('div', cls: item.past ? 'poll card attack-card past' : 'poll card attack-card',
      children: [
    el('div', cls: 'grow', children: [
      el('div', cls: 'small', text: _when(trip, item)),
      el('div', cls: 'title', text: item.title),
      if (detail != null) el('div', cls: 'label', text: detail),
      if (!item.past) _dayVotes(ui, trip, item),
    ]),
    button(
      cls: 'icon-button',
      ariaLabel: tr('Makni: {0}', [item.title]),
      onTap: () => _remove(ui, trip, item),
      children: [icon('close', size: 20)],
    ),
  ]);
}

/// Everything the group wants to do, by the days it agreed on: all of it, or one
/// day. What has gone by stays at the end, grey.
web.HTMLElement attackTab(Ui ui, Trip trip) {
  final items = planOfAttack(trip, DateTime.now());
  final day = ui.attackDays[trip.id];
  final shown = day == null || day >= trip.dayCount ? null : day;
  final chosen = [
    for (final item in items)
      if (shown == null || item.days.contains(shown)) item,
  ];
  void pick(int? next) {
    next == null ? ui.attackDays.remove(trip.id) : ui.attackDays[trip.id] = next;
    ui.rerender();
  }

  return el('div', children: [
    el('div', cls: 'chips', children: [
      chip(tr('Sve'), () => pick(null), on: shown == null),
      for (var i = 0; i < trip.dayCount; i++)
        chip(tr('Dan {0}', [i + 1]), () => pick(i), on: i == shown),
    ]),
    if (items.isEmpty)
      el('p', cls: 'soft pad gap-top', text: tr('Još nema ničega u planu.'))
    else if (chosen.isEmpty)
      el('p', cls: 'soft pad gap-top', text: tr('Za ovaj dan još ništa nije dogovoreno.')),
    for (final item in chosen) _card(ui, trip, item),
  ]);
}
