import 'dart:async';
import 'dart:math';

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

/// A swipe must be this long, in pixels, to change the kind.
const double _swipeLength = 60;

/// After this many pixels it is clear whether the finger goes sideways or down.
const double _lockDistance = 10;

/// A swipe from this close to the left edge is an iPhone's way back.
const double _backGestureEdge = 30;

/// How far the page follows the finger when there is no next kind.
const double _resistance = 0.25;

const Duration _slideTime = Duration(milliseconds: 90);
const String _slide = 'transform 90ms ease-out';

const Duration _glideTime = Duration(milliseconds: 150);
const String _glide = 'left 150ms ease, width 150ms ease';

bool get _wantsLessMotion =>
    web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/// Lets [sliding] follow the finger across [page]. Past the swipe length it
/// slides away and [move] is called with +1 for the next kind, -1 for the one
/// before. Lists of chips scroll by themselves, and an open form would lose what
/// was typed in it, so those are left alone.
void _followSwipes(
  web.HTMLElement page,
  web.HTMLElement sliding,
  bool Function(int step) canMove,
  void Function(int step) move,
) {
  double? startX;
  double startY = 0;
  var sideways = false;

  page.onTouchStart.listen((event) {
    final touch = event.changedTouches.item(0)!;
    final inChips = (event.target as web.Element).closest('.chips') != null;
    final formOpen = web.document.querySelector('details[open]') != null;
    final usable = event.touches.length == 1 &&
        touch.clientX >= _backGestureEdge &&
        !inChips &&
        !formOpen;
    startX = usable ? touch.clientX.toDouble() : null;
    startY = touch.clientY.toDouble();
    sideways = false;
  });
  page.onTouchMove.listen((event) {
    final from = startX;
    if (from == null) return;
    final touch = event.changedTouches.item(0)!;
    final across = touch.clientX - from;
    final down = touch.clientY - startY;
    if (!sideways) {
      if (max(across.abs(), down.abs()) < _lockDistance) return;
      if (across.abs() < down.abs() * 2) {
        startX = null;
        return;
      }
      sideways = true;
      sliding.style.transition = 'none';
    }
    final free = canMove(across < 0 ? 1 : -1);
    sliding.style.transform = 'translateX(${free ? across : across * _resistance}px)';
  });
  page.onTouchEnd.listen((event) {
    final from = startX;
    startX = null;
    if (from == null || !sideways) return;
    final across = event.changedTouches.item(0)!.clientX - from;
    final step = across < 0 ? 1 : -1;
    final done = across.abs() >= _swipeLength && canMove(step);
    if (done && _wantsLessMotion) {
      move(step);
    } else if (done) {
      sliding.style
        ..transition = _slide
        ..transform = 'translateX(${-step * 100}%)';
      Timer(_slideTime, () => move(step));
    } else {
      sliding.style
        ..transition = _slide
        ..transform = '';
    }
  });
  page.onTouchCancel.listen((_) {
    startX = null;
    sliding.style
      ..transition = _slide
      ..transform = '';
  });
}

/// Brings the freshly drawn list in from the side the swipe came from.
void _slideIn(int step) {
  final fresh = web.document.querySelector('.slide-page') as web.HTMLElement?;
  if (fresh == null || _wantsLessMotion) return;
  fresh.style
    ..transition = 'none'
    ..transform = 'translateX(${step * 100}%)';
  fresh.getBoundingClientRect(); // so that the browser sees where it starts
  fresh.style
    ..transition = _slide
    ..transform = '';
  // Should the animation not run, the list must still end up in its place.
  Timer(_slideTime * 2, () => fresh.style.transition = 'none');
}

web.HTMLElement? get _chipRow => web.document.querySelector('.chips') as web.HTMLElement?;

web.HTMLElement? get _chosenChip => _chipRow?.querySelector('.chip.on') as web.HTMLElement?;

/// Where the green of the chosen chip is, to start gliding from after a redraw.
({double left, double width, double scroll})? _chipPlace() {
  final row = _chipRow, chosen = _chosenChip;
  if (row == null || chosen == null) return null;
  return (
    left: chosen.offsetLeft.toDouble(),
    width: chosen.offsetWidth.toDouble(),
    scroll: row.scrollLeft.toDouble(),
  );
}

/// A redraw replaces the chips, so for a moment a green marker stands in for the
/// chosen chip's own colour and glides from the old place to the new one, while
/// the row scrolls to keep the chosen chip in sight.
void _glideToChosenChip(({double left, double width, double scroll}) from) {
  final row = _chipRow, chosen = _chosenChip;
  if (row == null || chosen == null) return;
  final centred = chosen.offsetLeft - (row.clientWidth - chosen.offsetWidth) / 2;
  if (_wantsLessMotion) {
    row.scrollLeft = centred;
    return;
  }
  row.scrollLeft = from.scroll;
  row.scrollTo(web.ScrollToOptions(left: centred, behavior: 'smooth'));
  final marker = el('span', cls: 'chip-marker');
  marker.style
    ..left = '${from.left}px'
    ..width = '${from.width}px'
    ..top = '${chosen.offsetTop}px'
    ..height = '${chosen.offsetHeight}px'
    ..borderRadius = web.window.getComputedStyle(chosen).borderRadius;
  row
    ..append(marker)
    ..classList.add('gliding');
  marker.getBoundingClientRect(); // so that the browser sees where it starts
  marker.style
    ..transition = _glide
    ..left = '${chosen.offsetLeft}px'
    ..width = '${chosen.offsetWidth}px';
  Timer(_glideTime, () {
    marker.remove();
    row.classList.remove('gliding');
    row.scrollLeft = centred;
  });
}

web.HTMLElement foodScreen(Ui ui, Trip trip) {
  final kind = ui.placeKind;
  final places = trip.places.where((place) => place.kind == kind).toList();

  void show(PlaceKind item) {
    if (item == kind) return;
    final from = _chipPlace();
    ui.placeKind = item;
    ui.rerender();
    if (from != null) _glideToChosenChip(from);
    _slideIn(item.index > kind.index ? 1 : -1);
  }

  final sliding = el('div', cls: 'slide-page', children: [
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
  ]);
  final page = el('div', cls: 'swipe-area', children: [
    topBar('Hrana i piće'),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
      for (final item in PlaceKind.values)
        chip(item.label, () => show(item), on: item == kind),
    ]),
    el('div', cls: 'slide-clip', children: [sliding]),
    el('div', cls: 'row stick-bottom', children: [
      el('div', cls: 'grow', text: 'Procjena za hranu i piće'),
      el('div', cls: 'price', text: euros(plannedCost(trip, CostCategory.food))),
    ]),
  ]);
  bool canMove(int step) {
    final next = kind.index + step;
    return next >= 0 && next < PlaceKind.values.length;
  }

  _followSwipes(page, sliding, canMove, (step) {
    show(PlaceKind.values[kind.index + step]);
  });
  return page;
}
