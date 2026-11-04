import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// "Planiraj trošak" at the bottom of a screen of Plan: the whole amount the
/// group means to spend on [category], which is then its Planirano in
/// Troškovi; an empty field goes back to the app's own estimate.
web.HTMLElement planCost(Ui ui, Trip trip, CostCategory category) {
  final set = trip.budgets[category.name];
  final amount = numberInput()
    ..value = set == null ? '' : (set / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  final line = Budget.of(trip).line(category);

  void save() {
    final text = amount.value.trim();
    if (text.isEmpty) {
      trip.budgets.remove(category.name);
    } else {
      final cents = parseEuros(text);
      if (cents == null) {
        ui.toast(tr('Upiši iznos.'));
        return;
      }
      trip.budgets[category.name] = cents;
    }
    ui.changed();
    ui.toast(tr('Spremljeno.'));
  }

  amount.onKeyDown.listen((event) {
    if (event.key == 'Enter') save();
  });
  return el('div', cls: 'plan-cost', children: [
    sectionTitle(tr('Planiraj trošak')),
    el('p', cls: 'small pad', text: tr('Potrošeno {0} · Planirano {1}', [euros(line.actual), euros(line.planned)])),
    el('div', cls: 'plan-cost-row', children: [
      el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [amount]),
      button(cls: 'text-button', text: tr('Spremi'), onTap: save),
    ]),
  ]);
}
