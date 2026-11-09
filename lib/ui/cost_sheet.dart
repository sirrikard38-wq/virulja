import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

/// A box that writes one cost in Troškovi, as a new cost would be: what it
/// cost ([guess] at first), who paid (this person at first) and whom it is
/// for (everyone at first). The x in the top right corner closes it with
/// nothing written. [done] gets the new cost once it is in.
void costSheet(
  Ui ui,
  Trip trip, {
  required String title,
  String? question,
  required String action,
  required CostCategory category,
  int guess = 0,
  List<int> days = const [],
  Set<int> daysDone = const {},
  void Function(Expense cost, int? day)? done,
}) {
  // Koji dan? on top when there are days to choose: the first still open.
  int? day;
  for (final each in days) {
    if (!daysDone.contains(each)) {
      day = each;
      break;
    }
  }
  final amount = amountInput(fit: true);
  if (guess > 0) amount.value = plainAmount(guess);
  var payer = ui.meIn(trip);
  if (!trip.memberIds.contains(payer) && trip.memberIds.isNotEmpty) payer = trip.memberIds.first;
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
      title: title,
      amount: cents,
      payerId: payer,
      sharedBy: [for (final id in trip.memberIds) if (shared.contains(id)) id],
      category: category,
    );
    trip.expenses.add(cost);
    done?.call(cost, day);
    close();
    ui.changed();
  }

  amount.onKeyDown.listen((event) {
    if (event.key == 'Enter') amount.blur();
  });

  void draw() {
    final typed = amount.value;
    card.textContent = '';
    for (final part in [
      button(cls: 'icon-button sheet-x', ariaLabel: tr('Zatvori'), onTap: close,
          children: [icon('close', size: 20)]),
      if (question != null) el('p', cls: 'label', text: question),
      el('p', cls: question == null ? 'label sheet-title' : 'small', text: title),
      if (days.length > 1 || (days.length == 1 && days.first >= 0)) ...[
        el('p', cls: 'label', attrs: {'style': 'margin-top:6px'}, text: tr('Koji dan?')),
        el('div', cls: 'checks', attrs: {'style': 'margin:0'}, children: [
          for (final each in days)
            if (daysDone.contains(each))
              // Already ticked off that day.
              button(cls: 'chip locked', text: '${tr('{0} Dan', [each + 1])} ✓', onTap: () {})
            else
              chip(tr('{0} Dan', [each + 1]), () {
                day = each;
                draw();
              }, on: day == each),
        ]),
      ],
      unitField(tr('Iznos'), amount..value = typed, moneySign())
        ..classList.remove('tight')
        ..classList.add('fit-amount'),
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
      primaryButton(action, save),
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
