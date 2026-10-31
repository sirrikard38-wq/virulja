import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

String _placeFacts(Place place) => [
      if (place.rating != null) place.rating!.toString().replaceAll('.', ','),
      if (place.pricePerPerson != null) '${euros(place.pricePerPerson!)} po osobi',
      if (place.note != null) place.note!,
    ].join(' · ');

web.HTMLElement _placeRow(Ui ui, Trip trip, Place place) {
  final link = place.link;
  return el('div', cls: 'row', children: [
    el('div', cls: 'grow', children: [
      el('div', cls: 'label', text: place.name),
      el('div', cls: 'small', text: _placeFacts(place)),
    ]),
    if (link != null) linkIcon(link, 'Otvori ${place.name}'),
    chip(place.planned ? 'U planu' : 'Dodaj', () {
      place.planned = !place.planned;
      ui.changed();
    }, on: place.planned),
    removeButton(place.name, () {
      trip.places.remove(place);
      ui.changed();
    }),
  ]);
}

web.HTMLElement _addPlace(Ui ui, Trip trip) {
  final name = input(placeholder: 'Konoba Stara uvala');
  final rating = numberInput(placeholder: '4,7');
  final price = numberInput(placeholder: '28');
  final note = input(placeholder: 'Peka, rezervirati dan ranije');
  final link = input(type: 'url', placeholder: 'https://');
  final error = errorLine();

  void add() {
    if (name.value.trim().isEmpty) {
      error.textContent = 'Upiši naziv mjesta.';
      return;
    }
    final address = link.value.trim();
    final remark = note.value.trim();
    trip.places.add(Place(
      id: ui.store.newId(),
      kind: ui.placeKind,
      name: name.value.trim(),
      rating: double.tryParse(rating.value.trim().replaceAll(',', '.')),
      pricePerPerson: parseEuros(price.value),
      note: remark.isEmpty ? null : remark,
      link: address.isEmpty ? null : address,
    ));
    ui.changed();
  }

  return adder('Dodaj mjesto', [
    field('Naziv', name),
    el('div', cls: 'fields', children: [
      field('Ocjena', rating, tight: true),
      field('Cijena po osobi (€)', price, tight: true),
    ]),
    field('Bilješka', note),
    field('Link', link),
    error,
    primaryButton('Dodaj mjesto', add),
  ]);
}

web.HTMLElement _dishRow(Ui ui, Trip trip, Dish dish) {
  final place = dish.placeName;
  return el('div', cls: 'row', children: [
    el('div', cls: 'grow', children: [
      el('div', cls: 'label', text: dish.name),
      el('div', cls: 'small', text: [
        if (place != null) place,
        '${dish.servings} × ${euros(dish.price)}',
      ].join(' · ')),
    ]),
    el('div', cls: 'price', text: euros(dish.price * dish.servings)),
    removeButton(dish.name, () {
      trip.dishes.remove(dish);
      ui.changed();
    }),
  ]);
}

web.HTMLElement _addDish(Ui ui, Trip trip) {
  final name = input(placeholder: 'Peka od hobotnice');
  final price = numberInput(placeholder: '28');
  final servings = numberInput(value: '1');
  final place = input(placeholder: 'Konoba Stara uvala');
  final error = errorLine();

  void add() {
    final cents = parseEuros(price.value);
    if (name.value.trim().isEmpty || cents == null) {
      error.textContent = 'Upiši jelo i cijenu.';
      return;
    }
    final where = place.value.trim();
    trip.dishes.add(Dish(
      id: ui.store.newId(),
      name: name.value.trim(),
      price: cents,
      servings: int.tryParse(servings.value.trim()) ?? 1,
      placeName: where.isEmpty ? null : where,
    ));
    ui.changed();
  }

  return adder('Dodaj jelo', [
    field('Jelo', name),
    el('div', cls: 'fields', children: [
      field('Cijena (€)', price, tight: true),
      field('Porcija', servings, tight: true),
    ]),
    field('Gdje', place),
    error,
    primaryButton('Dodaj jelo', add),
  ]);
}

web.HTMLElement foodScreen(Ui ui, Trip trip) {
  final kind = ui.placeKind;
  final places = trip.places.where((place) => place.kind == kind).toList();
  return el('div', children: [
    topBar('Hrana i piće'),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
      for (final item in PlaceKind.values)
        chip(item.label, () {
          ui.placeKind = item;
          ui.rerender();
        }, on: item == kind),
    ]),
    el('div', cls: 'pad gap-top', children: [
      outLink('Traži: ${kind.label} u mjestu ${trip.city}', mapsSearch(kind, trip)),
    ]),
    if (places.isEmpty)
      el('p', cls: 'soft pad gap-top', text: 'Još nema spremljenih mjesta.'),
    for (final place in places) _placeRow(ui, trip, place),
    _addPlace(ui, trip),
    sectionTitle('Jela koja želimo probati'),
    if (trip.dishes.isEmpty)
      el('p', cls: 'soft pad', text: 'Dodajte jela s cijenom s jelovnika.'),
    for (final dish in trip.dishes) _dishRow(ui, trip, dish),
    _addDish(ui, trip),
    el('div', cls: 'row', attrs: {'style': 'margin-top:12px'}, children: [
      el('div', cls: 'grow', text: 'Procjena za hranu i piće'),
      el('div', cls: 'price', text: euros(plannedCost(trip, CostCategory.food))),
    ]),
  ]);
}
