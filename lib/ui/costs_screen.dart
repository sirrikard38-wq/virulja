import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/settlement.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

/// The kinds of cost that always show, even at nothing yet.
const Set<CostCategory> _always = {
  CostCategory.stay,
  CostCategory.food,
  CostCategory.transport,
  CostCategory.shop,
};

/// Asks what [place] really cost, who paid and whom it is for, everyone at
/// first, and writes it in Troškovi.
void _split(Ui ui, Trip trip, Place place) {
  final amount = numberInput();
  final guess = (place.pricePerPerson ?? 0) * trip.people;
  if (guess > 0) amount.value = (guess / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  var payer = ui.meIn(trip);
  final shared = {...trip.memberIds};
  final card = el('div', cls: 'sheet-card card');
  late final web.HTMLElement sheet;
  final letGo = holdPage();
  void close() {
    sheet.remove();
    letGo();
  }

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
      title: place.name,
      amount: cents,
      payerId: payer,
      sharedBy: [for (final id in trip.memberIds) if (shared.contains(id)) id],
      category: CostCategory.food,
    );
    trip.expenses.add(cost);
    place.expenseId = cost.id;
    close();
    ui.changed();
  }

  void draw() {
    final typed = amount.value;
    card.textContent = '';
    for (final part in [
      button(cls: 'icon-button sheet-x', ariaLabel: tr('Zatvori'), onTap: close,
          children: [icon('close', size: 20)]),
      el('p', cls: 'label', text: tr('Koliko je zapravo bilo?')),
      el('p', cls: 'small', text: place.name),
      field(tr('Iznos (€)'), amount..value = typed),
      el('p', cls: 'label', attrs: {'style': 'margin-top:6px'}, text: tr('Tko je platio?')),
      el('div', cls: 'checks', attrs: {'style': 'margin:0'}, children: [
        for (final id in trip.memberIds)
          chip(ui.nameOf(id), () {
            payer = id;
            draw();
          }, on: payer == id),
      ]),
      el('p', cls: 'label', attrs: {'style': 'margin-top:6px'}, text: tr('Na koga se odnosi?')),
      el('div', cls: 'ticks', children: [
        for (final id in trip.memberIds)
          tick(ui.nameOf(id), shared.contains(id), () {
            shared.contains(id) ? shared.remove(id) : shared.add(id);
            draw();
          }),
      ]),
      primaryButton(tr('Razdijeli'), save),
    ]) {
      card.append(part);
    }
  }

  sheet = el('div', cls: 'sheet', attrs: {'role': 'dialog', 'aria-modal': 'true'}, children: [card]);
  sheet.onClick.listen((event) {
    if (event.target == sheet) close();
  });
  web.document.body!.append(sheet);
  draw();
}

web.HTMLElement _total(String label, int cents) => el('div', cls: 'tile card', children: [
      el('span', cls: 'small', text: label),
      el('span', cls: 'value', text: euros(cents)),
    ]);

/// One kind of cost: what was spent, and what is planned and not spent yet.
/// The bar fills with what was spent of the two together.
web.HTMLElement _line(BudgetLine line) {
  final whole = line.actual + line.ahead;
  final share = whole == 0 ? 0 : line.actual / whole;
  return el('div', cls: 'line', children: [
    el('div', attrs: {'style': 'display:flex;justify-content:space-between;gap:12px'},
        children: [
      el('span', cls: 'strong', text: line.category.label),
      el('span', cls: 'small', text: tr('Potrošeno {0} · Planirano {1}', [euros(line.actual), euros(line.ahead)])),
    ]),
    el('div', cls: 'bar', children: [
      el('div', attrs: {
        'style': 'width:${(share.clamp(0, 1) * 100).round()}%',
      }),
    ]),
  ]);
}

/// The fields of a cost: a new one, or [editing] to change, which a tap on it
/// in Plaćeno opens.
List<web.HTMLElement> _expenseFields(Ui ui, Trip trip, {Expense? editing}) {
  final title = input(value: editing?.title ?? '');
  final amount = numberInput()
    ..value = editing == null
        ? ''
        : (editing.amount / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  final category = select(CostCategory.values, (c) => c.label,
      selected: editing?.category ?? CostCategory.food);
  final payer = select(trip.memberIds, ui.nameOf,
      selected: editing != null && trip.memberIds.contains(editing.payerId)
          ? editing.payerId
          : ui.meIn(trip));
  final boxes = {
    for (final id in trip.memberIds)
      id: checkInput(checked: editing == null || editing.sharedBy.contains(id)),
  };
  final error = errorLine();

  void add() {
    final cents = parseEuros(amount.value);
    final sharers = [
      for (final id in trip.memberIds)
        if (boxes[id]!.checked) id,
    ];
    if (title.value.trim().isEmpty || cents == null || cents == 0) {
      error.textContent = tr('Upiši što je plaćeno i koliko.');
      return;
    }
    if (sharers.isEmpty) {
      error.textContent = tr('Označi tko dijeli trošak.');
      return;
    }
    if (editing != null) {
      editing
        ..title = title.value.trim()
        ..amount = cents
        ..payerId = trip.memberIds[payer.selectedIndex]
        ..sharedBy = sharers
        ..category = CostCategory.values[category.selectedIndex];
      ui.editingExpense = null;
    } else {
      trip.expenses.add(Expense(
        id: ui.store.newId(),
        title: title.value.trim(),
        amount: cents,
        payerId: trip.memberIds[payer.selectedIndex],
        sharedBy: sharers,
        category: CostCategory.values[category.selectedIndex],
      ));
    }
    ui.changed();
  }

  return [
    field(tr('Što'), title),
    el('div', cls: 'fields', children: [
      field(tr('Iznos (€)'), amount, tight: true),
      field(tr('Vrsta'), category, tight: true),
    ]),
    field(tr('Tko je platio'), payer),
    el('p', cls: 'label', text: tr('Tko dijeli trošak'), attrs: {'style': 'margin-top:12px'}),
    el('div', cls: 'checks', children: [
      for (final id in trip.memberIds) checkbox(ui.nameOf(id), boxes[id]!),
    ]),
    error,
    if (editing == null)
      primaryButton(tr('Dodaj trošak'), add)
    else
      el('div', attrs: {'style': 'display:flex;gap:12px;align-items:center;margin-top:12px'}, children: [
        primaryButton(tr('Spremi'), add, wide: false),
        button(cls: 'text-button', text: tr('Odustani'), onTap: () {
          ui.editingExpense = null;
          ui.rerender();
        }),
      ]),
  ];
}

web.HTMLElement _addExpense(Ui ui, Trip trip) =>
    adder(tr('Dodaj trošak'), _expenseFields(ui, trip));

/// One cost that was paid: a tap opens it for changing.
web.HTMLElement _paidCost(Ui ui, Trip trip, Expense expense) {
  final editing = ui.editingExpense == expense.id;
  return el('div', children: [
    el('div', cls: 'row', children: [
      button(
        cls: 'grow title-link',
        ariaLabel: tr('Uredi: {0}', [expense.title]),
        onTap: () {
          ui.editingExpense = editing ? null : expense.id;
          ui.rerender();
        },
        children: [
          el('div', text: expense.title),
          el('div', cls: 'small', text: '${ui.nameOf(expense.payerId)} · '
              '${expense.category.label}'),
        ],
      ),
      el('div', cls: 'price', text: euros(expense.amount)),
      removeWithUndo(ui, trip.expenses, expense, expense.title),
    ]),
    if (editing) el('div', cls: 'cost-edit', children: _expenseFields(ui, trip, editing: expense)),
  ]);
}

String _between(Ui ui, String from, String to) => '${ui.nameOf(from)} → ${ui.nameOf(to)}';

web.HTMLElement _transferRow(Ui ui, Trip trip, Transfer transfer) => el(
      'div',
      cls: 'row',
      children: [
        el('div', cls: 'grow', text: _between(ui, transfer.fromId, transfer.toId)),
        el('div', cls: 'price', text: euros(transfer.amount)),
        chip(tr('Podmireno'), () {
          final payment = Payment(
            id: ui.store.newId(),
            fromId: transfer.fromId,
            toId: transfer.toId,
            amount: transfer.amount,
          );
          trip.payments.add(payment);
          ui.changed();
          ui.offerUndo(tr('Podmireno: {0}', [euros(transfer.amount)]), () {
            trip.payments.remove(payment);
            ui.changed();
          });
        }),
      ],
    );

/// A debt that was paid: it stays, green, so that everyone sees who gave whom
/// what. A tap takes it back.
web.HTMLElement _paidRow(Ui ui, Trip trip, Payment payment) => el(
      'div',
      cls: 'row settled',
      children: [
        el('div', cls: 'grow', text: _between(ui, payment.fromId, payment.toId)),
        el('div', cls: 'price', text: euros(payment.amount)),
        chip(tr('Podmireno'), () {
          final at = trip.payments.indexOf(payment);
          if (at < 0) return;
          trip.payments.removeAt(at);
          ui.changed();
          ui.offerUndo(tr('Više nije podmireno: {0}', [euros(payment.amount)]), () {
            trip.payments.insert(min(at, trip.payments.length), payment);
            ui.changed();
          });
        }, on: true),
      ],
    );

/// Debts and payments in the order of the group, each pair together, so that a
/// debt that is paid turns green where it stood.
List<web.HTMLElement> _byPair(
  Trip trip,
  List<({String from, String to, web.HTMLElement row})> rows,
) {
  int place(String id) {
    final at = trip.memberIds.indexOf(id);
    return at < 0 ? trip.memberIds.length : at;
  }

  final order = List.generate(rows.length, (i) => i)
    ..sort((a, b) {
      final from = place(rows[a].from).compareTo(place(rows[b].from));
      if (from != 0) return from;
      final to = place(rows[a].to).compareTo(place(rows[b].to));
      return to != 0 ? to : a.compareTo(b);
    });
  return [for (final i in order) rows[i].row];
}

web.HTMLElement costsScreen(Ui ui, Trip trip) {
  final budget = Budget.of(trip);
  final transfers = debts(trip);
  final recent = trip.expenses.reversed.take(20);
  return el('div', children: [
    topBar(tr('Troškovi')),
    el('div', cls: 'three', children: [
      _total(tr('Potrošeno'), budget.actualTotal),
      _total(tr('Planirano'), budget.aheadTotal),
      _total(tr('Ukupno'), budget.actualTotal + budget.aheadTotal),
    ]),
    for (final line in budget.lines)
      if (line.planned > 0 || line.actual > 0 || _always.contains(line.category)) _line(line),
    if (toSplit(trip).isNotEmpty) ...[
      sectionTitle(tr('Za razdijeliti')),
      for (final place in toSplit(trip))
        el('div', cls: 'row', children: [
          el('div', cls: 'grow', children: [
            el('div', text: place.name),
            el('div', cls: 'small', text: tr('Procjena {0}', [euros((place.pricePerPerson ?? 0) * trip.people)])),
          ]),
          chip(tr('Razdijeli'), () => _split(ui, trip, place)),
        ]),
    ],
    sectionTitle(tr('Tko kome duguje')),
    if (transfers.isEmpty)
      el('p', cls: 'soft pad', text: tr('Svi su računi podmireni.')),
    for (final row in _byPair(trip, [
      for (final transfer in transfers)
        (from: transfer.fromId, to: transfer.toId, row: _transferRow(ui, trip, transfer)),
      for (final payment in trip.payments)
        (from: payment.fromId, to: payment.toId, row: _paidRow(ui, trip, payment)),
    ]))
      row,
    _addExpense(ui, trip),
    if (recent.isNotEmpty) sectionTitle(tr('Plaćeno')),
    for (final expense in recent) _paidCost(ui, trip, expense),
  ]);
}
