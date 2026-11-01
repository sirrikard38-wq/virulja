import 'dart:async';
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

/// A trip's code; a tap copies it and says so beside the code for a moment.
web.HTMLElement codeRow(Trip trip) {
  final note = el('span', cls: 'label', attrs: {'style': 'color:var(--accent);font-size:17px'});
  return button(
    cls: 'title-link pad gap-top',
    onTap: () async {
      try {
        await web.window.navigator.clipboard.writeText(trip.code ?? '').toDart;
        note.textContent = 'Kopirano';
        Timer(const Duration(seconds: 2), () => note.textContent = '');
      } on Object {
        note.textContent = 'Kopiraj ručno';
      }
    },
    children: [
      el('div', cls: 'small', text: trip.city),
      el('div', attrs: {'style': 'display:flex;align-items:center;gap:12px'}, children: [
        el('span', cls: 'label', text: trip.code),
        note,
      ]),
    ],
  );
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
    final trip = found.trip.trip;
    if (ui.data.tripById(trip.id) == null) {
      if (trip.approvalsNeeded > 0) {
        await cloud.askToJoin(found);
        ui.toast('Zahtjev je poslan. Grupa te mora prihvatiti.');
        ui.rerender();
        return;
      }
      cloud.join(found);
    }
    ui.openTrip(ui.data.tripById(trip.id)!);
  } on Object {
    error.textContent = 'Ne mogu provjeriti šifru. Možda si uklonjen s putovanja '
        'ili nema interneta.';
  }
}

web.HTMLElement codeField(Ui ui) {
  final code = input()
    ..setAttribute('autocapitalize', 'none')
    ..setAttribute('autocorrect', 'off');
  final error = errorLine();
  return el('div', children: [
    field('Šifra putovanja', code),
    error,
    primaryButton('Uđi na putovanje', () {
      final typed = code.value.trim();
      if (typed.length != 10) {
        error.textContent = 'Šifra ima 10 znakova.';
      } else {
        joinByCode(ui, typed, error);
      }
    }),
  ]);
}
