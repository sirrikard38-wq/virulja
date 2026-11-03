import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/settlement.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

web.HTMLElement _total(String label, int cents) => el('div', cls: 'tile card', children: [
      el('span', cls: 'small', text: label),
      el('span', cls: 'value', text: euros(cents)),
    ]);

web.HTMLElement _line(BudgetLine line) {
  final share = line.planned == 0 ? 0 : line.actual / line.planned;
  return el('div', cls: 'line', children: [
    el('div', attrs: {'style': 'display:flex;justify-content:space-between;gap:12px'},
        children: [
      el('span', cls: 'strong', text: line.category.label),
      el('span', cls: 'small', text: '${euros(line.actual)} od ${euros(line.planned)}'),
    ]),
    el('div', cls: 'bar', children: [
      el('div', cls: share > 1 ? 'over' : null, attrs: {
        'style': 'width:${(share.clamp(0, 1) * 100).round()}%',
      }),
    ]),
  ]);
}

web.HTMLElement _addExpense(Ui ui, Trip trip) {
  final title = input();
  final amount = numberInput();
  final category = select(CostCategory.values, (c) => c.label, selected: CostCategory.food);
  final payer = select(trip.memberIds, ui.nameOf, selected: ui.meIn(trip));
  final boxes = {for (final id in trip.memberIds) id: checkInput(checked: true)};
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
    trip.expenses.add(Expense(
      id: ui.store.newId(),
      title: title.value.trim(),
      amount: cents,
      payerId: trip.memberIds[payer.selectedIndex],
      sharedBy: sharers,
      category: CostCategory.values[category.selectedIndex],
    ));
    ui.changed();
  }

  return adder(tr('Dodaj trošak'), [
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
    primaryButton(tr('Dodaj trošak'), add),
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
      _total(tr('Plan'), budget.plannedTotal),
      _total(tr('Potrošeno'), budget.actualTotal),
      _total(tr('Ostaje'), budget.plannedTotal - budget.actualTotal),
    ]),
    for (final line in budget.lines)
      if (line.planned > 0 || line.actual > 0) _line(line),
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
    for (final expense in recent)
      el('div', cls: 'row', children: [
        el('div', cls: 'grow', children: [
          el('div', text: expense.title),
          el('div', cls: 'small', text: '${ui.nameOf(expense.payerId)} · '
              '${expense.category.label}'),
        ]),
        el('div', cls: 'price', text: euros(expense.amount)),
        removeWithUndo(ui, trip.expenses, expense, expense.title),
      ]),
  ]);
}
