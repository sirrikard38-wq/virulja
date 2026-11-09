import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'cost_sheet.dart';
import 'dom.dart';
import 'icons.dart';
import 'plan_cost.dart';
import 'swipes.dart';
import 'widgets.dart';

/// After a part of the journey is added or changed, its cost in Troškovi. With
/// a price and no cost written yet, the cost box asks who paid and whom it is
/// for, as Dodaj trošak does, named as the part is; with one written, it
/// follows the name and the price.
void _afterLeg(Ui ui, Trip trip, Leg leg) {
  final written = legExpense(trip, leg);
  if (written != null) {
    written.title = legName(leg);
    if (leg.cost > 0) written.amount = leg.cost;
  }
  ui.changed();
  if (written != null || leg.cost <= 0) return;
  costSheet(
    ui,
    trip,
    title: legName(leg),
    action: tr('Dodaj trošak'),
    category: CostCategory.transport,
    guess: leg.cost,
    done: (cost, _) => leg.expenseId = cost.id,
  );
}

/// Relacija on a third of its row, growing with its text; under it Prijevoz
/// and Iznos, half and half. Any of them may stay empty, for the brush later.
List<web.HTMLElement> _legFields(
        web.HTMLInputElement title, web.HTMLInputElement route, web.HTMLInputElement cost) =>
    [
      el('div', cls: 'form-row', children: [
        growWithText(field(tr('Relacija'), route, tight: true)..classList.add('third'), route,
            least: 1 / 3),
      ]),
      el('div', cls: 'form-row', children: [
        field(tr('Prijevoz'), title, tight: true),
        unitField(tr('Iznos'), cost, moneySign()),
      ]),
    ];

/// Whether anything at all was typed of a part of the journey.
bool _anyTyped(List<web.HTMLInputElement> boxes, web.HTMLElement error) {
  if (boxes.any((box) => box.value.trim().isNotEmpty)) return true;
  error.textContent = tr('Upiši prijevoz, relaciju ili iznos.');
  return false;
}

/// What was written of a part of the journey, open for changing: what, where
/// and what it costs. Its brush, tapped again, saves it.
({web.HTMLElement form, void Function() save}) _legEdit(Ui ui, Trip trip, Leg leg) {
  final title = input(value: leg.title);
  final route = input(value: leg.route, placeholder: tr('Početak - kraj'));
  final cost = amountInput(value: leg.cost == 0 ? '' : plainAmount(leg.cost));
  final error = errorLine();

  void save() {
    if (!_anyTyped([title, route, cost], error)) return;
    leg
      ..title = title.value.trim()
      ..route = route.value.trim()
      ..cost = parseEuros(cost.value) ?? 0;
    ui.editingLeg = null;
    _afterLeg(ui, trip, leg);
  }

  return (
    form: el('div', cls: 'leg-edit', children: [..._legFields(title, route, cost), error]),
    save: save,
  );
}

/// A part of the journey other than by car, on [day].
web.HTMLElement _addLeg(Ui ui, Trip trip, int day) {
  final title = input();
  final route = input(placeholder: tr('Početak - kraj'));
  final cost = amountInput();
  final error = errorLine();

  void add() {
    if (!_anyTyped([title, route, cost], error)) return;
    final leg = Leg(
      id: ui.store.newId(),
      title: title.value.trim(),
      route: route.value.trim(),
      cost: parseEuros(cost.value) ?? 0,
      dayIndex: day,
    );
    trip.legs.add(leg);
    _afterLeg(ui, trip, leg);
  }

  return adder(tr('Dodaj prijevoz'), [
    ..._legFields(title, route, cost),
    error,
    primaryButton(tr('Dodaj'), add),
  ]);
}

/// A drive by car on [day], or the one of [editing] to change: Ruta on a third
/// of its row, growing with its text, and under it what was paid for fuel,
/// tolls, the ferry and anything else, which add up to its cost.
({List<web.Node> fields, void Function() save}) _driveFields(Ui ui, Trip trip, int day,
    {Leg? editing}) {
  final drive = editing?.drive ?? Drive(roundTrip: false);
  String typed(int cents) => cents == 0 ? '' : plainAmount(cents);
  final route = input(value: drive.route, placeholder: tr('Početak - kraj'));
  final fuel = amountInput(value: typed(drive.fuelCost));
  final tolls = amountInput(value: typed(drive.tolls));
  final ferry = amountInput(value: typed(drive.ferry));
  final extra = amountInput(value: typed(drive.extra));

  void save() {
    final now = Drive(
      route: route.value.trim(),
      kilometres: drive.kilometres,
      roundTrip: false,
      fuel: parseEuros(fuel.value) ?? 0,
      tolls: parseEuros(tolls.value) ?? 0,
      ferry: parseEuros(ferry.value) ?? 0,
      extra: parseEuros(extra.value) ?? 0,
    );
    final Leg leg;
    if (editing == null) {
      leg = Leg(
        id: ui.store.newId(),
        title: now.route,
        cost: now.totalCost,
        dayIndex: day,
        drive: now,
      );
      trip.legs.add(leg);
    } else {
      leg = editing
        ..title = now.route
        ..cost = now.totalCost
        ..drive = now;
      ui.editingLeg = null;
    }
    // Its cost goes in Troškovi as that of any other transport.
    _afterLeg(ui, trip, leg);
  }

  return (
    fields: [
      el('div', cls: 'form-row', children: [
        growWithText(field(tr('Ruta'), route, tight: true)..classList.add('third'), route,
            least: 1 / 3),
      ]),
      el('div', cls: 'form-row one-line', children: [
        unitField(tr('Gorivo'), fuel, moneySign()),
        unitField(tr('Cestarine'), tolls, moneySign()),
        unitField(tr('Trajekt'), ferry, moneySign()),
        unitField(tr('Ekstra'), extra, moneySign()),
      ]),
    ],
    save: save,
  );
}

/// Dodaj prijevoz autom, on [day].
web.HTMLElement _driveForm(Ui ui, Trip trip, int day) {
  final drive = _driveFields(ui, trip, day);
  return adder(tr('Dodaj prijevoz autom'), [...drive.fields, primaryButton(tr('Dodaj'), drive.save)]);
}

/// One part of the journey on its day: what it costs, the brush that opens it
/// for changing, and the x. It is so as written: no vote, not in Plan napada.
/// Open, the part and its form stand in one outline, and the brush, green,
/// saves it.
List<web.HTMLElement> _legRow(Ui ui, Trip trip, Leg leg) {
  final open = ui.editingLeg == leg.id;
  ({web.HTMLElement form, void Function() save})? edit;
  if (open && leg.drive != null) {
    final drive = _driveFields(ui, trip, leg.dayIndex, editing: leg);
    edit = (form: el('div', cls: 'leg-edit', children: drive.fields), save: drive.save);
  } else if (open) {
    edit = _legEdit(ui, trip, leg);
  }
  final row = el('div', cls: 'row', children: [
    el('div', cls: 'grow', text: legName(leg)),
    if (leg.cost > 0) el('div', cls: 'price', text: euros(leg.cost)),
    button(
      cls: open ? 'icon-button brush-small on' : 'icon-button brush-small',
      ariaLabel: open ? tr('Spremi') : tr('Uredi: {0}', [legName(leg)]),
      onTap: () {
        if (edit != null) {
          edit.save();
          return;
        }
        ui.editingLeg = leg.id;
        ui.rerender();
      },
      children: [icon('brush', size: 20)],
    ),
    // Its cost in Troškovi goes with it, and comes back with undo.
    removeWithUndo(ui, trip.legs, leg, legName(leg), also: () {
      final at = trip.expenses.indexWhere((cost) => cost.id == leg.expenseId);
      if (at < 0) return () {};
      final cost = trip.expenses.removeAt(at);
      return () => trip.expenses.insert(at.clamp(0, trip.expenses.length), cost);
    }),
  ]);
  if (edit == null) return [row];
  return [el('div', cls: 'card leg-open', children: [row, edit.form])];
}

web.HTMLElement routeScreen(Ui ui, Trip trip) {
  if (moveOldDrive(trip)) ui.saved();
  final day = ui.routeDay.clamp(0, trip.dayCount - 1);

  /// What one day shows; the next one is drawn beside it during a swipe.
  web.HTMLElement dayPage(int shown) {
    final stops = trip.stops.where((stop) => stop.dayIndex == shown).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    final legs = legsOn(trip, shown);
    return el('div', children: [
      sectionTitle(weekdayAndDate(trip.dayAt(shown))),
      if (stops.isEmpty && legs.isEmpty)
        el('p', cls: 'soft pad', text: tr('Za ovaj dan još nema prijevoza.')),
      for (final stop in stops)
        el('div', cls: 'row', children: [
          if (stop.time.isNotEmpty) el('div', cls: 'label', text: stop.time),
          el('div', cls: 'grow', text: stop.title),
          if (stop.cost > 0) el('div', cls: 'price', text: euros(stop.cost)),
          removeWithUndo(ui, trip.stops, stop, stop.title),
        ]),
      for (final leg in legs) ..._legRow(ui, trip, leg),
    ]);
  }

  // A swipe sideways goes to the day before or after, as the chips do.
  final sliding = el('div', cls: 'slide-page', children: [dayPage(day)]);
  final dayRow = el('div', cls: 'chips', attrs: {
    'style': 'padding-top:0'
  }, children: [
    for (var i = 0; i < trip.dayCount; i++)
      chip(tr('{0} Dan', [i + 1]), () {
        ui.routeDay = i;
        ui.editingLeg = null;
        ui.rerender();
      }, on: i == day),
  ]);
  final mark = SwipeMark(dayRow);
  // All the days together and what Troškovi has of the kind Prijevoz besides,
  // shown on its tile in Plan.
  final all = transportTotal(trip);
  // A swipe anywhere on Prijevoz goes to the day before or after; the foot
  // stays at the bottom of the screen.
  final page = el('div', cls: 'swipe-area', children: [
    topBar(tr('Prijevoz')),
    dayRow,
    el('div', cls: 'slide-clip', children: [sliding]),
    // At the bottom, standing still whatever the day: the adders for the day
    // shown, right over the line of the foot.
    el('div', cls: 'route-foot', children: [
      _driveForm(ui, trip, day),
      _addLeg(ui, trip, day),
      el('div', cls: 'stick-bottom', children: [
        el('div', cls: 'row', attrs: {
          'style': 'padding:0'
        }, children: [
          el('div', cls: 'grow', text: tr('Prijevoz ukupno')),
          el('div', cls: 'price', text: euros(all)),
        ]),
        if (alsoIn(all) case final also when also.isNotEmpty)
          el('div',
              cls: 'small also',
              attrs: {'style': 'text-align:right'},
              text: also),
        planCost(ui, trip, CostCategory.transport.name),
      ]),
    ]),
  ]);
  // The chip of the day shown stands whole in sight, the last one too.
  scheduleMicrotask(() => showChosenChip(dayRow));
  followSwipes(page, sliding, (step) {
    final next = day + step;
    return next >= 0 && next < trip.dayCount;
  }, (step) {
    ui.routeDay = day + step;
    ui.editingLeg = null;
    ui.rerender();
    slideIn(step);
  },
      peek: (step) => dayPage(day + step),
      follow: (step, fraction) => mark.follow(
          dayRow.children.item(day + step) as web.HTMLElement?, fraction));
  return page;
}
