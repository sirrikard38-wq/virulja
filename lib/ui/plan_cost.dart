import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// "Planirani trošak:" at the bottom of a screen of Plan: the whole amount the
/// group means to spend on [category], which is then its Planirano in
/// Troškovi. It keeps itself as it is typed; an empty field goes back to the
/// app's own estimate. The box grows with a longer number.
web.HTMLElement planCost(Ui ui, Trip trip, CostCategory category) {
  final set = trip.budgets[category.name];
  final amount = numberInput(placeholder: '0')
    ..value = set == null ? '' : (set / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');

  void fit() => amount.style.width = '${max(4, amount.value.length) + 1}ch';

  amount.onInput.listen((_) {
    fit();
    final text = amount.value.trim();
    if (text.isEmpty) {
      trip.budgets.remove(category.name);
    } else {
      final cents = parseEuros(text);
      if (cents == null) return;
      trip.budgets[category.name] = cents;
    }
    // No redraw: it would take the keyboard away.
    ui.saved();
  });
  amount.onKeyDown.listen((event) {
    if (event.key == 'Enter') amount.blur();
  });
  fit();
  return el('label', cls: 'plan-cost', children: [
    el('span', cls: 'small', text: tr('Planirani trošak:')),
    amount,
    el('span', cls: 'small', text: '€'),
  ]);
}
