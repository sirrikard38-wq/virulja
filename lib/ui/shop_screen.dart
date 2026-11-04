import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

/// Asks what [list] cost and whom it is for, everyone at first, and writes it
/// in Troškovi under Dućan, paid by this person. Troškovi can change it later.
void _buy(Ui ui, Trip trip, ShopList list) {
  final amount = numberInput();
  final shared = {...trip.memberIds};
  final card = el('div', cls: 'sheet-card card');
  late final web.HTMLElement sheet;
  void close() => sheet.remove();

  void save() {
    final cents = parseEuros(amount.value);
    if (cents == null || cents == 0) {
      ui.toast(tr('Upiši iznos.'));
      return;
    }
    if (shared.isEmpty) {
      ui.toast(tr('Odaberi barem jednu osobu.'));
      return;
    }
    final cost = Expense(
      id: ui.store.newId(),
      title: list.name,
      amount: cents,
      payerId: ui.meIn(trip),
      sharedBy: [for (final id in trip.memberIds) if (shared.contains(id)) id],
      category: CostCategory.shop,
    );
    trip.expenses.add(cost);
    list.expenseId = cost.id;
    close();
    ui.changed();
  }

  amount.onKeyDown.listen((event) {
    if (event.key == 'Enter') save();
  });
  final people = el('div', cls: 'ticks');
  void drawPeople() {
    people.textContent = '';
    for (final id in trip.memberIds) {
      people.append(tick(ui.nameOf(id), shared.contains(id), () {
        shared.contains(id) ? shared.remove(id) : shared.add(id);
        drawPeople();
      }));
    }
  }

  drawPeople();
  for (final part in [
    button(cls: 'icon-button sheet-x', ariaLabel: tr('Zatvori'), onTap: close,
        children: [icon('close', size: 20)]),
    el('p', cls: 'label', text: tr('Unesi iznos')),
    el('p', cls: 'small', text: list.name),
    field(tr('Iznos (€)'), amount),
    el('p', cls: 'label', attrs: {'style': 'margin-top:6px'}, text: tr('Na koga se odnosi?')),
    people,
    primaryButton(tr('Kupljeno'), save),
  ]) {
    card.append(part);
  }
  sheet = el('div', cls: 'sheet', attrs: {'role': 'dialog', 'aria-modal': 'true'}, children: [card]);
  sheet.onClick.listen((event) {
    if (event.target == sheet) close();
  });
  web.document.body!.append(sheet);
}

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

/// One list: its name, typed in place, its things with a tick each, a field
/// for one more, and Kupljeno.
web.HTMLElement _listCard(Ui ui, Trip trip, ShopList list) {
  final me = ui.meIn(trip);
  final next = input(placeholder: tr('Dodaj stavku'));
  void add() {
    final text = next.value.trim();
    if (text.isEmpty) return;
    list.items.add(ShopItem(id: ui.store.newId(), text: text, addedBy: me));
    ui.changed();
    // Ready for the next one.
    (web.document.querySelector('[data-list="${list.id}"] .shop-next input') as web.HTMLElement?)?.focus();
  }

  next.onKeyDown.listen((event) {
    if (event.key == 'Enter') add();
  });
  final cost = trip.expenses.where((each) => each.id == list.expenseId).firstOrNull;
  return el('div', cls: 'card shop-list', attrs: {'data-list': list.id}, children: [
    el('div', cls: 'shop-head', children: [
      el('div', cls: 'grow', children: [
        editableName(list.name, tr('Naziv liste'), (name) {
          list.name = name;
          cost?.title = name;
          ui.changed();
        })..style.fontSize = '16px',
      ]),
      removeWithUndo(ui, trip.shopLists, list, list.name),
    ]),
    for (final item in list.items)
      el('div', cls: 'shop-item-row', children: [
        tick(item.text, item.done, () {
          item.done = !item.done;
          ui.changed();
        })
          ..classList.add('shop-item'),
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
      ]),
    el('div', cls: 'shop-next', children: [
      el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [next]),
      button(cls: 'text-button', text: tr('Dodaj'), onTap: add),
    ]),
    el('div', attrs: {'style': 'margin-top:10px'}, children: [
      cost == null
          ? chip(tr('Kupljeno'), () => _buy(ui, trip, list))
          : chip('${tr('Kupljeno')} · ${euros(cost.amount)}', () => _unbuy(ui, trip, list), on: true),
    ]),
  ]);
}

/// Dućan: lists of what the group wants to buy. Anyone adds to them and ticks
/// what is in the basket; Kupljeno asks what it cost and puts it in Troškovi.
web.HTMLElement shopScreen(Ui ui, Trip trip) {
  final name = input();
  void make() {
    final title = name.value.trim();
    trip.shopLists.add(ShopList(
      id: ui.store.newId(),
      name: title.isEmpty ? tr('Dućan') : title,
    ));
    ui.changed();
  }

  return el('div', children: [
    topBar(tr('Dućan')),
    if (trip.shopLists.isEmpty)
      el('p', cls: 'soft pad', text: tr('Napravite listu i dodajte što treba kupiti.')),
    for (final list in trip.shopLists) _listCard(ui, trip, list),
    adder(tr('Nova lista'), [
      field(tr('Naziv liste'), name),
      primaryButton(tr('Napravi listu'), make),
    ]),
  ]);
}

/// How many things are still to buy on every list of [trip].
int itemsLeft(Trip trip) => trip.shopLists
    .where((list) => list.expenseId == null)
    .fold(0, (sum, list) => sum + list.items.where((item) => !item.done).length);
