import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'polls_section.dart';
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
      error.textContent = 'Upiši što je u planu.';
      return;
    }
    trip.stops.add(Stop(
      id: ui.store.newId(),
      dayIndex: day,
      time: time.value,
      title: title.value.trim(),
      cost: parseEuros(cost.value) ?? 0,
    ));
    ui.changed();
  }

  return adder('Dodaj u plan', [
    field('Što', title),
    el('div', cls: 'fields', children: [
      field('Vrijeme', time, tight: true),
      field('Trošak za grupu (€)', cost, tight: true),
    ]),
    error,
    primaryButton('Dodaj', add),
  ]);
}

web.HTMLElement _addLeg(Ui ui, Trip trip) {
  final title = input();
  final cost = numberInput();
  final error = errorLine();

  void add() {
    if (title.value.trim().isEmpty) {
      error.textContent = 'Upiši kojim prijevozom i kamo.';
      return;
    }
    trip.legs.add(Leg(
      id: ui.store.newId(),
      title: title.value.trim(),
      cost: parseEuros(cost.value) ?? 0,
    ));
    ui.changed();
  }

  return adder('Dodaj prijevoz', [
    field('Prijevoz i relacija', title),
    field('Trošak za grupu (€)', cost),
    error,
    primaryButton('Dodaj', add),
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

  return adder('Dodaj prijevoz autom', [
    field('Ruta', route),
    el('div', cls: 'fields', children: [
      field('Kilometara u jednom smjeru', km, tight: true),
      field('Broj auta', cars, tight: true),
    ]),
    el('div', cls: 'fields', children: [
      field('Potrošnja (l/100 km)', litres, tight: true),
      field('Cijena goriva (€/l)', fuel, tight: true),
    ]),
    el('div', cls: 'fields', children: [
      field('Cestarine (€)', tolls, tight: true),
      field('Trajekt (€)', ferry, tight: true),
    ]),
    el('div', cls: 'checks', children: [checkbox('Računaj oba smjera', both)]),
    el('div', cls: 'row', attrs: {'style': 'margin-top:8px'}, children: [
      el('div', cls: 'grow', text: 'Gorivo'),
      el('div', cls: 'price', text: euros(drive.fuelCost)),
    ]),
    el('div', cls: 'row', children: [
      el('div', cls: 'grow strong', text: 'Prijevoz ukupno'),
      el('div', cls: 'price', text: euros(drive.totalCost)),
    ]),
    primaryButton('Izračunaj', update),
  ]);
}

web.HTMLElement routeScreen(Ui ui, Trip trip) {
  final day = ui.routeDay.clamp(0, trip.dayCount - 1);
  final stops = trip.stops.where((stop) => stop.dayIndex == day).toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  return el('div', children: [
    topBar('Plan puta'),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
      for (var i = 0; i < trip.dayCount; i++)
        chip('Dan ${i + 1}', () {
          ui.routeDay = i;
          ui.rerender();
        }, on: i == day),
    ]),
    sectionTitle(weekdayAndDate(trip.dayAt(day))),
    if (stops.isEmpty) el('p', cls: 'soft pad', text: 'Za ovaj dan još nema plana.'),
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
    pollsSection(ui, trip),
    newPoll(ui, trip),
    sectionTitle('Prijevoz'),
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
        el('div', cls: 'grow', text: trip.drive.route.isEmpty ? 'Auto' : 'Auto: ${trip.drive.route}'),
        el('div', cls: 'price', text: euros(trip.drive.totalCost)),
      ]),
    _driveForm(ui, trip),
    _addLeg(ui, trip),
  ]);
}
