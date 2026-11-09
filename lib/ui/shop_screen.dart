import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'cost_sheet.dart';
import 'dom.dart';
import 'icons.dart';
import 'list_drag.dart';
import 'plan_cost.dart';
import 'widgets.dart';

/// Asks what [list] cost, who paid and whom it is for, and writes it in
/// Troškovi under Dućan. Troškovi can change it later. The list goes down among
/// the bought ones; Poništi takes it all back, and the list is where it was.
void _buy(Ui ui, Trip trip, ShopList list) => costSheet(
      ui,
      trip,
      title: list.name,
      action: tr('Kupljeno'),
      category: CostCategory.shop,
      done: (cost, _) {
        list
          ..expenseId = cost.id
          ..boughtAt = DateTime.now().millisecondsSinceEpoch;
        // Folded, on top of the bought ones; Poništi opens it again.
        final wasOpen = ui.shopOpen.remove(list.id);
        scheduleMicrotask(() => ui.offerUndo(tr('Kupljeno: {0}', [list.name]), () {
              trip.expenses.removeWhere((each) => each.id == cost.id);
              list
                ..expenseId = null
                ..boughtAt = null;
              if (wasOpen) ui.shopOpen.add(list.id);
              ui.changed();
            }));
      },
    );

/// Takes the purchase of [list] back, with its cost in Troškovi.
void _unbuy(Ui ui, Trip trip, ShopList list) {
  final stood = _shown(ui, trip).bought.indexOf(list);
  ui.shopKept = (trip: trip.id, list: list.id, at: stood);
  final at = trip.expenses.indexWhere((cost) => cost.id == list.expenseId);
  final cost = at < 0 ? null : trip.expenses.removeAt(at);
  final id = list.expenseId;
  final when = list.boughtAt;
  list
    ..expenseId = null
    ..boughtAt = null;
  ui.changed();
  ui.offerUndo(tr('Više nije kupljeno'), () {
    list
      ..expenseId = id
      ..boughtAt = when;
    if (cost != null) trip.expenses.insert(at.clamp(0, trip.expenses.length), cost);
    ui.changed();
  });
}

/// The lists as they show: those to buy, in the group's order, and the bought
/// ones, the last bought first, under Nova lista. One whose Kupljeno was just
/// taken back stays where it stood among the bought until Dućan is left
/// (`Ui.shopKept`).
({List<ShopList> toBuy, List<ShopList> bought}) _shown(Ui ui, Trip trip) {
  final lists = listsInOrder(trip);
  bool bought(ShopList list) => trip.expenses.any((cost) => cost.id == list.expenseId);
  final toBuy = [for (final list in lists) if (!bought(list)) list];
  final done = [for (final list in lists) if (bought(list)) list];
  final kept = ui.shopKept;
  if (kept != null && kept.trip == trip.id) {
    final at = toBuy.indexWhere((list) => list.id == kept.list);
    if (at >= 0) done.insert(kept.at.clamp(0, done.length), toBuy.removeAt(at));
  }
  return (toBuy: toBuy, bought: done);
}

/// What was typed in the empty field of a list being changed, kept across a
/// redraw that was not meant to take it in (an x on a thing).
final Map<String, String> _typedNext = {};

/// A list being made or changed, its brush on: the name under a grey "Naziv
/// liste", each thing in its own box with an x, and at the bottom an empty box,
/// "Dodaj u listu", where the keyboard's tick puts what was typed in and opens
/// the next one. The brush takes it all in; the x in the corner throws the
/// list away, with the usual undo. A [draft] is a new list, not yet in [trip].
web.HTMLElement _editCard(Ui ui, Trip trip, ShopList list, {required bool draft}) {
  final me = ui.meIn(trip);
  final cost = trip.expenses.where((each) => each.id == list.expenseId).firstOrNull;
  web.HTMLInputElement box(String key, String value, String placeholder) =>
      input(value: value, placeholder: placeholder)
        ..setAttribute('data-box', key)
        ..setAttribute('enterkeyhint', 'done');
  final name = box('name', list.name, tr('Naziv liste'))..classList.add('shop-name-box');
  final boxes = {for (final item in list.items) item: box(item.id, item.text, '')};
  final next = box('next', _typedNext.remove(list.id) ?? '', tr('Dodaj u listu'));

  /// Writes the name and the things as they are typed into the list; an empty
  /// box keeps what it had.
  void take() {
    final title = name.value.trim();
    if (title.isNotEmpty) {
      list.name = title;
      cost?.title = title;
    }
    for (final MapEntry(key: item, value: typed) in boxes.entries) {
      if (typed.value.trim().isNotEmpty) item.text = typed.value.trim();
    }
  }

  void redraw() => draft ? ui.rerender() : ui.changed();

  void focus(String key) => (web.document
          .querySelector('[data-list="${list.id}"] [data-box="$key"]') as web.HTMLElement?)
      ?.focus();

  /// The box the cursor is in, when it is one of this list's.
  String? focused() {
    final now = web.document.activeElement;
    if (now == null || now.closest('[data-list="${list.id}"]') == null) return null;
    return now.getAttribute('data-box');
  }

  void addNext() {
    take();
    final text = next.value.trim();
    if (text.isNotEmpty) {
      list.items.add(ShopItem(id: ui.store.newId(), text: text, addedBy: me));
    }
    next.value = '';
    redraw();
    focus('next'); // ready for the next one
  }

  void done() {
    take();
    final text = next.value.trim();
    if (text.isNotEmpty) list.items.add(ShopItem(id: ui.store.newId(), text: text, addedBy: me));
    if (draft) {
      if (list.name.trim().isEmpty) list.name = tr('Dućan');
      trip.shopLists.add(list);
      ui.shopDraft = null;
    }
    ui.shopEditing = null;
    ui.shopOpen.add(list.id);
    ui.changed();
  }

  name.onKeyDown.listen((event) {
    if (event.key == 'Enter') focus('next');
  });
  next.onKeyDown.listen((event) {
    if (event.key == 'Enter') addNext();
  });
  // An iPhone has its own tick over the keyboard, which a page cannot take
  // away; it only takes the cursor out. What was typed goes in then as with
  // the keyboard's own tick. A moment later, so that a tap that took the
  // cursor out (the brush, another box) is done first: the brush takes it in
  // itself, and the box tapped keeps the cursor.
  next.onBlur.listen((_) {
    Timer(const Duration(milliseconds: 250), () {
      if (!next.isConnected || next.value.trim().isEmpty) return;
      final was = focused();
      take();
      list.items.add(ShopItem(id: ui.store.newId(), text: next.value.trim(), addedBy: me));
      next.value = '';
      redraw();
      focus(was ?? 'next');
    });
  });
  for (final typed in [name, ...boxes.values]) {
    typed.onChange.listen((_) {
      take();
      if (!draft) ui.saved();
    });
    if (typed != name) {
      typed.onKeyDown.listen((event) {
        if (event.key == 'Enter') typed.blur();
      });
    }
  }

  // An x that leaves the cursor where it is: a press on it takes no focus.
  web.HTMLElement keepsCursor(web.HTMLElement x) {
    x.addEventListener('mousedown', ((web.Event event) => event.preventDefault()).toJS);
    return x;
  }

  web.HTMLElement itemRow(ShopItem item) => el('div', cls: 'shop-item-row', children: [
        el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [boxes[item]!]),
        keepsCursor(button(
          cls: 'icon-button',
          ariaLabel: tr('Ukloni: {0}', [item.text]),
          onTap: () {
            final was = focused();
            take();
            _typedNext[list.id] = next.value;
            final at = list.items.indexOf(item);
            list.items.removeAt(at);
            if (!draft) list.removed[item.id] = (text: item.text, by: me);
            redraw();
            if (was != null && was != item.id) focus(was);
            ui.offerUndo(tr('Uklonjeno: {0}', [item.text]), () {
              list.items.insert(at.clamp(0, list.items.length), item);
              list.removed.remove(item.id);
              redraw();
            });
          },
          children: [icon('close', size: 20)],
        )),
      ]);

  final throwAway = draft
      ? button(
          cls: 'icon-button shop-x',
          ariaLabel: tr('Ukloni: {0}', [list.name.isEmpty ? tr('Nova lista') : list.name]),
          onTap: () {
            take();
            ui.shopDraft = null;
            ui.shopEditing = null;
            ui.rerender();
            ui.offerUndo(tr('Uklonjeno'), () {
              ui.shopDraft = list;
              ui.shopEditing = list.id;
              ui.rerender();
            });
          },
          children: [icon('close', size: 20)],
        )
      : removeWithUndo(ui, trip.shopLists, list, list.name)
    ..classList.add('shop-x');

  return el('div', cls: cost == null ? 'card shop-list shop-edit' : 'card shop-list shop-edit bought',
      attrs: {'data-list': list.id}, children: [
    el('div', cls: 'shop-head', children: [
      el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [name]),
      button(
        cls: 'icon-button brush-small on',
        ariaLabel: tr('Spremi'),
        onTap: done,
        children: [icon('brush', size: 20)],
      ),
      throwAway,
    ]),
    for (final item in list.items) itemRow(item),
    el('div', cls: 'shop-item-row', children: [
      el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [next]),
    ]),
  ]);
}

/// One list. Folded it shows "+ Naziv"; a tap unfolds what is to buy, each
/// with a tick, and Kupljeno, which asks what it cost. The brush in the corner
/// opens the list for changing, with an empty box at the bottom for more.
web.HTMLElement _listCard(Ui ui, Trip trip, ShopList list) {
  if (ui.shopEditing == list.id) return _editCard(ui, trip, list, draft: false);
  final open = ui.shopOpen.contains(list.id);
  final cost = trip.expenses.where((each) => each.id == list.expenseId).firstOrNull;

  web.HTMLElement itemRow(ShopItem item) => el('div', cls: 'shop-item-row', children: [
        tick(item.text, item.done, () {
          item.done = !item.done;
          ui.changed();
        })
          ..classList.add('shop-item'),
      ]);

  // Bought, it greys as a ticked wish does, and says so under its name.
  return el('div', cls: cost == null ? 'card shop-list' : 'card shop-list bought', attrs: {'data-list': list.id}, children: [
    el('div', cls: 'shop-head', children: [
      button(
        cls: 'grow shop-fold',
        onTap: () {
          open ? ui.shopOpen.remove(list.id) : ui.shopOpen.add(list.id);
          ui.rerender();
        },
        children: [
          icon(open ? 'minus' : 'plus', size: 20),
          el('span', cls: 'shop-name', children: [
            el('span', text: list.name),
            if (cost != null) el('span', cls: 'small', text: tr('Kupljeno')),
          ]),
        ],
      )..setAttribute('aria-expanded', '$open'),
      button(
        cls: 'icon-button brush-small',
        ariaLabel: tr('Uredi listu'),
        onTap: () {
          ui.shopEditing = list.id;
          ui.shopOpen.add(list.id);
          ui.rerender();
          (web.document.querySelector('[data-list="${list.id}"] [data-box="next"]') as web.HTMLElement?)
              ?.focus();
        },
        children: [icon('brush', size: 20)],
      ),
    ]),
    if (open) ...[
      for (final item in list.items) itemRow(item),
      el('div', cls: 'shop-actions', children: [
        cost == null
            ? chip(tr('Kupljeno'), () => _buy(ui, trip, list))
            : chip('${tr('Kupljeno')} · ${euros(cost.amount)}', () => _unbuy(ui, trip, list), on: true),
      ]),
    ],
  ]);
}

/// Dućan: lists of what the group wants to buy. Anyone adds to them and ticks
/// what is in the basket; Kupljeno asks what it cost and puts it in Troškovi.
web.HTMLElement shopScreen(Ui ui, Trip trip) {
  final draft = ui.shopDraft;
  // Nova lista opens a new list as it will be, being changed: its name and its
  // first thing ready for typing.
  final newList = adder(tr('Nova lista'), []);
  newList.querySelector('summary')!.addEventListener('click', ((web.Event event) {
    event.preventDefault();
    final list = ShopList(id: ui.store.newId(), name: '');
    ui.shopDraft = list;
    ui.shopEditing = list.id;
    ui.rerender();
    (web.document.querySelector('[data-list="${list.id}"] [data-box="name"]') as web.HTMLElement?)
        ?.focus();
  }).toJS);

  final shown = _shown(ui, trip);
  final toBuy = [for (final list in shown.toBuy) _listCard(ui, trip, list)];
  // A finger held on a list carries it up or down among those to buy; not
  // while one is being changed.
  if (ui.shopEditing == null) {
    for (final card in toBuy) {
      movableUpDown(card, toBuy, (from, to) {
        final ids = [for (final list in shown.toBuy) list.id];
        ids.insert(to, ids.removeAt(from));
        orderShopLists(trip, ids);
        ui.changed();
      });
    }
  }

  return el('div', cls: 'fill-page', children: [
    topBar(tr('Dućan')),
    if (trip.shopLists.isEmpty && draft == null)
      el('p', cls: 'soft pad', text: tr('Napravite listu i dodajte što treba kupiti.')),
    ...toBuy,
    if (draft == null) newList else _editCard(ui, trip, draft, draft: true),
    for (final list in shown.bought) _listCard(ui, trip, list),
    planCost(ui, trip, CostCategory.shop.name),
  ]);
}
