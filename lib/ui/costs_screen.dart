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

web.HTMLElement _transferRow(Ui ui, Trip trip, Transfer transfer) => el(
      'div',
      cls: 'row',
      children: [
        el('div', cls: 'grow', text: '${ui.nameOf(transfer.fromId)} → '
            '${ui.nameOf(transfer.toId)}'),
        el('div', cls: 'price', text: euros(transfer.amount)),
        chip(tr('Podmireno'), () {
          trip.payments.add(Payment(
            id: ui.store.newId(),
            fromId: transfer.fromId,
            toId: transfer.toId,
            amount: transfer.amount,
          ));
          ui.changed();
        }),
      ],
    );

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
    for (final transfer in transfers) _transferRow(ui, trip, transfer),
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
        removeButton(expense.title, () {
          trip.expenses.remove(expense);
          ui.changed();
        }),
      ]),
  ]);
}
