import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'plan_cost.dart';
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

/// Its polls, found by name, taken out of Ankete; gives what puts them back.
void Function() _takePolls(Trip trip, String name) {
  final taken = [
    for (var i = 0; i < trip.polls.length; i++)
      if (trip.polls[i].single && trip.polls[i].title == name) (at: i, poll: trip.polls[i]),
  ];
  trip.polls.removeWhere((poll) => poll.single && poll.title == name);
  return () {
    for (final item in taken) {
      trip.polls.insert(item.at.clamp(0, trip.polls.length), item.poll);
    }
  };
}

/// A new name for a place or dish, which its polls take along.
void _rename(Ui ui, Trip trip, String old, String name, void Function(String) set) {
  for (final poll in trip.polls) {
    if (poll.single && poll.title == old) poll.title = name;
  }
  set(name);
  ui.changed();
}

/// Puts [name] up for a vote, once; a second tap takes the poll back.
web.HTMLElement _voteChip(Ui ui, Trip trip, String name) {
  bool same(Poll poll) => poll.single && poll.title == name;
  final polled = trip.polls.any(same);
  return chip(tr('Anketa'), () {
    polled ? trip.polls.removeWhere(same) : addYesNoPoll(ui, trip, name);
    ui.changed();
  }, on: polled);
}

web.HTMLElement _placeRow(Ui ui, Trip trip, Place place) {
  final link = place.link;
  final inAttack = placeInAttack(trip, place);
  return el('div', cls: 'row', children: [
    el('div', cls: 'grow', children: [
      editableName(place.name, tr('Naziv'),
          (name) => _rename(ui, trip, place.name, name, (name) => place.name = name)),
      el('div', cls: 'small', text: _placeFacts(place)),
      el('div', attrs: {'style': 'display:flex;gap:8px;margin-top:6px'}, children: [
        _voteChip(ui, trip, place.name),
        chip(tr('Plan napada'), () {
          setPlaceInAttack(trip, place, !inAttack, ui.meIn(trip));
          ui.changed();
        }, on: inAttack),
      ]),
    ]),
    if (link != null) linkIcon(link, tr('Otvori {0}', [place.name])),
    removeWithUndo(ui, trip.places, place, place.name, also: () => _takePolls(trip, place.name)),
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
      field(inMoney(tr('Cijena po osobi (€)')), price, tight: true),
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
      editableName(dish.name, tr('Naziv'),
          (name) => _rename(ui, trip, dish.name, name, (name) => dish.name = name)),
      el('div', cls: 'small', text: [
        if (place != null) place,
        '${dish.servings} × ${euros(dish.price)}',
      ].join(' · ')),
    ]),
    el('div', cls: 'price', text: euros(dish.price * dish.servings)),
    _voteChip(ui, trip, dish.name),
    removeWithUndo(ui, trip.dishes, dish, dish.name, also: () => _takePolls(trip, dish.name)),
  ]);
}

web.HTMLElement _addDish(Ui ui, Trip trip) {
  final name = input();
  final price = amountInput();
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
      field(inMoney(tr('Cijena (€)')), price, tight: true),
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
const String _dishesKey = dishesKind;

/// One category of the screen: a fixed kind, one the group made, or the dishes,
/// which are neither.
class _Tab {
  const _Tab(this.label, this.searchWord, {this.kind, this.custom});

  final String label;
  final String searchWord;
  final PlaceKind? kind;
  final CustomKind? custom;

  bool get isDishes => kind == null && custom == null;

  /// What stands over the sum of this category.
  String get estimateTitle {
    if (custom != null) return tr('Procjena za {0}', [custom!.label.toLowerCase()]);
    return kind?.estimateTitle ?? tr('Procjena za hranu');
  }

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

/// A little puff of sparks where something was thrown away.
void _puff(web.HTMLElement over) {
  final box = over.getBoundingClientRect();
  final burst = el('div', cls: 'puff', attrs: {
    'style': 'left:${box.left + box.width / 2}px;top:${box.top + box.height / 2}px',
  }, children: [
    el('span', cls: 'puff-cloud'),
    for (var i = 0; i < 14; i++)
      el('span', cls: 'spark', attrs: {
        'style': '--dx:${(cos(i * pi / 7) * (34 + 10 * (i % 3))).toStringAsFixed(1)}px;'
            '--dy:${(sin(i * pi / 7) * (34 + 10 * (i % 3))).toStringAsFixed(1)}px;'
            '--hue:${(i * 47) % 360}',
      }),
  ]);
  web.document.body!.append(burst);
  Timer(const Duration(milliseconds: 750), () => burst.remove());
}

/// A long press picks a category up, the others wobble as icons do on a phone,
/// and it goes where the finger drops it. The green goes with it, as it is the
/// one being worked on. [save] gets the new order and the one that moved. While
/// it is up, a bin stands at the top in the middle: let go over it and [trash]
/// gets the category.
void _reorderOnHold(
  web.HTMLElement row,
  void Function(List<String> keys, String moved) save,
  void Function(String key) trash,
) {
  Timer? hold;
  web.HTMLElement? held;
  var lifted = false;
  web.HTMLElement? bin;
  var overBin = false;
  double lastX = 0, lastY = 0;
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
    final thrown = overBin && event.type == 'touchend';
    final where = bin;
    bin = null;
    overBin = false;
    if (thrown && where != null) {
      _puff(where);
      chip.style.visibility = 'hidden';
      Timer(const Duration(milliseconds: 160), () => where.remove());
      row.classList.remove('arranging');
      trash(chip.getAttribute('data-tab')!);
      return;
    }
    where?.remove();
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
      bin = el('div', cls: 'kind-bin', children: [icon('trash', size: 26)]);
      web.document.body!.append(bin!);
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
    lastX = x;
    lastY = touch.clientY.toDouble();
    final box = bin?.getBoundingClientRect();
    overBin = box != null &&
        lastX > box.left - 16 && lastX < box.right + 16 &&
        lastY > box.top - 16 && lastY < box.bottom + 16;
    bin?.classList.toggle('over', overBin);
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
  final hidden = ui.data.hiddenKinds[trip.id] ?? const <String>{};
  final every = [
    _Tab(tr('Hrana'), ''),
    for (final kind in PlaceKind.values) _Tab(kind.label, kind.searchWord, kind: kind),
    for (final custom in trip.customKinds)
      _Tab(custom.label, custom.label, custom: custom),
  ];
  final tabs = _inOrder([
    for (final item in every)
      if (!hidden.contains(item.key)) item,
  ], ui.data.kindOrder[trip.id] ?? const []);
  final customAt = tabs.indexWhere((tab) => tab.key == ui.customKindId);
  final shownAt = customAt >= 0
      ? customAt
      : tabs.indexWhere((tab) => tab.kind == ui.placeKind);
  final index = shownAt < 0 ? 0 : shownAt;
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
      final same = every.where((item) => item.label.toLowerCase() == label.toLowerCase());
      if (same.isNotEmpty) {
        // One thrown away earlier comes back.
        ui.data.hiddenKinds[trip.id]?.remove(same.first.key);
        choose(same.first);
      } else {
        final custom = CustomKind(id: ui.store.newId(), label: label);
        trip.customKinds.add(custom);
        ui.customKindId = custom.id;
      }
    }
    ui.changed();
  }

  /// Throws a category away with a moment to change your mind: one the group
  /// made goes with its places, one of the app's own is hidden on this phone.
  void throwAway(String key) {
    final item = every.firstWhere((each) => each.key == key);
    if (tabs.length <= 1) {
      ui.toast(tr('Jedna kategorija mora ostati.'));
      ui.rerender();
      return;
    }
    final custom = item.custom;
    final open = identical(item, tab);
    void Function() restore;
    if (custom != null) {
      final at = trip.customKinds.indexOf(custom);
      final places = [for (final place in trip.places) if (item.holds(place)) place];
      trip.places.removeWhere(item.holds);
      trip.customKinds.remove(custom);
      restore = () {
        trip.customKinds.insert(at.clamp(0, trip.customKinds.length), custom);
        trip.places.addAll(places);
      };
    } else {
      ui.data.hiddenKinds.putIfAbsent(trip.id, () => {}).add(key);
      restore = () => ui.data.hiddenKinds[trip.id]?.remove(key);
    }
    if (open) choose(tabs.firstWhere((each) => !identical(each, item)));
    ui.changed();
    ui.offerUndo(tr('Uklonjeno: {0}', [item.label]), () {
      restore();
      ui.changed();
    });
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
  }, (key) {
    _rowKept = chipRow.scrollLeft.toDouble();
    throwAway(key);
  });
  final page = el('div', cls: 'swipe-area', children: [
    topBar(tr('Hrana i piće')),
    chipRow,
    if (ui.addingKind) _newKind(ui, addKind),
    el('div', cls: 'slide-clip', children: [sliding]),
    // The estimate and, under it, what the group plans for this category.
    el('div', cls: 'stick-bottom', children: [
      el('div', cls: 'row', attrs: {'style': 'padding:0'}, children: [
        el('div', cls: 'grow', text: tab.estimateTitle),
        el('div', cls: 'price',
            text: euros(tab.isDishes ? dishesCost(trip) : plannedPlacesCost(trip, places))),
      ]),
      if (alsoIn(tab.isDishes ? dishesCost(trip) : plannedPlacesCost(trip, places)) case final also
          when also.isNotEmpty)
        el('div', cls: 'small also', attrs: {'style': 'text-align:right'}, text: also),
      planCost(ui, trip, foodBudgetKey(tab.key)),
    ]),
  ]);
  // Past the last category a swipe opens the new one's field, as the + does,
  // without the keyboard; a swipe back closes it again.
  bool canMove(int step) {
    if (ui.addingKind) return step < 0;
    final next = index + step;
    return next >= 0 && next <= tabs.length;
  }

  followSwipes(page, sliding, canMove, (step) {
    if (ui.addingKind || index + step == tabs.length) {
      ui.addingKind = !ui.addingKind;
      ui.rerender();
      return;
    }
    show(tabs[index + step]);
  });
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
