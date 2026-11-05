import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// "Planirani trošak:" at the bottom of a screen of Plan, on the right: the
/// whole amount the group means to spend on what [key] names in `Trip.budgets`
/// (a kind of cost, or one category of Hrana i piće), which then counts as its
/// Planirano in Troškovi. It keeps itself as it is typed; an empty field goes
/// back to the app's own estimate. The box grows with a longer number.
web.HTMLElement planCost(Ui ui, Trip trip, String key) {
  final set = trip.budgets[key];
  final amount = numberInput(placeholder: '0')
    ..value = set == null ? '' : (set / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');

  // Room for three digits; a longer number widens it.
  void fit() => amount.style.width = 'calc(${max(3, amount.value.length)}ch + 16px)';

  amount.onInput.listen((_) {
    fit();
    final text = amount.value.trim();
    if (text.isEmpty) {
      trip.budgets.remove(key);
    } else {
      final cents = parseEuros(text);
      if (cents == null) return;
      trip.budgets[key] = cents;
    }
    // No redraw: it would take the keyboard away.
    ui.saved();
  });
  amount.onKeyDown.listen((event) {
    if (event.key == 'Enter') amount.blur();
  });
  fit();
  // Written as "Procjena za" is: the words on the left, the amount on the right.
  return el('label', cls: 'plan-cost', children: [
    el('span', cls: 'grow', text: tr('Planirani trošak:')),
    amount,
    el('span', text: moneySign()),
  ]);
}
