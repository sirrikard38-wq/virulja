import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/format.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

String _when(Trip trip, NextUp item) => [
      weekdayAndDate(trip.dayAt(item.dayIndex)),
      if (item.time.isNotEmpty) item.time,
    ].join(' · ');

/// Takes [item] out of the plan of attack, with a moment to change your mind.
/// A poll stays in Ankete and a stop in Plan puta.
void _remove(Ui ui, Trip trip, NextUp item) {
  final poll = item.poll, stop = item.stop;
  final activeBy = poll?.activeBy;
  poll
    ?..active = false
    ..activeBy = null;
  stop?.hiddenInAttack = true;
  ui.changed();
  ui.offerUndo('Maknuto iz Plana napada', () {
    poll
      ?..active = true
      ..activeBy = activeBy;
    stop?.hiddenInAttack = false;
    ui.changed();
  });
}

web.HTMLElement _closeButton(Ui ui, Trip trip, NextUp item) => button(
      cls: 'icon-button',
      ariaLabel: 'Makni: ${item.title}',
      onTap: () => _remove(ui, trip, item),
      children: [icon('close', size: 20)],
    );

/// For a place from Hrana i piće: which of the days left suit each person.
web.HTMLElement _dayVotes(Ui ui, Trip trip, Poll poll) {
  final me = ui.meIn(trip);
  return el('div', children: [
    el('div', cls: 'small', attrs: {'style': 'margin-top:8px'}, text: 'Koji dan idemo?'),
    el('div', cls: 'checks', attrs: {'style': 'margin:6px 0 0'}, children: [
      for (final day in remainingDays(trip, DateTime.now()))
        chip('Dan ${day + 1} · ${poll.dayVotes[day]?.length ?? 0}', () {
          final people = poll.dayVotes[day] ??= {};
          if (!people.remove(me)) people.add(me);
          if (people.isEmpty) poll.dayVotes.remove(day);
          ui.changed();
        }, on: poll.dayVotes[day]?.contains(me) ?? false),
    ]),
  ]);
}

web.HTMLElement _texts(Ui ui, Trip trip, NextUp item, {required bool big}) {
  final poll = item.poll;
  return el('div', cls: 'grow', children: [
    if (big) el('div', cls: 'small', text: _when(trip, item)),
    el('div', cls: big ? 'title' : 'label', text: item.title),
    if (big && item.detail != null) el('div', cls: 'label', text: item.detail),
    if (!big)
      el('div', cls: 'small', text: [
        _when(trip, item),
        if (item.detail != null) item.detail!,
        if (item.past) 'prošlo',
      ].join(' · ')),
    if (poll != null && poll.single && !item.past) _dayVotes(ui, trip, poll),
  ]);
}

/// What comes next, biggest first, then the rest in order and at the end, grey,
/// what has gone by.
web.HTMLElement attackTab(Ui ui, Trip trip) {
  final items = planOfAttack(trip, DateTime.now());
  if (items.isEmpty) {
    return el('p', cls: 'soft pad gap-top', text: 'Još nema ničega u planu.');
  }
  final next = items.first.past ? null : items.first;
  return el('div', children: [
    if (next != null)
      el('div', cls: 'poll card', attrs: {'style': 'display:flex;gap:8px'}, children: [
        _texts(ui, trip, next, big: true),
        _closeButton(ui, trip, next),
      ]),
    for (final item in items)
      if (!identical(item, next))
        el('div', cls: item.past ? 'row past' : 'row', children: [
          _texts(ui, trip, item, big: false),
          _closeButton(ui, trip, item),
        ]),
  ]);
}
