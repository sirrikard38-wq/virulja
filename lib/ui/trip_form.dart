import 'package:web/web.dart' as web;

import '../src/domain/countries.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'media.dart';
import 'widgets.dart';

/// Makes a new trip, or changes [trip] when there is one.
web.HTMLElement tripForm(Ui ui, {Trip? trip}) {
  final country = input(
    value: trip?.country ?? 'Hrvatska',
    list: 'drzave',
    placeholder: 'Hrvatska',
  );
  final city = input(value: trip?.city ?? '', placeholder: 'Vis');
  final start = input(type: 'date', value: trip == null ? '' : dayKey(trip.start));
  final end = input(type: 'date', value: trip == null ? '' : dayKey(trip.end));
  final newPerson = input(placeholder: 'Ime');
  final error = errorLine();
  final cover = el('input', cls: 'file', attrs: {
    'type': 'file',
    'accept': 'image/*',
  }) as web.HTMLInputElement;
  final coverName = el('span', text: 'Odaberi fotografiju');
  cover.onChange.listen((_) {
    if (pickedFiles(cover).isNotEmpty) coverName.textContent = 'Fotografija odabrana';
  });

  final boxes = <String, web.HTMLInputElement>{
    for (final person in ui.data.people)
      person.id: checkInput(
        checked: trip == null
            ? person.id == ui.meId
            : trip.memberIds.contains(person.id),
      ),
  };
  final people = el('div', cls: 'checks', children: [
    for (final person in ui.data.people)
      checkbox(person.name, boxes[person.id]!),
  ]);

  void addPerson() {
    final name = newPerson.value.trim();
    if (name.isEmpty) return;
    final person = Person(id: ui.store.newId(), name: name);
    ui.data.people.add(person);
    final box = checkInput(checked: true);
    boxes[person.id] = box;
    people.appendChild(checkbox(person.name, box));
    newPerson.value = '';
    ui.store.save();
  }

  Future<void> save() async {
    final from = start.value, to = end.value;
    final message = city.value.trim().isEmpty
        ? 'Upiši grad.'
        : country.value.trim().isEmpty
            ? 'Upiši državu.'
            : from.isEmpty || to.isEmpty
                ? 'Odaberi datume putovanja.'
                : parseDay(to).isBefore(parseDay(from))
                    ? 'Povratak ne može biti prije polaska.'
                    : null;
    if (message != null) {
      error.textContent = message;
      return;
    }
    addPerson();
    final members = [
      for (final person in ui.data.people)
        if (boxes[person.id]?.checked ?? false) person.id,
    ];
    if (members.isEmpty) {
      error.textContent = 'U grupi mora biti barem jedna osoba.';
      return;
    }
    final saved = trip ??
        Trip(
          id: ui.store.newId(),
          country: country.value.trim(),
          city: city.value.trim(),
          start: parseDay(from),
          end: parseDay(to),
          memberIds: members,
        );
    saved
      ..country = country.value.trim()
      ..city = city.value.trim()
      ..start = parseDay(from)
      ..end = parseDay(to)
      ..memberIds = members;
    final files = pickedFiles(cover);
    if (files.isNotEmpty) {
      final id = ui.store.newId();
      try {
        await storePicture(ui.store, id, files.first);
        saved.coverId = id;
      } on Object {
        ui.toast('Tu fotografiju ne mogu pročitati.');
      }
    }
    if (trip == null) ui.data.trips.add(saved);
    ui.store.save();
    if (trip == null) {
      ui.openTrip(saved);
    } else {
      ui.back();
    }
  }

  void delete() {
    if (!web.window.confirm('Obrisati putovanje ${trip!.city} sa svim fotografijama?')) {
      return;
    }
    for (final photo in trip.photos) {
      ui.store.removeBlob(photo.id);
      ui.store.removeBlob(thumbId(photo.id));
    }
    ui.data.trips.remove(trip);
    ui.store.save();
    ui.go('#/');
  }

  return el('div', children: [
    topBar(trip == null ? 'Novo putovanje' : 'Uredi putovanje'),
    el('datalist', attrs: {'id': 'drzave'}, children: [
      for (final name in countries) el('option', attrs: {'value': name}),
    ]),
    field('Država', country),
    field('Grad', city),
    el('div', cls: 'fields', children: [
      field('Polazak', start, tight: true),
      field('Povratak', end, tight: true),
    ]),
    el('p', cls: 'label pad gap-top', text: 'Tko ide?'),
    people,
    el('div', cls: 'fields', children: [
      field('Dodaj osobu', newPerson, tight: true),
      el('div', attrs: {'style': 'align-self:end'}, children: [
        secondaryButton('Dodaj', addPerson),
      ]),
    ]),
    el('p', cls: 'label pad gap-top', text: 'Fotografija za razglednicu'),
    el('label', cls: 'secondary wide', attrs: {'style': 'margin-top:6px'}, children: [
      cover,
      coverName,
    ]),
    error,
    primaryButton(trip == null ? 'Napravi putovanje' : 'Spremi', save),
    if (trip != null)
      el('div', cls: 'pad gap-top', children: [
        button(
          cls: 'text-button danger',
          text: 'Obriši putovanje',
          onTap: delete,
        ),
      ]),
  ]);
}
