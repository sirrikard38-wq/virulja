import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'plan_cost.dart';
import 'swipes.dart';
import 'widgets.dart';

String _number(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value'.replaceAll('.', ',');

double? _parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

web.HTMLElement _addStop(Ui ui, Trip trip, int day) {
  final picker = timePicker();
  final time = picker.value;
  final title = input();
  final cost = amountInput();
  final error = errorLine();

  void add() {
    if (title.value.trim().isEmpty) {
      error.textContent = tr('Upiši što je u planu.');
      return;
    }
    trip.stops.add(Stop(
      id: ui.store.newId(),
      dayIndex: day,
      time: time.value,
      addedBy: ui.meIn(trip),
      title: title.value.trim(),
      cost: parseEuros(cost.value) ?? 0,
    ));
    ui.changed();
  }

  return adder(tr('Dodaj u plan'), [
    field(tr('Što'), title),
    el('div', cls: 'fields', children: [
      field(tr('Vrijeme'), picker.view, tight: true),
      field(inMoney(tr('Trošak za grupu (€)')), cost, tight: true),
    ]),
    error,
    primaryButton(tr('Dodaj'), add),
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
  final stops = trip.stops.where((stop) => stop.dayIndex == day).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  // A swipe sideways goes to the day before or after, as the chips do.
  final sliding = el('div', cls: 'slide-page', children: [
    sectionTitle(weekdayAndDate(trip.dayAt(day))),
    if (stops.isEmpty) el('p', cls: 'soft pad', text: tr('Za ovaj dan još nema plana.')),
    for (final stop in stops)
      el('div', cls: 'row', children: [
        if (stop.time.isNotEmpty) el('div', cls: 'label', text: stop.time),
        el('div', cls: 'grow', text: stop.title),
        if (stop.cost > 0) el('div', cls: 'price', text: euros(stop.cost)),
        removeWithUndo(ui, trip.stops, stop, stop.title),
      ]),
    _addStop(ui, trip, day),
  ]);
  final days = el('div', cls: 'swipe-area', children: [
    el('div', cls: 'slide-clip', children: [sliding]),
  ]);
  followSwipes(days, sliding, (step) {
    final next = day + step;
    return next >= 0 && next < trip.dayCount;
  }, (step) {
    ui.routeDay = day + step;
    ui.rerender();
    slideIn(step);
  });
  return el('div', cls: 'fill-page', children: [
    topBar(tr('Prijevoz')),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
      for (var i = 0; i < trip.dayCount; i++)
        chip(tr('{0} Dan', [i + 1]), () {
          ui.routeDay = i;
          ui.rerender();
        }, on: i == day),
    ]),
    days,
    sectionTitle(tr('Prijevoz')),
    // A reserved part of the journey goes into Plan napada, where the group
    // picks its day.
    for (final leg in trip.legs)
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', text: leg.title),
        if (leg.cost > 0) el('div', cls: 'price', text: euros(leg.cost)),
        chip(tr('Rezervirano'), () {
          leg.reserved = !leg.reserved;
          ui.changed();
          if (leg.reserved) ui.toast(tr('Dodano u Plan napada.'));
        }, on: leg.reserved),
        removeWithUndo(ui, trip.legs, leg, leg.title),
      ]),
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
