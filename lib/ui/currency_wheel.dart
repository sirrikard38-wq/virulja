import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/currency.dart';
import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import 'context.dart';
import 'dom.dart';

String? _askedOn;

/// Reads the day's rates from the European Central Bank, through the free
/// Frankfurter service, once a day; then [done] runs. Without a connection the
/// last rates stay.
Future<void> loadRates(Ui ui, {void Function()? done}) async {
  final day = DateTime.now().toUtc().toIso8601String().substring(0, 10);
  if (ui.data.ratesDay == day && ui.data.rates.isNotEmpty) return;
  if (_askedOn == day) return; // once a day, even when it failed
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

/// A wheel of currencies: a tap circles one in green and takes it, another tap
/// lets it go. Two at most, the first taken the one amounts are written in;
/// one always stays. [onChange] gets the new choice; the wheel shows it itself,
/// with no redraw, so it stays where it was turned.
web.HTMLElement currencyWheel(Ui ui, List<String> chosen, void Function(List<String>) onChange) {
  var now = cleanCurrencies(chosen);
  final note = el('p', cls: 'small pad');
  final rows = <String, web.HTMLElement>{};

  void show() {
    rows.forEach((code, row) {
      final at = now.indexOf(code);
      row.classList.toggle('on', at >= 0);
      row.setAttribute('aria-pressed', '${at >= 0}');
    });
    note.textContent = now.length == 1
        ? tr('Iznosi se pišu u: {0}', [now.first])
        : tr('Iznosi se pišu u: {0} · Pored: {1}', [now.first, now.last]);
  }

  final wheel = el('div', cls: 'currency-wheel', attrs: {'role': 'list'}, children: [
    for (final currency in currencies)
      rows[currency.code] = (el('button', cls: 'currency-row', attrs: {'type': 'button'}, children: [
        el('span', cls: 'currency-code', text: currency.code),
        el('span', cls: 'currency-sign', text: currency.sign),
      ])
        ..onClick.listen((_) {
          final next = tapCurrency(now, currency.code);
          if (next == null) {
            ui.toast(now.contains(currency.code) ? tr('Jedna valuta mora ostati.') : tr('Najviše dvije valute.'));
            return;
          }
          now = next;
          show();
          onChange(now);
          if (now.length > 1) loadRates(ui);
        })),
  ]);
  show();
  // Turned so that the first chosen one stands in the middle.
  scheduleMicrotask(() {
    final first = rows[now.first];
    if (first == null) return;
    wheel.scrollTop = first.offsetTop - (wheel.clientHeight - first.offsetHeight) / 2;
  });
  return el('div', children: [
    el('div', cls: 'currency-frame', children: [wheel]),
    note,
  ]);
}
