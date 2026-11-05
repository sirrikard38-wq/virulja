import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'cost_sheet.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

/// The line over a plan: its time, and for what has gone by also its day, as
/// those show no votes any more.
String _when(Trip trip, NextUp item) => [
      if (item.past) ...item.days.map((day) => weekdayAndDate(trip.dayAt(day))),
      if (item.time.isNotEmpty) item.time,
    ].join(' · ');

/// Takes [item] out of the plan of attack, with a moment to change your mind.
/// A poll stays in Ankete, a stop in Plan puta and a place in Hrana i piće.
void _remove(Ui ui, Trip trip, NextUp item) {
  final poll = item.poll, stop = item.stop, place = item.place, leg = item.leg;
  final active = poll?.active, activeBy = poll?.activeBy;
  final planned = place?.planned, plannedBy = place?.plannedBy;
  final polls = {
    for (final other in trip.polls)
      if (place != null && placeOf(trip, other) == place) other: other.active,
  };
  if (poll != null) setPollInAttack(trip, poll, false, ui.meIn(trip));
  if (place != null) setPlaceInAttack(trip, place, false, ui.meIn(trip));
  stop?.hiddenInAttack = true;
  leg?.reserved = false;
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
    leg?.reserved = true;
    ui.changed();
  });
}

/// Draws Plan napada again in its place, and nothing else: the page above it
/// and where it is scrolled stay as they are. A full redraw made an iPhone
/// jump to the top when a day was voted at the bottom of the list.
void _redrawTab(Ui ui, Trip trip) {
  final tab = web.document.querySelector('.attack-tab');
  if (tab == null) {
    ui.rerender();
    return;
  }
  final at = web.window.scrollY;
  tab.replaceWith(attackTab(ui, trip));
  if ((web.window.scrollY - at).abs() > 1) web.window.scrollTo(0.toJS, at);
}

/// Which of the days left suit each person. The day with most votes is marked.
web.HTMLElement _dayVotes(Ui ui, Trip trip, NextUp item) {
  final me = ui.meIn(trip);
  final votes = item.dayVotes;
  final days = remainingDays(trip, DateTime.now());
  web.HTMLElement dayChip(int day) =>
      chip(tr('{0} Dan · {1}', [day + 1, trip.membersAmong(votes[day] ?? const {})]), () {
        toggleDayVote(votes, day, me);
        ui.saved();
        _redrawTab(ui, trip);
      }, on: votes[day]?.contains(me) ?? false)
        ..classList.toggle('agreed', item.days.contains(day));

  // A trip of more than 7 days shows its weeks; a tap on one opens its days.
  final weekly = trip.dayCount > 7;
  final weeks = [
    for (final day in days)
      if (day == days.first || day % 7 == 0) day ~/ 7,
  ];
  final open = ui.openWeek[item.id];
  return el('div', children: [
    el('div', cls: 'small', attrs: {'style': 'margin-top:8px'}, text: tr('Koji dan idemo?')),
    // Four buttons of one length a row; more go on in the next rows.
    el('div', cls: 'attack-days', children: [
      if (!weekly)
        for (final day in days) dayChip(day)
      else
        for (final week in weeks)
          chip(tr('{0}. tjedan', [week + 1]), () {
            open == week ? ui.openWeek.remove(item.id) : ui.openWeek[item.id] = week;
            _redrawTab(ui, trip);
          }, on: open == week)
            ..classList.toggle('agreed', item.days.any((day) => day ~/ 7 == week)),
    ]),
    if (weekly && open != null)
      el('div', cls: 'attack-days', children: [
        for (final day in days)
          if (day ~/ 7 == open) dayChip(day),
      ]),
  ]);
}

/// Whether [item] is already written in Troškovi: its own cost, or one of its name.
bool _written(Trip trip, NextUp item) => trip.expenses.any((cost) =>
    cost.id == item.place?.expenseId ||
    cost.title.trim().toLowerCase() == item.title.trim().toLowerCase());

web.HTMLElement _card(Ui ui, Trip trip, NextUp item) {
  final detail = item.detail;
  final written = _written(trip, item);
  return el('div', cls: item.past ? 'poll card attack-card past' : 'poll card attack-card',
      children: [
    el('div', cls: 'attack-top', children: [
    el('div', cls: 'grow', children: [
      if (_when(trip, item).isNotEmpty) el('div', cls: 'small', text: _when(trip, item)),
      el('div', cls: 'title', text: item.title),
      if (detail != null) el('div', cls: 'label', text: detail),
    ]),
    // Writes it in Troškovi, as a new cost: what it cost, who paid, for whom.
    button(
      cls: written ? 'icon-button cost-tick on' : 'icon-button cost-tick',
      ariaLabel: tr('Dodaj u troškove: {0}', [item.title]),
      onTap: () => costSheet(
        ui,
        trip,
        title: item.title,
        action: tr('Dodaj u troškove'),
        category: item.category,
        guess: item.cost,
        done: (cost) => item.place?.expenseId = cost.id,
      ),
      children: [icon('check', size: 20)],
    ),
    button(
      cls: 'icon-button',
      ariaLabel: tr('Makni: {0}', [item.title]),
      onTap: () => _remove(ui, trip, item),
      children: [icon('close', size: 20)],
    ),
    ]),
    // The days under it all, filling the whole width of the card.
    if (!item.past) _dayVotes(ui, trip, item),
  ]);
}

/// Everything the group wants to do, by the day with most votes: all of it, or
/// one day. Nothing moves within the list; what has gone by turns grey. While a day is open, what
/// was on it stays, even if a vote moves it to another day; it moves once the
/// day is left.
web.HTMLElement attackTab(Ui ui, Trip trip) {
  final items = planOfAttack(trip, DateTime.now());
  final day = ui.attackDays[trip.id];
  final shown = day == null || day >= trip.dayCount ? null : day;
  final kept = ui.attackKept;
  final stays = kept != null && kept.trip == trip.id && kept.day == shown
      ? kept.ids
      : const <String>{};
  final chosen = [
    for (final item in items)
      if (shown == null || item.days.contains(shown) || stays.contains(item.id)) item,
  ];
  ui.attackKept =
      shown == null ? null : (trip: trip.id, day: shown, ids: {for (final item in chosen) item.id});
  void pick(int? next) {
    next == null ? ui.attackDays.remove(trip.id) : ui.attackDays[trip.id] = next;
    ui.attackKept = null;
    _redrawTab(ui, trip);
  }

  return el('div', cls: 'attack-tab', children: [
    el('div', cls: 'chips', children: [
      chip('${tr('Sve')} (${items.length})', () => pick(null), on: shown == null),
      for (var i = 0; i < trip.dayCount; i++)
        chip('${tr('{0} Dan', [i + 1])} (${items.where((item) => item.days.contains(i)).length})',
            () => pick(i), on: i == shown),
    ]),
    if (items.isEmpty)
      el('p', cls: 'soft pad gap-top', text: tr('Još nema ničega u planu.'))
    else if (chosen.isEmpty)
      el('p', cls: 'soft pad gap-top', text: tr('Za ovaj dan još ništa nije dogovoreno.')),
    for (final item in chosen) _card(ui, trip, item),
  ]);
}
