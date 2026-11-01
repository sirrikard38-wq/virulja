import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'polls_section.dart';
import 'swipes.dart';
import 'widgets.dart';

String _priceOf(Place place) => switch ((place.priceLow, place.priceHigh)) {
      (final low?, final high?) => eurosRange(low, high),
      _ => euros(place.pricePerPerson!),
    };

String _placeFacts(Place place) => [
      if (place.rating != null) place.rating!.toString().replaceAll('.', ','),
      if (place.pricePerPerson != null) tr('{0} po osobi', [_priceOf(place)]),
      if (place.note != null) place.note!,
    ].join(' · ');

/// Puts [name] up for a vote, once; a second tap takes the poll back.
web.HTMLElement _voteChip(Ui ui, Trip trip, String name) {
  bool same(Poll poll) => poll.single && poll.title == name;
  final polled = trip.polls.any(same);
  return chip(polled ? tr('U anketi') : tr('Glasaj'), () {
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
        chip(place.planned ? tr('U planu') : tr('Dodaj u plan'), () {
          place.planned = !place.planned;
          ui.changed();
        }, on: place.planned),
        _voteChip(ui, trip, place.name),
      ]),
    ]),
    if (link != null) linkIcon(link, tr('Otvori {0}', [place.name])),
    removeButton(place.name, () {
      trip.places.remove(place);
      ui.changed();
    }),
  ]);
}

web.HTMLElement _addPlace(Ui ui, Trip trip, CustomKind? custom) {
  final name = input();
  final rating = numberInput();
  final price = input(); // a phone's number keys have no dash for a range
  final note = input();
  final link = input(type: 'url');
  final error = errorLine();
  link.onInput.listen((_) {
    final found = nameFromLink(link.value);
    if (found != null && name.value.trim().isEmpty) name.value = found;
  });

  void add() {
    if (name.value.trim().isEmpty) {
      error.textContent = tr('Upiši naziv mjesta.');
      return;
    }
    final cost = parsePriceRange(price.value);
    if (cost == null && price.value.trim().isNotEmpty) {
      error.textContent = tr('Upiši cijenu ili raspon, npr. 10-30.');
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
      pricePerPerson: cost?.middle,
      priceLow: cost?.low,
      priceHigh: cost?.high,
      note: remark.isEmpty ? null : remark,
      link: address.isEmpty ? null : address,
    ));
    ui.changed();
  }

  return adder(tr('Dodaj mjesto'), [
    field(tr('Link'), link),
    field(tr('Naziv'), name),
    el('div', cls: 'fields', children: [
      field(tr('Ocjena'), rating, tight: true),
      field(tr('Cijena po osobi (€)'), price, tight: true),
    ]),
    field(tr('Bilješka'), note),
    error,
    primaryButton(tr('Dodaj mjesto'), add),
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
      error.textContent = tr('Upiši jelo i cijenu.');
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

  return adder(tr('Dodaj jelo'), [
    field(tr('Jelo'), name),
    el('div', cls: 'fields', children: [
      field(tr('Cijena (€)'), price, tight: true),
      field(tr('Porcija'), servings, tight: true),
    ]),
    field(tr('Gdje'), place),
    error,
    primaryButton(tr('Dodaj jelo'), add),
  ]);
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

/// A redraw replaces the chips, so for a moment a green marker stands in for the
/// chosen chip's own colour. It glides from the old place to the new one while
/// the row scrolls with it and the words change colour, all in one movement.
void _glideToChosenChip(_ChipPlace from) {
  final row = _chipRow, chosen = _chosenChip;
  if (row == null || chosen == null) return;
  final longest = (row.scrollWidth - row.clientWidth).toDouble();
  final centred = _centredLeft(row, chosen).clamp(0.0, max(longest, 0.0));
  if (wantsLessMotion) {
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
  animate(glideTime, (progress) {
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

/// What this person's order of the categories calls the dishes.
const String _dishesKey = 'dishes';

/// One category of the screen: a fixed kind, one the group made, or the dishes,
/// which are neither.
class _Tab {
  const _Tab(this.label, this.searchWord, {this.kind, this.custom});

  final String label;
  final String searchWord;
  final PlaceKind? kind;
  final CustomKind? custom;

  bool get isDishes => kind == null && custom == null;

  /// What this person's order of the categories calls it.
  String get key => custom?.id ?? kind?.name ?? _dishesKey;

  bool holds(Place place) => custom != null
      ? place.customKindId == custom!.id
      : place.customKindId == null && place.kind == kind;
}

/// [tabs] in the order this person chose. Categories made since come last; the
/// dishes come first until this person moves them.
List<_Tab> _inOrder(List<_Tab> tabs, List<String> order) {
  int place(_Tab tab) {
    final at = order.indexOf(tab.key);
    if (at >= 0) return at;
    return tab.isDishes ? -1 : order.length + tabs.indexOf(tab);
  }

  return tabs.toList()..sort((a, b) => place(a).compareTo(place(b)));
}

/// How long a finger must rest on a category to pick it up, and how far it may
/// wander meanwhile before it counts as scrolling the row.
const Duration _holdTime = Duration(milliseconds: 380);
const double _holdWander = 8;

/// Where the row of categories stays after a drop, instead of going to the chosen
/// category.
double? _rowKept;

/// A long press picks a category up, the others wobble as icons do on a phone,
/// and it goes where the finger drops it. The green goes with it, as it is the
/// one being worked on. [save] gets the new order and the one that moved.
void _reorderOnHold(
  web.HTMLElement row,
  void Function(List<String> keys, String moved) save,
) {
  Timer? hold;
  web.HTMLElement? held;
  var lifted = false;
  double startX = 0, startY = 0, startLeft = 0, startScroll = 0;
  final active = web.AddEventListenerOptions(passive: false);

  void follow(web.HTMLElement chip, double x) {
    final moved = x - startX + row.scrollLeft - startScroll;
    chip.style.transform = 'translateX(${moved - (chip.offsetLeft - startLeft)}px)';
  }

  void passBy(web.HTMLElement other, void Function() swap) {
    final before = other.offsetLeft;
    swap();
    other.style
      ..transition = 'none'
      ..transform = 'translateX(${before - other.offsetLeft}px)';
    other.getBoundingClientRect(); // so that the browser sees where it starts
    other.style
      ..transition = 'transform 120ms ease'
      ..transform = '';
  }

  double middle(web.Element element) {
    final box = element.getBoundingClientRect();
    return box.left + box.width / 2;
  }

  void finish(web.Event event) {
    hold?.cancel();
    final chip = held;
    held = null;
    if (!lifted || chip == null) return;
    lifted = false;
    event.preventDefault();
    chip.classList.remove('lifted');
    chip.style.transform = '';
    row.classList.remove('arranging');
    final chips = row.querySelectorAll('[data-tab]');
    save([
      for (var i = 0; i < chips.length; i++)
        (chips.item(i) as web.Element).getAttribute('data-tab')!,
    ], chip.getAttribute('data-tab')!);
  }

  row.addEventListener('touchstart', ((web.TouchEvent event) {
    final chip = (event.target as web.Element).closest('[data-tab]') as web.HTMLElement?;
    if (chip == null || event.touches.length != 1) return;
    final touch = event.touches.item(0)!;
    startX = touch.clientX.toDouble();
    startY = touch.clientY.toDouble();
    startLeft = chip.offsetLeft.toDouble();
    startScroll = row.scrollLeft.toDouble();
    held = chip;
    hold?.cancel();
    hold = Timer(_holdTime, () {
      lifted = true;
      row.querySelector('.chip.on')?.classList.remove('on');
      chip.classList.add('on');
      chip.classList.add('lifted');
      row.classList.add('arranging');
      try {
        web.window.navigator.vibrate(15.toJS);
      } on Object {
        // Not every phone can.
      }
    });
  }).toJS);
  row.addEventListener('touchmove', ((web.TouchEvent event) {
    final chip = held;
    if (chip == null) return;
    final touch = event.touches.item(0)!;
    final x = touch.clientX.toDouble();
    if (!lifted) {
      if ((x - startX).abs() > _holdWander ||
          (touch.clientY - startY).abs() > _holdWander) {
        hold?.cancel();
        held = null;
      }
      return;
    }
    event.preventDefault();
    if (x < 40) row.scrollLeft -= 6;
    if (x > web.window.innerWidth - 40) row.scrollLeft += 6;
    follow(chip, x);
    final next = chip.nextElementSibling;
    final previous = chip.previousElementSibling;
    if (next != null && next.hasAttribute('data-tab') && middle(chip) > middle(next)) {
      passBy(next as web.HTMLElement, () => row.insertBefore(next, chip));
      follow(chip, x);
    } else if (previous != null &&
        previous.hasAttribute('data-tab') &&
        middle(chip) < middle(previous)) {
      passBy(previous as web.HTMLElement, () => row.insertBefore(chip, previous));
      follow(chip, x);
    }
  }).toJS, active);
  row.addEventListener('touchend', finish.toJS, active);
  row.addEventListener('touchcancel', finish.toJS, active);
  row.addEventListener('contextmenu', ((web.Event event) {
    if (held != null) event.preventDefault();
  }).toJS);
}

/// The field for a new category, under the row of categories.
web.HTMLElement _newKind(Ui ui, void Function(String label) add) {
  final name = input();
  return el('div', cls: 'new-kind', children: [
    field(tr('Nova kategorija'), name),
    primaryButton(tr('Dodaj kategoriju'), () => add(name.value.trim())),
  ]);
}

web.HTMLElement foodScreen(Ui ui, Trip trip) {
  final tabs = _inOrder([
    _Tab(tr('Hrana i piće'), ''),
    for (final kind in PlaceKind.values) _Tab(kind.label, kind.searchWord, kind: kind),
    for (final custom in trip.customKinds)
      _Tab(custom.label, custom.label, custom: custom),
  ], ui.data.kindOrder[trip.id] ?? const []);
  final customAt = tabs.indexWhere((tab) => tab.key == ui.customKindId);
  final index = customAt >= 0
      ? customAt
      : tabs.indexWhere((tab) => tab.kind == ui.placeKind);
  final tab = tabs[index];
  final places = trip.places.where(tab.holds).toList();

  void choose(_Tab item) {
    ui.customKindId = item.kind == null ? item.key : null;
    ui.placeKind = item.kind ?? ui.placeKind;
  }

  void show(_Tab item) {
    if (identical(item, tab)) return;
    final from = _chipPlace();
    choose(item);
    ui.rerender();
    if (from != null) _glideToChosenChip(from);
    slideIn(tabs.indexOf(item) > index ? 1 : -1);
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
    if (!web.window.confirm(tr('Obrisati kategoriju {0} i mjesta u njoj?', [custom.label]))) return;
    trip.places.removeWhere(tab.holds);
    trip.customKinds.remove(custom);
    ui.customKindId = null;
    ui.changed();
  }

  final custom = tab.custom;
  final sliding = el('div', cls: 'slide-page', children: [
    if (tab.isDishes) ...[
      sectionTitle(tr('Jela koja želimo probati')),
      if (trip.dishes.isEmpty)
        el('p', cls: 'soft pad', text: tr('Dodajte jela s cijenom s jelovnika.')),
      for (final dish in trip.dishes) _dishRow(ui, trip, dish),
      _addDish(ui, trip),
    ] else ...[
      el('div', cls: 'pad gap-top', children: [
        outLink(tr('Traži: {0} u mjestu {1}', [tab.label, trip.city]), mapsSearchFor(tab.searchWord, trip)),
      ]),
      if (places.isEmpty)
        el('p', cls: 'soft pad gap-top', text: tr('Još nema spremljenih mjesta.')),
      for (final place in places) _placeRow(ui, trip, place),
      _addPlace(ui, trip, custom),
      if (custom != null)
        el('div', cls: 'pad gap-top', children: [
          button(
            cls: 'text-button',
            text: tr('Obriši kategoriju'),
            onTap: () => removeKind(custom),
          ),
        ]),
    ],
  ]);
  final chipRow = el('div', cls: 'chips', attrs: {'style': 'padding-top:0'}, children: [
      for (final item in tabs)
        chip(item.label, () => show(item), on: identical(item, tab))
          ..setAttribute('data-tab', item.key),
      button(
        cls: ui.addingKind ? 'chip on-outline' : 'chip',
        ariaLabel: tr('Nova kategorija'),
        onTap: () {
          ui.addingKind = !ui.addingKind;
          ui.rerender();
          (web.document.querySelector('.new-kind input') as web.HTMLElement?)?.focus();
        },
        children: [icon(ui.addingKind ? 'minus' : 'plus', size: 18)],
      ),
  ]);
  _reorderOnHold(chipRow, (keys, moved) {
    ui.data.kindOrder[trip.id] = keys;
    ui.store.save();
    _rowKept = chipRow.scrollLeft.toDouble();
    choose(tabs.firstWhere((item) => item.key == moved));
    ui.rerender();
  });
  final page = el('div', cls: 'swipe-area', children: [
    topBar(tr('Hrana i piće')),
    chipRow,
    if (ui.addingKind) _newKind(ui, addKind),
    el('div', cls: 'slide-clip', children: [sliding]),
    el('div', cls: 'row stick-bottom', children: [
      el('div', cls: 'grow', text: tr('Procjena za hranu i piće')),
      el('div', cls: 'price', text: euros(plannedCost(trip, CostCategory.food))),
    ]),
  ]);
  bool canMove(int step) {
    final next = index + step;
    return next >= 0 && next < tabs.length;
  }

  followSwipes(page, sliding, canMove, (step) => show(tabs[index + step]));
  // A redraw starts the row of categories from the left again.
  scheduleMicrotask(() {
    final row = _chipRow, chosen = _chosenChip;
    if (row == null || chosen == null || row.classList.contains('gliding')) return;
    row.scrollLeft =
        _rowKept ?? (ui.addingKind ? row.scrollWidth : _centredLeft(row, chosen));
    _rowKept = null;
  });
  return page;
}
