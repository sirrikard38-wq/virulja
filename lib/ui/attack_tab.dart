import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'cost_sheet.dart';
import 'trip_screen.dart';
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

/// Draws Plan napada again in its place, and nothing else: the page above it
/// and where it is scrolled stay as they are. A full redraw made an iPhone
/// jump to the top when a day was voted at the bottom of the list.
void _redrawTab(Ui ui, Trip trip) => redrawTripTab(ui, trip);

/// Draws the card of [id] again in its place, with the row of days over the
/// list and its counts, and nothing else: with a long plan, drawing every card
/// again for one vote made the phone lag. A card that leaves the view this way
/// (a vote moved it out of the open week) needs the whole tab drawn again.
void _redrawCard(Ui ui, Trip trip, String id) {
  final tab = web.document.querySelector('.attack-tab');
  final old = tab?.querySelector('[data-item="${_cssId(id)}"]');
  if (tab == null || old == null) return _redrawTab(ui, trip);
  final fresh = attackTab(ui, trip, only: id);
  final card = fresh.querySelector('[data-item="${_cssId(id)}"]');
  final row = fresh.querySelector('.chips');
  final oldRow = tab.querySelector('.chips');
  if (card == null || row == null || oldRow == null) return _redrawTab(ui, trip);
  old.replaceWith(card);
  oldRow.replaceWith(row);
}

String _cssId(String id) => id.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

/// Which of the days left suit each person. The day with most votes is marked.
web.HTMLElement _dayVotes(Ui ui, Trip trip, NextUp item) {
  final me = ui.meIn(trip);
  final votes = item.dayVotes;
  final days = remainingDays(trip, DateTime.now());
  web.HTMLElement dayChip(int day) =>
      chip(tr('{0} Dan · {1}', [day + 1, trip.membersAmong(votes[day] ?? const {})]), () {
        toggleDayVote(votes, day, me);
        ui.saved();
        _redrawCard(ui, trip, item.id);
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
          chip(tr('Tjedan {0}', [week + 1]), () {
            open == week ? ui.openWeek.remove(item.id) : ui.openWeek[item.id] = week;
            _redrawCard(ui, trip, item.id);
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
/// The tick of [item]: on a day it writes that day's cost in Troškovi and turns
/// the thing green there; a tap on a green one takes it back, cost and all,
/// with the usual undo. On Sve or a week the box asks Koji dan?, offering every
/// day someone voted for, and that day is ticked as if it were open; once every
/// day is ticked a tap takes them all back.
void _tick(Ui ui, Trip trip, NextUp item, int? day) {
  final open = day != null
      ? (tickedOn(trip, item, day) ? const <int>[] : [day])
      : [for (final each in tickDays(item)) if (!tickedOn(trip, item, each)) each];
  if (open.isEmpty) {
    final days = trip.ticked[item.id] ?? const <int, Ticked>{};
    final back = day != null ? {day: days[day]!} : Map.of(days);
    final costs = [
      for (final ticked in back.values)
        for (final cost in trip.expenses)
          if (cost.id == ticked.costId) cost,
    ];
    back.keys.forEach(trip.ticked[item.id]!.remove);
    trip.expenses.removeWhere(costs.contains);
    ui.changed();
    ui.offerUndo(tr('Više nije plaćeno: {0}', [item.title]), () {
      (trip.ticked[item.id] ??= {}).addAll(back);
      trip.expenses.addAll(costs);
      ui.changed();
    });
    return;
  }
  final all = tickDays(item);
  costSheet(
    ui,
    trip,
    title: item.title,
    action: tr('Dodaj u troškove'),
    category: item.category,
    days: day == null ? all : const [],
    daysDone: {for (final each in all) if (tickedOn(trip, item, each)) each},
    done: (cost, chosen) {
      item.place?.expenseId = cost.id;
      (trip.ticked[item.id] ??= {})[day ?? chosen ?? open.first] =
          Ticked(at: DateTime.now().millisecondsSinceEpoch, costId: cost.id);
    },
  );
}

web.HTMLElement _card(Ui ui, Trip trip, NextUp item, int? day) {
  final detail = item.detail;
  // Green when ticked off on this day, or on Sve once every day is; on Sve a
  // thing ticked on some of its days has a green edge.
  final share = day == null ? tickedShare(trip, item) : (tickedOn(trip, item, day) ? 1.0 : 0.0);
  final done = share == 1;
  return el('div', attrs: {'data-item': item.id}, cls: [
    'poll card attack-card',
    if (item.past) 'past',
    if (done) 'done' else if (share > 0) 'partly',
  ].join(' '), children: [
    el('div', cls: 'attack-top', children: [
    el('div', cls: 'grow', children: [
      if (_when(trip, item).isNotEmpty) el('div', cls: 'small', text: _when(trip, item)),
      el('div', cls: 'title', text: item.title),
      if (detail != null) el('div', cls: 'label', text: detail),
    ]),
    // Writes it in Troškovi, as a new cost: what it cost, who paid, for whom.
    button(
      cls: done ? 'icon-button cost-tick on' : 'icon-button cost-tick',
      ariaLabel: tr('Dodaj u troškove: {0}', [item.title]),
      onTap: () => _tick(ui, trip, item, day),
      children: [icon('check', size: 20)],
    ),
    // The x right of the tick, in the top right corner.
    button(
      cls: 'icon-button attack-x',
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
///
/// With [only], the row of days and just the card of that id are drawn, for
/// [_redrawCard].
web.HTMLElement attackTab(Ui ui, Trip trip, {String? only}) {
  final items = planOfAttack(trip, DateTime.now());
  final day = ui.attackDays[trip.id];
  final shown = day == null || day >= trip.dayCount ? null : day;
  // A trip of more than 7 days: Sve, its weeks, then the days of the open week.
  final weekly = trip.dayCount > 7;
  final weekCount = (trip.dayCount + 6) ~/ 7;
  final openWeek = weekly ? ui.attackWeeks[trip.id] : null;
  final kept = ui.attackKept;
  final stays = kept != null && kept.trip == trip.id && kept.day == shown
      ? kept.ids
      : const <String>{};
  bool inWeek(NextUp item) => openWeek != null && item.days.any((day) => day ~/ 7 == openWeek);
  final chosen = [
    for (final item in items)
      if (shown != null
          ? item.days.contains(shown) || stays.contains(item.id)
          : openWeek == null || inWeek(item))
        item,
  ];
  ui.attackKept =
      shown == null ? null : (trip: trip.id, day: shown, ids: {for (final item in chosen) item.id});
  final view = shown != null ? 'd$shown' : openWeek != null ? 'w$openWeek' : 'all';
  final order = ui.attackOrder;
  final List<NextUp> ordered;
  if (order != null && order.trip == trip.id && order.view == view) {
    final byId = {for (final item in chosen) item.id: item};
    ordered = [
      for (final id in order.ids)
        if (byId[id] case final item?) item,
      for (final item in chosen)
        if (!order.ids.contains(item.id)) item,
    ];
  } else {
    ordered = tickedLast(trip, chosen, shown);
  }
  ui.attackOrder = (trip: trip.id, view: view, ids: [for (final item in ordered) item.id]);
  void pick(int? next) {
    next == null ? ui.attackDays.remove(trip.id) : ui.attackDays[trip.id] = next;
    if (next == null) ui.attackWeeks.remove(trip.id);
    ui.attackKept = null;
    _redrawTab(ui, trip);
  }

  void pickWeek(int week) {
    // The open week again closes it; another opens with all its days shown.
    openWeek == week ? ui.attackWeeks.remove(trip.id) : ui.attackWeeks[trip.id] = week;
    ui.attackDays.remove(trip.id);
    ui.attackKept = null;
    _redrawTab(ui, trip);
  }

  web.HTMLElement dayChip(int i) =>
      chip('${tr('{0} Dan', [i + 1])} (${items.where((item) => item.days.contains(i)).length})',
          () => pick(i), on: i == shown);

  // The row stays turned where it was, whatever is picked in it.
  final row = el('div', cls: 'chips', children: [
    chip('${tr('Sve')} (${items.length})', () => pick(null), on: shown == null && openWeek == null),
    if (!weekly)
      for (var i = 0; i < trip.dayCount; i++) dayChip(i)
    else ...[
      for (var week = 0; week < weekCount; week++)
        chip('${tr('Tjedan {0}', [week + 1])} (${items.where((item) => item.days.any((day) => day ~/ 7 == week)).length})',
            () => pickWeek(week), on: openWeek == week && shown == null)
          ..classList.toggle('week-open', openWeek == week),
      if (openWeek != null)
        for (var i = openWeek * 7; i < trip.dayCount && i < openWeek * 7 + 7; i++) dayChip(i),
    ],
  ]);
  row.onScroll.listen((_) => ui.attackRowLeft[trip.id] = row.scrollLeft.toDouble());
  final left = ui.attackRowLeft[trip.id];
  if (left != null) scheduleMicrotask(() => row.scrollLeft = left);

  return el('div', cls: 'attack-tab', children: [
    row,
    if (items.isEmpty)
      el('p', cls: 'soft pad gap-top', text: tr('Još nema ničega u planu.'))
    else if (chosen.isEmpty)
      el('p', cls: 'soft pad gap-top',
          text: shown == null ? tr('Za ovaj tjedan još ništa nije dogovoreno.') : tr('Za ovaj dan još ništa nije dogovoreno.')),
    for (final item in ordered)
      if (only == null || item.id == only) _card(ui, trip, item, shown),
  ]);
}
