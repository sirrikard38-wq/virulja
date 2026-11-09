import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/currency.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';

String? _askedOn;

/// Reads the day's rates from the European Central Bank, through the free
/// Frankfurter service, once a day; then [done] runs. Without a connection the
/// last rates stay.
Future<void> loadRates(Ui ui, {void Function()? done, bool now = false}) async {
  final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  if (ui.data.ratesDay == day && ui.data.rates.isNotEmpty) return;
  if (_askedOn == day && !now) return; // once a day, even when it failed
  _askedOn = day;
  try {
    final response = await web.window
        .fetch('https://api.frankfurter.dev/v2/rates?base=EUR'.toJS)
        .toDart;
    if (!response.ok) return;
    final list = jsonDecode((await response.text().toDart).toDart) as List<dynamic>;
    ui.data.rates = {
      for (final item in list.cast<Map<String, dynamic>>())
        item['quote'] as String: (item['rate'] as num).toDouble(),
    };
    ui.data.ratesDay = day;
    ui.store.save();
    ratesPerEuro = ui.data.rates;
    done?.call();
  } on Object {
    // Asked again next time.
  }
}

/// A wheel of currencies, turned as the time is: the one standing in the
/// middle, under the green ring, is taken with the tick beside it, which
/// [onConfirm] gets; true from it means it is now the one in use. The tick is
/// green while the wheel stands on the one in use, as the tick of Plan napada.
/// The wheel shows it all itself, with no redraw, so it stays where it was
/// turned. One currency for now; a second one beside it may come back.
web.HTMLElement currencyWheel(
    Ui ui, List<String> chosen, Future<bool> Function(String code) onConfirm) {
  var now = cleanCurrencies(chosen).first;
  final note = el('p', cls: 'small pad centered');
  final rows = <web.HTMLElement>[
    for (final currency in currencies)
      el('div', cls: 'currency-row', children: [
        el('span', cls: 'currency-code', text: currency.code),
        el('span', cls: 'currency-sign', text: currency.sign),
      ]),
  ];
  final wheel = el('div', cls: 'currency-wheel', attrs: {'role': 'listbox', 'aria-label': tr('Valuta')}, children: rows);

  /// The row in the middle, as far as the wheel has turned.
  int middle() {
    final height = rows.first.offsetHeight;
    return height == 0 ? 0 : (wheel.scrollTop / height).round().clamp(0, rows.length - 1);
  }

  void show(int at) {
    for (var i = 0; i < rows.length; i++) {
      rows[i].classList.toggle('on', i == at);
    }
    note.textContent = tr('Iznosi se pišu u: {0}', [currencies[at].code]);
  }

  late final web.HTMLElement tick;
  void showTick() => tick.classList.toggle('on', currencies[middle()].code == now);
  tick = button(
    cls: 'icon-button cost-tick currency-tick',
    ariaLabel: tr('Potvrdi valutu'),
    onTap: () async {
      final code = currencies[middle()].code;
      if (code == now) return;
      if (await onConfirm(code)) now = code;
      showTick();
    },
    children: [icon('check', size: 26)],
  );
  wheel.onScroll.listen((_) {
    show(middle());
    showTick();
  });
  final first = max(0, currencies.indexWhere((currency) => currency.code == now));
  show(first);
  tick.classList.add('on');
  // Turned so that the chosen one stands in the middle.
  scheduleMicrotask(() => wheel.scrollTop = first * rows.first.offsetHeight.toDouble());
  return el('div', children: [
    el('div', cls: 'currency-pick', children: [
      el('div', cls: 'currency-frame', children: [wheel]),
      tick,
    ]),
    note,
  ]);
}
