import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/trip_currency.dart';
import 'currency_wheel.dart';
import 'context.dart';
import 'country_names.dart';
import 'dom.dart';
import 'join_screen.dart';
import 'media.dart';
import 'notifications_section.dart';
import 'people_section.dart';
import 'profile_section.dart';
import 'range_picker.dart';
import 'widgets.dart';

/// The group of a trip: nobody is added by hand, people appear when they enter
/// the code.
web.HTMLElement _members(Ui ui, Trip trip) {
  return el('div', children: [
    sectionTitle(tr('Šifra putovanja')),
    el('div', cls: 'row', children: [
      el('div', cls: 'grow title', text: trip.code ?? tr('Priprema se...')),
    ]),
    el('div', cls: 'two', children: [
      secondaryButton(tr('Pošalji na WhatsApp'), () => sendCodeOnWhatsApp(trip)),
      secondaryButton(tr('Kopiraj'), () => copyCode(ui, trip)),
    ]),
    el('div', cls: 'pad gap-top', children: [
      button(cls: 'text-button', text: tr('Promijeni šifru'), onTap: () async {
        if (!web.window.confirm(tr('Promijeniti šifru? Članovi ostaju na putovanju.'))) {
          return;
        }
        try {
          await ui.cloud?.changeCode(trip);
        } on Object {
          ui.toast(tr('Nema veze. Pokušaj ponovno.'));
        }
        ui.rerender();
      }),
    ]),
    sectionTitle(tr('Putolovci')),
    for (final id in trip.memberIds) memberRow(ui, trip, id),
  ]);
}

/// Makes a new trip, or changes [trip] when there is one.
web.HTMLElement tripForm(Ui ui, {Trip? trip}) {
  final country = input(value: trip?.country ?? (language == Language.hr ? 'Hrvatska' : ''), list: 'drzave');
  final city = input(value: trip?.city ?? '');
  final dates = RangePicker(start: trip?.start, end: trip?.end);
  final error = errorLine();
  var money = trip?.currencies ?? ui.data.currencies;
  final cover = el('input', cls: 'file', attrs: {
    'type': 'file',
    'accept': 'image/*',
  }) as web.HTMLInputElement;
  final coverName = el('span', text: tr('Odaberi fotografiju'));
  cover.onChange.listen((_) async {
    if (pickedFiles(cover).isEmpty) return;
    coverName.textContent = tr('Fotografija odabrana');
    if (trip == null) return; // a new trip takes it with Napravi putovanje
    final id = ui.store.newId();
    try {
      await storePicture(ui.store, id, pickedFiles(cover).first);
      trip.coverId = id;
      ui.saved();
      ui.toast(tr('Spremljeno.'));
    } on Object {
      ui.toast(tr('Tu fotografiju ne mogu pročitati.'));
    }
  });

  // A trip's settings have no Spremi: what is typed is kept as it is typed,
  // and the dates and the currency once the settings are left. A new currency
  // converts every amount of the trip at the day's rate.
  if (trip != null) {
    void keepText() {
      if (country.value.trim().isNotEmpty) trip.country = country.value.trim();
      if (city.value.trim().isNotEmpty) trip.city = city.value.trim();
      ui.saved();
    }

    country.onInput.listen((_) => keepText());
    city.onInput.listen((_) => keepText());
    ui.onLeave = () {
      final from = dates.start, to = dates.end;
      if (from != null && to != null) {
        trip
          ..start = from
          ..end = to;
        ui.saved();
      }
      final next = money.first;
      if (next == trip.currencies.first) return;
      loadRates(ui, now: true).then((_) {
        if (changeTripCurrency(trip, next, ui.data.rates)) {
          ui.changed();
          ui.toast(tr('Svi iznosi su preračunati u {0} po današnjem tečaju.', [next]), long: true);
        } else {
          ui.toast(tr('Za preračun treba internet. Valuta nije promijenjena.'), long: true);
        }
      });
    };
  }

  Future<void> save() async {
    final from = dates.start, to = dates.end;
    final message = city.value.trim().isEmpty
        ? tr('Upiši grad.')
        : country.value.trim().isEmpty
            ? tr('Upiši državu.')
            : from == null || to == null
                ? tr('Odaberi polazak i povratak u kalendaru.')
                : null;
    if (message != null) {
      error.textContent = message;
      return;
    }
    final saved = trip ??
        Trip(
          id: ui.store.newSecretId(),
          country: country.value.trim(),
          city: city.value.trim(),
          start: from!,
          end: to!,
          memberIds: [ui.meId],
          currencies: money,
        );
    saved
      ..country = country.value.trim()
      ..city = city.value.trim()
      ..start = from!
      ..end = to!;
    final files = pickedFiles(cover);
    if (files.isNotEmpty) {
      final id = ui.store.newId();
      try {
        await storePicture(ui.store, id, files.first);
        saved.coverId = id;
      } on Object {
        ui.toast(tr('Tu fotografiju ne mogu pročitati.'));
      }
    }
    if (trip == null) ui.data.trips.add(saved);
    ui.saved();
    if (trip == null) {
      ui.openTrip(saved);
    } else {
      ui.back();
    }
  }

  /// Takes the trip off this phone. For the rest of the group nothing changes,
  /// so nobody can wipe a shared trip by accident.
  void remove() {
    if (!web.window.confirm(tr('Ukloniti putovanje {0} s ovog mobitela? Ostali u grupi i dalje će ga imati.', [trip!.city]))) {
      return;
    }
    for (final photo in trip.photos) {
      ui.store.removeBlob(photo.id);
      ui.store.removeBlob(thumbId(photo.id));
    }
    ui.data.trips.remove(trip);
    ui.data.identities.remove(trip.id);
    ui.store.forgetMirror(trip.id);
    ui.saved();
    ui.go('#/');
  }

  return el('div', cls: 'trip-settings', children: [
    topBar(trip == null ? tr('Novo putovanje') : tr('Postavke')),
    el('datalist', attrs: {'id': 'drzave'}, children: [
      for (final name in countryNames()) el('option', attrs: {'value': name}),
    ]),
    // Where the trip goes, in one row at the top.
    el('div', cls: 'form-row', attrs: {'style': 'margin-bottom:16px'}, children: [
      field(tr('Država'), country, tight: true),
      field(tr('Grad'), city, tight: true),
    ]),
    if (trip != null) profilePhoto(ui, trip: trip),
    dates.element,
    sectionTitle(tr('Valuta')),
    // Kept when the settings are left, so that turning past others changes nothing.
    currencyWheel(ui, money, (chosen) => money = chosen),
    sectionTitle(tr('Razglednica')),
    el('label', cls: 'secondary wide', attrs: {'style': 'margin-top:6px'}, children: [
      cover,
      coverName,
    ]),
    if (trip == null) ...[
      error,
      primaryButton(tr('Napravi putovanje'), save),
    ],
    if (trip != null && ui.cloud != null) _members(ui, trip),
    if (trip != null && ui.cloud?.pushKey != null) notificationsSection(ui, trip: trip),
    if (trip != null)
      el('div', cls: 'pad gap-top', children: [
        button(
          cls: 'text-button danger',
          text: tr('Ukloni s ovog mobitela'),
          onTap: remove,
        ),
      ]),
  ]);
}
