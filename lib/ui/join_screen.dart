import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// Opens WhatsApp with the trip's code ready to send.
void sendCodeOnWhatsApp(Trip trip) {
  final text = 'Šifra putovanja "${trip.city}": ${trip.code}\n'
      '${web.window.location.href.split('#').first}';
  web.window.open(
    Uri.https('wa.me', '/', {'text': text}).toString(),
    '_blank',
  );
}

Future<void> copyCode(Ui ui, Trip trip) async {
  try {
    await web.window.navigator.clipboard.writeText(trip.code ?? '').toDart;
    ui.toast('Šifra je kopirana.');
  } on Object {
    ui.toast('Šifra: ${trip.code}');
  }
}

/// Enter a code once and the trip stays on this phone.
Future<void> joinByCode(Ui ui, String code, web.Element error) async {
  final cloud = ui.cloud;
  if (cloud == null) return;
  try {
    final found = await cloud.findTrip(code);
    if (found == null) {
      error.textContent = 'Nema putovanja s tom šifrom.';
      return;
    }
    if (ui.data.tripById(found.trip.trip.id) == null) cloud.join(found);
    ui.openTrip(ui.data.tripById(found.trip.trip.id)!);
  } on Object {
    error.textContent = 'Ne mogu provjeriti šifru. Možda si uklonjen s putovanja '
        'ili nema interneta.';
  }
}

web.HTMLElement codeField(Ui ui) {
  final code = input(inputMode: 'numeric');
  final error = errorLine();
  return el('div', children: [
    field('Šifra putovanja', code),
    error,
    primaryButton('Uđi na putovanje', () {
      final digits = code.value.replaceAll(RegExp(r'\D'), '');
      if (digits.length != 10) {
        error.textContent = 'Šifra ima 10 znamenki.';
      } else {
        joinByCode(ui, digits, error);
      }
    }),
  ]);
}
