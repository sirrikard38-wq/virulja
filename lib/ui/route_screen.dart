import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'plan_cost.dart';
import 'swipes.dart';
import 'widgets.dart';

String _number(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value'.replaceAll('.', ',');

double? _parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

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
    field(inMoney(tr('Trošak za grupu (€)')), cost),
    error,
    el('div', attrs: {'style': 'display:flex;gap:12px;align-items:center;margin:10px 20px 0'}, children: [
      primaryButton(tr('Spremi'), save, wide: false),
      button(cls: 'text-button', text: tr('Odustani'), onTap: () {
        ui.editingLeg = null;
        ui.rerender();
      }),
    ]),
  ]);
}

web.HTMLElement _addLeg(Ui ui, Trip trip) {
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
    ));
    ui.changed();
  }

  return adder(tr('Dodaj prijevoz'), [
    field(tr('Prijevoz i relacija'), title),
    field(inMoney(tr('Trošak za grupu (€)')), cost),
    error,
    primaryButton(tr('Dodaj'), add),
  ]);
}

web.HTMLElement _driveForm(Ui ui, Trip trip) {
  final drive = trip.drive;
  final route = input(value: drive.route);
  final km = numberInput(value: drive.kilometres == 0 ? '' : _number(drive.kilometres));
  final litres = numberInput(value: _number(drive.litresPer100));
  final fuel = amountInput(value: plainAmount(drive.fuelPrice));
  final cars = numberInput(value: '${drive.cars}');
  final tolls = amountInput(value: drive.tolls == 0 ? '' : plainAmount(drive.tolls));
  final ferry = amountInput(value: drive.ferry == 0 ? '' : plainAmount(drive.ferry));
  final both = checkInput(checked: drive.roundTrip);

  void update() {
    drive
      ..route = route.value.trim()
      ..kilometres = _parseNumber(km.value) ?? 0
      ..roundTrip = both.checked
      ..litresPer100 = _parseNumber(litres.value) ?? drive.litresPer100
      ..fuelPrice = parseEuros(fuel.value) ?? drive.fuelPrice
      ..cars = int.tryParse(cars.value.trim()) ?? drive.cars
      ..tolls = parseEuros(tolls.value) ?? 0
      ..ferry = parseEuros(ferry.value) ?? 0;
    ui.changed();
  }

  return adder(tr('Dodaj prijevoz autom'), [
    field(tr('Ruta'), route),
    el('div', cls: 'fields', children: [
      field(tr('Kilometara u jednom smjeru'), km, tight: true),
      field(tr('Broj auta'), cars, tight: true),
    ]),
    el('div', cls: 'fields', children: [
      field(tr('Potrošnja (l/100 km)'), litres, tight: true),
      field(inMoney(tr('Cijena goriva (€/l)')), fuel, tight: true),
    ]),
    el('div', cls: 'fields', children: [
      field(inMoney(tr('Cestarine (€)')), tolls, tight: true),
      field(inMoney(tr('Trajekt (€)')), ferry, tight: true),
    ]),
    el('div', cls: 'checks', children: [checkbox(tr('Računaj oba smjera'), both)]),
    el('div', cls: 'row', attrs: {'style': 'margin-top:8px'}, children: [
      el('div', cls: 'grow', text: tr('Gorivo')),
      el('div', cls: 'price', text: euros(drive.fuelCost)),
    ]),
    el('div', cls: 'row', children: [
      el('div', cls: 'grow strong', text: tr('Prijevoz ukupno')),
      el('div', cls: 'price', text: euros(drive.totalCost)),
    ]),
    primaryButton(tr('Izračunaj'), update),
  ]);
}

web.HTMLElement routeScreen(Ui ui, Trip trip) {
  final day = ui.routeDay.clamp(0, trip.dayCount - 1);

  /// What one day shows; the next one is drawn beside it during a swipe.
  web.HTMLElement dayPage(int shown) {
    final stops = trip.stops.where((stop) => stop.dayIndex == shown).toList()
      ..sort((a, b) => a.time.compareTo(b.time));
    return el('div', children: [
      sectionTitle(weekdayAndDate(trip.dayAt(shown))),
      if (stops.isEmpty) el('p', cls: 'soft pad', text: tr('Za ovaj dan još nema plana.')),
      for (final stop in stops)
        el('div', cls: 'row', children: [
          if (stop.time.isNotEmpty) el('div', cls: 'label', text: stop.time),
          el('div', cls: 'grow', text: stop.title),
          if (stop.cost > 0) el('div', cls: 'price', text: euros(stop.cost)),
          removeWithUndo(ui, trip.stops, stop, stop.title),
        ]),
    ]);
  }

  // A swipe sideways goes to the day before or after, as the chips do.
  final sliding = el('div', cls: 'slide-page', children: [dayPage(day)]);
  final dayRow = el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
    for (var i = 0; i < trip.dayCount; i++)
      chip(tr('{0} Dan', [i + 1]), () {
        ui.routeDay = i;
        ui.rerender();
      }, on: i == day),
  ]);
  final mark = SwipeMark(dayRow);
  // Only the day swipes; the rest of Prijevoz follows right under it.
  final days = el('div', cls: 'swipe-area day-swipe', children: [
    el('div', cls: 'slide-clip', children: [sliding]),
  ]);
  followSwipes(days, sliding, (step) {
    final next = day + step;
    return next >= 0 && next < trip.dayCount;
  }, (step) {
    ui.routeDay = day + step;
    ui.rerender();
    slideIn(step);
  },
      peek: (step) => dayPage(day + step),
      follow: (step, fraction) => mark.follow(dayRow.children.item(day + step) as web.HTMLElement?, fraction));
  return el('div', cls: 'fill-page', children: [
    topBar(tr('Prijevoz')),
    dayRow,
    days,
    // A reserved part of the journey goes into Plan napada, where the group
    // picks its day.
    for (final leg in trip.legs) ...[
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', text: leg.title),
        if (leg.cost > 0) el('div', cls: 'price', text: euros(leg.cost)),
        chip(tr('Rezervirano'), () {
          leg.reserved = !leg.reserved;
          ui.changed();
          if (leg.reserved) ui.toast(tr('Dodano u Plan napada.'));
        }, on: leg.reserved),
        // The brush opens what was written of it for changing.
        button(
          cls: ui.editingLeg == leg.id ? 'icon-button brush-small on' : 'icon-button brush-small',
          ariaLabel: tr('Uredi: {0}', [leg.title]),
          onTap: () {
            ui.editingLeg = ui.editingLeg == leg.id ? null : leg.id;
            ui.rerender();
          },
          children: [icon('brush', size: 20)],
        ),
        removeWithUndo(ui, trip.legs, leg, leg.title),
      ]),
      if (ui.editingLeg == leg.id) _legEdit(ui, leg),
    ],
    if (trip.drive.totalCost > 0)
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', text: trip.drive.route.isEmpty ? tr('Auto') : tr('Auto: {0}', [trip.drive.route])),
        el('div', cls: 'price', text: euros(trip.drive.totalCost)),
      ]),
    _driveForm(ui, trip),
    _addLeg(ui, trip),
    planCost(ui, trip, CostCategory.transport.name),
  ]);
}
