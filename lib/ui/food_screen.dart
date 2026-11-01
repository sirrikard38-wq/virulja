import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'polls_section.dart';
import 'widgets.dart';

String _placeFacts(Place place) => [
      if (place.rating != null) place.rating!.toString().replaceAll('.', ','),
      if (place.pricePerPerson != null) '${euros(place.pricePerPerson!)} po osobi',
      if (place.note != null) place.note!,
    ].join(' · ');

/// Puts [name] up for a vote, once; a second tap takes the poll back.
web.HTMLElement _voteChip(Ui ui, Trip trip, String name) {
  bool same(Poll poll) => poll.single && poll.title == name;
  final polled = trip.polls.any(same);
  return chip(polled ? 'U anketi' : 'Glasaj', () {
    polled ? trip.polls.removeWhere(same) : addYesNoPoll(ui, trip, name);
    ui.changed();
  }, on: polled);
}

web.HTMLElement _placeRow(Ui ui, Trip trip, Place place) {
  final link = place.link;
  return el('div', cls: 'row', children: [
    el('div', cls: 'grow', children: [
      el('div', cls: 'label', text: place.name),
      el('div', cls: 'small', text: _placeFacts(place)),
      el('div', attrs: {'style': 'display:flex;gap:8px;margin-top:6px'}, children: [
        chip(place.planned ? 'U planu' : 'Dodaj u plan', () {
          place.planned = !place.planned;
          ui.changed();
        }, on: place.planned),
        _voteChip(ui, trip, place.name),
      ]),
    ]),
    if (link != null) linkIcon(link, 'Otvori ${place.name}'),
    removeButton(place.name, () {
      trip.places.remove(place);
      ui.changed();
    }),
  ]);
}

web.HTMLElement _addPlace(Ui ui, Trip trip) {
  final name = input();
  final rating = numberInput();
  final price = numberInput();
  final note = input();
  final link = input(type: 'url');
  final error = errorLine();
  link.onInput.listen((_) {
    final found = nameFromLink(link.value);
    if (found != null && name.value.trim().isEmpty) name.value = found;
  });

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
    field('Link', link),
    field('Naziv', name),
    el('div', cls: 'fields', children: [
      field('Ocjena', rating, tight: true),
      field('Cijena po osobi (€)', price, tight: true),
    ]),
    field('Bilješka', note),
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
    _voteChip(ui, trip, dish.name),
    removeButton(dish.name, () {
      trip.dishes.remove(dish);
      ui.changed();
    }),
  ]);
}

web.HTMLElement _addDish(Ui ui, Trip trip) {
  final name = input();
  final price = numberInput();
  final servings = numberInput(value: '1');
  final place = input();
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
    el('div', cls: 'row stick-bottom', children: [
      el('div', cls: 'grow', text: 'Procjena za hranu i piće'),
      el('div', cls: 'price', text: euros(plannedCost(trip, CostCategory.food))),
    ]),
  ]);
}
