import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'country_names.dart';
import 'dom.dart';
import 'join_screen.dart';
import 'media.dart';
import 'people_section.dart';
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
    sectionTitle(tr('Grupa')),
    for (final id in trip.memberIds) memberRow(ui, trip, id),
  ]);
}

/// Makes a new trip, or changes [trip] when there is one.
web.HTMLElement tripForm(Ui ui, {Trip? trip}) {
  final country = input(value: trip?.country ?? (language == Language.hr ? 'Hrvatska' : ''), list: 'drzave');
  final city = input(value: trip?.city ?? '');
  final dates = RangePicker(start: trip?.start, end: trip?.end);
  final error = errorLine();
  final cover = el('input', cls: 'file', attrs: {
    'type': 'file',
    'accept': 'image/*',
  }) as web.HTMLInputElement;
  final coverName = el('span', text: tr('Odaberi fotografiju'));
  cover.onChange.listen((_) {
    if (pickedFiles(cover).isNotEmpty) coverName.textContent = tr('Fotografija odabrana');
  });

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
          adminIds: [ui.meId],
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

  return el('div', children: [
    topBar(trip == null ? tr('Novo putovanje') : tr('Postavke')),
    el('datalist', attrs: {'id': 'drzave'}, children: [
      for (final name in countryNames()) el('option', attrs: {'value': name}),
    ]),
    field(tr('Država'), country),
    field(tr('Grad'), city),
    dates.element,
    el('p', cls: 'label pad gap-top', text: tr('Fotografija za razglednicu')),
    el('label', cls: 'secondary wide', attrs: {'style': 'margin-top:6px'}, children: [
      cover,
      coverName,
    ]),
    error,
    primaryButton(trip == null ? tr('Napravi putovanje') : tr('Spremi'), save),
    if (trip != null && ui.cloud != null) _members(ui, trip),
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
