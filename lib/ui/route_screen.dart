import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'plan_cost.dart';
import 'swipes.dart';
import 'widgets.dart';

/// Spremi and Odustani under a form opened with a brush.
web.HTMLElement _saveOrCancel(Ui ui, void Function() save) => el('div', attrs: {
      'style': 'display:flex;gap:12px;align-items:center;margin:10px 20px 0'
    }, children: [
      primaryButton(tr('Spremi'), save, wide: false),
      button(
          cls: 'text-button',
          text: tr('Odustani'),
          onTap: () {
            ui.editingLeg = null;
            ui.rerender();
          }),
    ]);

/// Changes what was written of a part of the journey: what and what it costs.
web.HTMLElement _legEdit(Ui ui, Leg leg) {
  final title = input(value: leg.title);
  final cost = amountInput(value: leg.cost == 0 ? '' : plainAmount(leg.cost));
  final error = errorLine();

  void save() {
    if (title.value.trim().isEmpty) {
      error.textContent = tr('Upiši kojim prijevozom i kamo.');
      return;
    }
    leg
      ..title = title.value.trim()
      ..cost = parseEuros(cost.value) ?? 0;
    ui.editingLeg = null;
    ui.changed();
  }

  return el('div', cls: 'leg-edit', children: [
    field(tr('Prijevoz i relacija'), title),
    unitField(tr('Trošak za grupu'), cost, moneySign(), tight: false),
    error,
    _saveOrCancel(ui, save),
  ]);
}

/// A part of the journey other than by car, on [day].
web.HTMLElement _addLeg(Ui ui, Trip trip, int day) {
  final title = input();
  final cost = amountInput();
  final error = errorLine();

  void add() {
    if (title.value.trim().isEmpty) {
      error.textContent = tr('Upiši kojim prijevozom i kamo.');
      return;
    }
    trip.legs.add(Leg(
      id: ui.store.newId(),
      title: title.value.trim(),
      cost: parseEuros(cost.value) ?? 0,
      dayIndex: day,
    ));
    ui.changed();
  }

  return adder(tr('Dodaj prijevoz'), [
    field(tr('Prijevoz i relacija'), title),
    unitField(tr('Trošak za grupu'), cost, moneySign(), tight: false),
    error,
    primaryButton(tr('Dodaj'), add),
  ]);
}

/// A drive by car on [day], or the one of [editing] to change: what it costs is
/// worked out from the kilometres and the fuel as it is typed.
web.HTMLElement _driveForm(Ui ui, Trip trip, int day, {Leg? editing}) {
  // A new car starts from the last one: the same cars use the same fuel.
  final last = [
    for (final leg in trip.legs)
      if (leg.drive != null) leg.drive!,
  ];
  final drive = editing?.drive ?? Drive(roundTrip: false);
  final like = editing?.drive ?? (last.isEmpty ? drive : last.last);
  final route = input(value: drive.route);
  final km = numberInput(
      value: drive.kilometres == 0 ? '' : decimal(drive.kilometres));
  final litres = numberInput(value: decimal(like.litresPer100));
  final fuel = amountInput(value: plainAmount(like.fuelPrice));
  final cars = numberInput(value: '${like.cars}');
  final tolls =
      amountInput(value: drive.tolls == 0 ? '' : plainAmount(drive.tolls));
  final ferry =
      amountInput(value: drive.ferry == 0 ? '' : plainAmount(drive.ferry));
  final fuelCost = el('div', cls: 'price');
  final total = el('div', cls: 'price');

  Drive typed() => Drive(
        route: route.value.trim(),
        kilometres: parseDecimal(km.value) ?? 0,
        roundTrip: false,
        litresPer100: parseDecimal(litres.value) ?? like.litresPer100,
        fuelPrice: parseEuros(fuel.value) ?? like.fuelPrice,
        cars: int.tryParse(cars.value.trim()) ?? like.cars,
        tolls: parseEuros(tolls.value) ?? 0,
        ferry: parseEuros(ferry.value) ?? 0,
      );

  void show() {
    final now = typed();
    fuelCost.textContent = euros(now.fuelCost);
    total.textContent = euros(now.totalCost);
  }

  for (final box in [km, litres, fuel, cars, tolls, ferry]) {
    box.onInput.listen((_) => show());
  }
  show();

  void save() {
    final now = typed();
    if (editing == null) {
      trip.legs.add(Leg(
        id: ui.store.newId(),
        title: now.route,
        cost: now.totalCost,
        dayIndex: day,
        drive: now,
      ));
    } else {
      editing
        ..title = now.route
        ..cost = now.totalCost
        ..drive = now;
      ui.editingLeg = null;
    }
    ui.changed();
  }

  final fields = <web.Node>[
    field(tr('Ruta'), route),
    el('div', cls: 'fields', children: [
      unitField(tr('Udaljenost'), km, 'km'),
      field(tr('Broj auta'), cars, tight: true),
    ]),
    el('div', cls: 'fields', children: [
      unitField(tr('Potrošnja'), litres, 'l/100 km'),
      unitField(tr('Cijena goriva'), fuel, '${moneySign()}/l'),
    ]),
    el('div', cls: 'fields', children: [
      unitField(tr('Cestarine'), tolls, moneySign()),
      unitField(tr('Trajekt'), ferry, moneySign()),
    ]),
    el('div', cls: 'row', attrs: {
      'style': 'margin-top:8px'
    }, children: [
      el('div', cls: 'grow', text: tr('Gorivo')),
      fuelCost,
    ]),
    el('div', cls: 'row', children: [
      el('div', cls: 'grow strong', text: tr('Auto ukupno')),
      total,
    ]),
  ];
  return editing == null
      ? adder(tr('Dodaj prijevoz autom'),
          [...fields, primaryButton(tr('Dodaj'), save)])
      : el('div',
          cls: 'leg-edit', children: [...fields, _saveOrCancel(ui, save)]);
}

/// One part of the journey on its day: what it costs, the brush that opens it
/// for changing, and the x. It is so as written: no vote, not in Plan napada.
List<web.HTMLElement> _legRow(Ui ui, Trip trip, Leg leg) => [
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', text: legName(leg)),
        if (leg.cost > 0) el('div', cls: 'price', text: euros(leg.cost)),
        button(
          cls: ui.editingLeg == leg.id
              ? 'icon-button brush-small on'
              : 'icon-button brush-small',
          ariaLabel: tr('Uredi: {0}', [legName(leg)]),
          onTap: () {
            ui.editingLeg = ui.editingLeg == leg.id ? null : leg.id;
            ui.rerender();
          },
          children: [icon('brush', size: 20)],
        ),
        removeWithUndo(ui, trip.legs, leg, legName(leg)),
      ]),
      if (ui.editingLeg == leg.id)
        leg.drive != null
            ? _driveForm(ui, trip, leg.dayIndex, editing: leg)
            : _legEdit(ui, leg),
    ];

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
  // All the days together: the cost of transport, shown on its tile in Plan.
  final all = plannedCost(trip, CostCategory.transport);
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
