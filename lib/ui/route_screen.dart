import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

String _number(double value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value'.replaceAll('.', ',');

double? _parseNumber(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

web.HTMLElement _addStop(Ui ui, Trip trip, int day) {
  final time = input(type: 'time');
  final title = input();
  final cost = numberInput();
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
      field(tr('Vrijeme'), time, tight: true),
      field(tr('Trošak za grupu (€)'), cost, tight: true),
    ]),
    error,
    primaryButton(tr('Dodaj'), add),
  ]);
}

web.HTMLElement _addLeg(Ui ui, Trip trip) {
  final title = input();
  final cost = numberInput();
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
    field(tr('Trošak za grupu (€)'), cost),
    error,
    primaryButton(tr('Dodaj'), add),
  ]);
}

web.HTMLElement _driveForm(Ui ui, Trip trip) {
  final drive = trip.drive;
  final route = input(value: drive.route);
  final km = numberInput(value: drive.kilometres == 0 ? '' : _number(drive.kilometres));
  final litres = numberInput(value: _number(drive.litresPer100));
  final fuel = numberInput(value: euros(drive.fuelPrice).replaceAll(' €', ''));
  final cars = numberInput(value: '${drive.cars}');
  final tolls = numberInput(value: drive.tolls == 0 ? '' : euros(drive.tolls).replaceAll(' €', ''));
  final ferry = numberInput(value: drive.ferry == 0 ? '' : euros(drive.ferry).replaceAll(' €', ''));
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
      field(tr('Cijena goriva (€/l)'), fuel, tight: true),
    ]),
    el('div', cls: 'fields', children: [
      field(tr('Cestarine (€)'), tolls, tight: true),
      field(tr('Trajekt (€)'), ferry, tight: true),
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
  return el('div', children: [
    topBar(tr('Plan puta')),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
      for (var i = 0; i < trip.dayCount; i++)
        chip(tr('Dan {0}', [i + 1]), () {
          ui.routeDay = i;
          ui.rerender();
        }, on: i == day),
    ]),
    sectionTitle(weekdayAndDate(trip.dayAt(day))),
    if (stops.isEmpty) el('p', cls: 'soft pad', text: tr('Za ovaj dan još nema plana.')),
    for (final stop in stops)
      el('div', cls: 'row', children: [
        if (stop.time.isNotEmpty) el('div', cls: 'label', text: stop.time),
        el('div', cls: 'grow', text: stop.title),
        if (stop.cost > 0) el('div', cls: 'price', text: euros(stop.cost)),
        removeButton(stop.title, () {
          trip.stops.remove(stop);
          ui.changed();
        }),
      ]),
    _addStop(ui, trip, day),
    sectionTitle(tr('Prijevoz')),
    for (final leg in trip.legs)
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', text: leg.title),
        if (leg.cost > 0) el('div', cls: 'price', text: euros(leg.cost)),
        removeButton(leg.title, () {
          trip.legs.remove(leg);
          ui.changed();
        }),
      ]),
    if (trip.drive.totalCost > 0)
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', text: trip.drive.route.isEmpty ? tr('Auto') : tr('Auto: {0}', [trip.drive.route])),
        el('div', cls: 'price', text: euros(trip.drive.totalCost)),
      ]),
    _driveForm(ui, trip),
    _addLeg(ui, trip),
  ]);
}
