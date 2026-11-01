import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
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

web.HTMLElement _addPlace(Ui ui, Trip trip, CustomKind? custom) {
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
      customKindId: custom?.id,
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

const Duration _slideTime = Duration(milliseconds: 80);
const String _slide = 'transform 80ms ease-out';

const Duration _glideTime = Duration(milliseconds: 160);

bool get _wantsLessMotion =>
    web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/// Lets [sliding] follow the finger across [page]. Past the swipe length [move]
/// is called at once, with +1 for the next kind, -1 for the one before. Lists of
/// chips scroll by themselves, and an open form would lose what was typed in it,
/// so those are left alone.
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
    final formOpen = web.document.querySelector('details[open], .new-kind') != null;
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
    if (done) {
      move(step);
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

double _centredLeft(web.HTMLElement row, web.HTMLElement chosen) =>
    chosen.offsetLeft - (row.clientWidth - chosen.offsetWidth) / 2;

/// Where the green of the chosen chip is, to start gliding from after a redraw.
typedef _ChipPlace = ({int index, double left, double width, double scroll});

_ChipPlace? _chipPlace() {
  final row = _chipRow, chosen = _chosenChip;
  if (row == null || chosen == null) return null;
  final chips = row.querySelectorAll('.chip');
  var index = 0;
  while (index < chips.length && !identical(chips.item(index), chosen)) {
    index++;
  }
  return (
    index: index,
    left: chosen.offsetLeft.toDouble(),
    width: chosen.offsetWidth.toDouble(),
    scroll: row.scrollLeft.toDouble(),
  );
}

/// Calls [frame] with the progress, from 0 to 1, on every frame for [length],
/// then [end]. A hidden page gets no frames, so a timer makes sure it ends.
void _animate(Duration length, void Function(double progress) frame, void Function() end) {
  final started = web.window.performance.now();
  var finished = false;

  void finish() {
    if (finished) return;
    finished = true;
    frame(1);
    end();
  }

  void tick(double now) {
    if (finished) return;
    final time = (now - started) / length.inMilliseconds;
    if (time >= 1) {
      finish();
    } else {
      frame(1 - pow(1 - max(time, 0), 3).toDouble());
      web.window.requestAnimationFrame(tick.toJS);
    }
  }

  web.window.requestAnimationFrame(tick.toJS);
  Timer(length * 2, finish);
}

/// A redraw replaces the chips, so for a moment a green marker stands in for the
/// chosen chip's own colour. It glides from the old place to the new one while
/// the row scrolls with it and the words change colour, all in one movement.
void _glideToChosenChip(_ChipPlace from) {
  final row = _chipRow, chosen = _chosenChip;
  if (row == null || chosen == null) return;
  final longest = (row.scrollWidth - row.clientWidth).toDouble();
  final centred = _centredLeft(row, chosen).clamp(0.0, max(longest, 0.0));
  if (_wantsLessMotion) {
    row.scrollLeft = centred;
    return;
  }
  final leaving = row.querySelectorAll('.chip').item(from.index) as web.HTMLElement?;
  final toLeft = chosen.offsetLeft.toDouble();
  final toWidth = chosen.offsetWidth.toDouble();
  final marker = el('span', cls: 'chip-marker');
  marker.style
    ..left = '${from.left}px'
    ..width = '${from.width}px'
    ..top = '${chosen.offsetTop}px'
    ..height = '${chosen.offsetHeight}px'
    ..borderRadius = web.window.getComputedStyle(chosen).borderRadius;
  leaving?.classList.add('leaving');
  row
    ..append(marker)
    ..scrollLeft = from.scroll
    ..classList.add('gliding')
    ..classList.add('glide-start');
  row.getBoundingClientRect(); // so that the browser sees the colours they start from
  row.classList.remove('glide-start');
  _animate(_glideTime, (progress) {
    marker.style
      ..left = '${from.left + (toLeft - from.left) * progress}px'
      ..width = '${from.width + (toWidth - from.width) * progress}px';
    row.scrollLeft = from.scroll + (centred - from.scroll) * progress;
  }, () {
    marker.remove();
    leaving?.classList.remove('leaving');
    row.classList.remove('gliding');
  });
}

/// One category of the screen: a fixed kind, or one the group made.
class _Tab {
  const _Tab(this.label, this.searchWord, {this.kind, this.custom});

  final String label;
  final String searchWord;
  final PlaceKind? kind;
  final CustomKind? custom;

  bool holds(Place place) => custom != null
      ? place.customKindId == custom!.id
      : place.customKindId == null && place.kind == kind;
}

/// The field for a new category, under the row of categories.
web.HTMLElement _newKind(Ui ui, void Function(String label) add) {
  final name = input();
  return el('div', cls: 'new-kind', children: [
    field('Nova kategorija', name),
    primaryButton('Dodaj kategoriju', () => add(name.value.trim())),
  ]);
}

web.HTMLElement foodScreen(Ui ui, Trip trip) {
  final tabs = [
    for (final kind in PlaceKind.values) _Tab(kind.label, kind.searchWord, kind: kind),
    for (final custom in trip.customKinds)
      _Tab(custom.label, custom.label, custom: custom),
  ];
  final customAt = tabs.indexWhere(
      (tab) => tab.custom != null && tab.custom!.id == ui.customKindId);
  final index = customAt >= 0
      ? customAt
      : tabs.indexWhere((tab) => tab.kind == ui.placeKind);
  final tab = tabs[index];
  final places = trip.places.where(tab.holds).toList();

  void choose(_Tab item) {
    ui.customKindId = item.custom?.id;
    ui.placeKind = item.kind ?? ui.placeKind;
  }

  void show(_Tab item) {
    if (identical(item, tab)) return;
    final from = _chipPlace();
    choose(item);
    ui.rerender();
    if (from != null) _glideToChosenChip(from);
    _slideIn(tabs.indexOf(item) > index ? 1 : -1);
  }

  void addKind(String label) {
    ui.addingKind = false;
    if (label.isNotEmpty) {
      final same = tabs.where((item) => item.label.toLowerCase() == label.toLowerCase());
      if (same.isNotEmpty) {
        choose(same.first);
      } else {
        final custom = CustomKind(id: ui.store.newId(), label: label);
        trip.customKinds.add(custom);
        ui.customKindId = custom.id;
      }
    }
    ui.changed();
  }

  void removeKind(CustomKind custom) {
    if (!web.window.confirm('Obrisati kategoriju ${custom.label} i mjesta u njoj?')) return;
    trip.places.removeWhere(tab.holds);
    trip.customKinds.remove(custom);
    ui.customKindId = null;
    ui.changed();
  }

  final custom = tab.custom;
  final sliding = el('div', cls: 'slide-page', children: [
    el('div', cls: 'pad gap-top', children: [
      outLink('Traži: ${tab.label} u mjestu ${trip.city}', mapsSearchFor(tab.searchWord, trip)),
    ]),
    if (places.isEmpty)
      el('p', cls: 'soft pad gap-top', text: 'Još nema spremljenih mjesta.'),
    for (final place in places) _placeRow(ui, trip, place),
    _addPlace(ui, trip, custom),
    if (custom != null)
      el('div', cls: 'pad gap-top', children: [
        button(
          cls: 'text-button',
          text: 'Obriši kategoriju',
          onTap: () => removeKind(custom),
        ),
      ]),
    sectionTitle('Jela koja želimo probati'),
    if (trip.dishes.isEmpty)
      el('p', cls: 'soft pad', text: 'Dodajte jela s cijenom s jelovnika.'),
    for (final dish in trip.dishes) _dishRow(ui, trip, dish),
    _addDish(ui, trip),
  ]);
  final page = el('div', cls: 'swipe-area', children: [
    topBar('Hrana i piće'),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
      for (final item in tabs)
        chip(item.label, () => show(item), on: identical(item, tab)),
      button(
        cls: ui.addingKind ? 'chip on-outline' : 'chip',
        ariaLabel: 'Nova kategorija',
        onTap: () {
          ui.addingKind = !ui.addingKind;
          ui.rerender();
          (web.document.querySelector('.new-kind input') as web.HTMLElement?)?.focus();
        },
        children: [icon(ui.addingKind ? 'minus' : 'plus', size: 18)],
      ),
    ]),
    if (ui.addingKind) _newKind(ui, addKind),
    el('div', cls: 'slide-clip', children: [sliding]),
    el('div', cls: 'row stick-bottom', children: [
      el('div', cls: 'grow', text: 'Procjena za hranu i piće'),
      el('div', cls: 'price', text: euros(plannedCost(trip, CostCategory.food))),
    ]),
  ]);
  bool canMove(int step) {
    final next = index + step;
    return next >= 0 && next < tabs.length;
  }

  _followSwipes(page, sliding, canMove, (step) => show(tabs[index + step]));
  // A redraw starts the row of categories from the left again.
  scheduleMicrotask(() {
    final row = _chipRow, chosen = _chosenChip;
    if (row == null || chosen == null || row.classList.contains('gliding')) return;
    row.scrollLeft = ui.addingKind ? row.scrollWidth : _centredLeft(row, chosen);
  });
  return page;
}
