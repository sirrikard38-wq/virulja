import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'cost_sheet.dart';
import 'dom.dart';
import 'icons.dart';
import 'plan_cost.dart';
import 'widgets.dart';

/// Asks what [list] cost, who paid and whom it is for, and writes it in
/// Troškovi under Dućan. Troškovi can change it later.
void _buy(Ui ui, Trip trip, ShopList list) => costSheet(
      ui,
      trip,
      title: list.name,
      question: tr('Unesi iznos'),
      action: tr('Kupljeno'),
      category: CostCategory.shop,
      done: (cost) => list.expenseId = cost.id,
    );

/// Takes the purchase of [list] back, with its cost in Troškovi.
void _unbuy(Ui ui, Trip trip, ShopList list) {
  final at = trip.expenses.indexWhere((cost) => cost.id == list.expenseId);
  final cost = at < 0 ? null : trip.expenses.removeAt(at);
  final id = list.expenseId;
  list.expenseId = null;
  ui.changed();
  ui.offerUndo(tr('Više nije kupljeno'), () {
    list.expenseId = id;
    if (cost != null) trip.expenses.insert(at.clamp(0, trip.expenses.length), cost);
    ui.changed();
  });
}

/// One list. Folded it shows "+ Naziv"; a tap unfolds what is to buy, each
/// with a tick. While wishes are being typed there is the field and Spremi;
/// then Dodaj opens the field again and Kupljeno asks what it cost. The brush
/// in the corner opens the names of the list and of its things for changing.
web.HTMLElement _listCard(Ui ui, Trip trip, ShopList list) {
  final me = ui.meIn(trip);
  final open = ui.shopOpen.contains(list.id);
  final adding = ui.shopAdding.contains(list.id);
  final editing = ui.shopEditing == list.id;
  final next = input(placeholder: tr('Dodaj želju'));
  void keep() {
    final text = next.value.trim();
    if (text.isEmpty) return;
    list.items.add(ShopItem(id: ui.store.newId(), text: text, addedBy: me));
  }

  void add() {
    keep();
    ui.changed();
    // Ready for the next one.
    (web.document.querySelector('[data-list="${list.id}"] .shop-next input') as web.HTMLElement?)?.focus();
  }

  void save() {
    keep();
    ui.shopAdding.remove(list.id);
    ui.changed();
  }

  next.onKeyDown.listen((event) {
    if (event.key == 'Enter') add();
  });
  final cost = trip.expenses.where((each) => each.id == list.expenseId).firstOrNull;

  web.HTMLElement itemRow(ShopItem item) => el('div', cls: 'shop-item-row', children: [
        if (editing)
          el('div', cls: 'grow', children: [
            editableName(item.text, tr('Naziv stavke'), (text) {
              item.text = text;
              ui.changed();
            }),
          ])
        else
          tick(item.text, item.done, () {
            item.done = !item.done;
            ui.changed();
          })
            ..classList.add('shop-item'),
        if (editing)
          button(
            cls: 'icon-button',
            ariaLabel: tr('Ukloni: {0}', [item.text]),
            onTap: () {
              final at = list.items.indexOf(item);
              list.items.removeAt(at);
              list.removed[item.id] = (text: item.text, by: me);
              ui.changed();
              ui.offerUndo(tr('Uklonjeno: {0}', [item.text]), () {
                list.items.insert(at.clamp(0, list.items.length), item);
                list.removed.remove(item.id);
                ui.changed();
              });
            },
            children: [icon('close', size: 20)],
          ),
      ]);

  return el('div', cls: 'card shop-list', attrs: {'data-list': list.id}, children: [
    el('div', cls: 'shop-head', children: [
      if (editing)
        el('div', cls: 'grow', children: [
          editableName(list.name, tr('Naziv liste'), (name) {
            list.name = name;
            cost?.title = name;
            ui.changed();
          })..style.fontSize = '16px',
        ])
      else
        button(
          cls: 'grow shop-fold',
          onTap: () {
            open ? ui.shopOpen.remove(list.id) : ui.shopOpen.add(list.id);
            ui.rerender();
          },
          children: [
            icon(open ? 'minus' : 'plus', size: 20),
            el('span', text: list.name),
          ],
        )..setAttribute('aria-expanded', '$open'),
      if (editing) removeWithUndo(ui, trip.shopLists, list, list.name),
      button(
        cls: editing ? 'icon-button brush-small on' : 'icon-button brush-small',
        ariaLabel: tr('Uredi listu'),
        onTap: () {
          ui.shopEditing = editing ? null : list.id;
          if (!editing) ui.shopOpen.add(list.id);
          ui.rerender();
        },
        children: [icon('brush', size: 20)],
      ),
    ]),
    if (open || editing) ...[
      for (final item in list.items) itemRow(item),
      if (adding)
        el('div', cls: 'shop-next', children: [
          el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [next]),
          button(cls: 'text-button', text: tr('Dodaj'), onTap: save),
        ])
      else if (!editing)
        el('div', cls: 'shop-actions', children: [
          chip(tr('Dodaj'), () {
            ui.shopAdding.add(list.id);
            ui.rerender();
            (web.document.querySelector('[data-list="${list.id}"] .shop-next input') as web.HTMLElement?)?.focus();
          }),
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
  final name = input();
  void make() {
    final title = name.value.trim();
    final list = ShopList(id: ui.store.newId(), name: title.isEmpty ? tr('Dućan') : title);
    trip.shopLists.add(list);
    // A new list opens with its field for wishes.
    ui.shopOpen.add(list.id);
    ui.shopAdding.add(list.id);
    ui.changed();
  }

  return el('div', cls: 'fill-page', children: [
    topBar(tr('Dućan')),
    if (trip.shopLists.isEmpty)
      el('p', cls: 'soft pad', text: tr('Napravite listu i dodajte što treba kupiti.')),
    for (final list in trip.shopLists) _listCard(ui, trip, list),
    adder(tr('Nova lista'), [
      field(tr('Naziv liste'), name),
      primaryButton(tr('Napravi listu'), make),
    ]),
    planCost(ui, trip, CostCategory.shop.name),
  ]);
}

