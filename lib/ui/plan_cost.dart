import 'dart:async';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// "Planirani trošak po osobi:" at the bottom of a screen of Plan, written as
/// "Procjena za" is: what the group means to spend per person on what [key]
/// names in `Trip.budgets` (a kind of cost, or one category of Hrana i piće).
/// For everyone together it is Planirano in Troškovi. It keeps itself as it is
/// typed; an empty field plans nothing. The box has room for three digits and
/// grows with a longer number.
web.HTMLElement planCost(Ui ui, Trip trip, String key) {
  final set = trip.budgets[key];
  final amount = numberInput(placeholder: '0')..value = set == null ? '' : plainAmount(set);
  // The same letters as the box, out of sight, to measure what is typed.
  final measure = el('span', cls: 'plan-cost-measure', attrs: {'aria-hidden': 'true'});

  void fit() {
    final text = amount.value;
    measure.textContent = text.length < 3 ? '000' : text;
    final width = measure.offsetWidth;
    amount.style.width = width > 0
        ? '${width + 22}px'
        : 'calc(${max(3, text.length)}ch + 22px)';
  }

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
  // Once typed, the amount is written as all amounts are: 1.250,50.
  amount.onChange.listen((_) {
    final cents = parseEuros(amount.value);
    if (cents != null) amount.value = plainAmount(cents);
    fit();
  });
  amount.onKeyDown.listen((event) {
    if (event.key == 'Enter') amount.blur();
  });
  fit();
  scheduleMicrotask(fit); // measured once it is on the screen
  return el('label', cls: 'plan-cost', children: [
    el('span', cls: 'grow', text: tr('Planirani trošak po osobi:')),
    amount,
    el('span', cls: 'price', text: moneySign()),
    measure,
  ]);
}
