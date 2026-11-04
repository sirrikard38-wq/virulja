import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import '../src/domain/offers.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

/// Asks where the link of a stay should go when it has both a place on the map
/// and an offer on Booking or Airbnb.
void _chooseWhere(Offer offer) {
  late final web.HTMLElement sheet;
  void close() => sheet.remove();
  web.HTMLElement away(String label, String address) => el('a', cls: 'secondary wide', text: label, attrs: {
        'href': address,
        'target': '_blank',
        'rel': 'noopener',
      })..onClick.listen((_) => close());
  sheet = el('div', cls: 'sheet', attrs: {'role': 'dialog', 'aria-modal': 'true'}, children: [
    el('div', cls: 'sheet-card card', children: [
      button(
        cls: 'icon-button sheet-x',
        ariaLabel: tr('Zatvori'),
        onTap: close,
        children: [icon('close', size: 20)],
      ),
      el('p', cls: 'label', text: tr('Što želiš otvoriti?')),
      away(tr('Lokacija na Google Maps'), '${mapsOf(offer.location!)}'),
      away(switch (offer.source) {
        'Booking' => tr('Ponuda na Bookingu'),
        'Airbnb' => tr('Ponuda na Airbnbu'),
        _ => tr('Otvori ponudu'),
      }, offer.link!),
    ]),
  ]);
  sheet.onClick.listen((event) {
    if (event.target == sheet) close();
  });
  web.document.body!.append(sheet);
}

/// Asks who paid for [offer] and whom it is for, everyone at first, then books
/// it: the cost goes into Troškovi, so the others owe the one who paid.
void _reserve(Ui ui, Trip trip, Offer offer) {
  var payer = ui.meIn(trip);
  final shared = {...trip.memberIds};
  final total = offer.pricePerNight * trip.nights;
  final card = el('div', cls: 'sheet-card card');
  late final web.HTMLElement sheet;
  void close() => sheet.remove();

  void book() {
    if (shared.isEmpty) {
      ui.toast(tr('Odaberi barem jednu osobu.'));
      return;
    }
    final cost = Expense(
      id: ui.store.newId(),
      title: offer.name,
      amount: total,
      payerId: payer,
      sharedBy: [for (final id in trip.memberIds) if (shared.contains(id)) id],
      category: CostCategory.stay,
    );
    trip.expenses.add(cost);
    offer
      ..reserved = true
      ..expenseId = cost.id;
    close();
    ui.changed();
  }

  void draw() {
    card.textContent = '';
    for (final part in [
      button(cls: 'icon-button sheet-x', ariaLabel: tr('Zatvori'), onTap: close,
          children: [icon('close', size: 20)]),
      el('p', cls: 'label', text: tr('Tko je platio?')),
      el('p', cls: 'small', text: '${offer.name} · ${nightsCount(trip.nights)} · ${euros(total)}'),
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
      primaryButton(tr('Rezervirano'), book),
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

/// Takes a stay's reservation back, with its cost in Troškovi, and a moment to
/// change your mind.
void _unreserve(Ui ui, Trip trip, Offer offer) {
  final at = trip.expenses.indexWhere((cost) => cost.id == offer.expenseId);
  final cost = at < 0 ? null : trip.expenses.removeAt(at);
  offer.reserved = false;
  ui.changed();
  ui.offerUndo(tr('Rezervacija je poništena'), () {
    offer.reserved = true;
    if (cost != null) trip.expenses.insert(at.clamp(0, trip.expenses.length), cost);
    ui.changed();
  });
}

/// The link at the end of a stay: to the offer, to its place on the map, or a
/// question which of the two when it has both.
web.HTMLElement? _offerLink(Offer offer) {
  final link = offer.link, location = offer.location;
  if (link != null && location != null) {
    return button(
      cls: 'icon-button',
      ariaLabel: tr('Otvori ponudu ili lokaciju'),
      onTap: () => _chooseWhere(offer),
      children: [icon('link', size: 20)],
    );
  }
  if (link != null) return linkIcon(link, tr('Otvori ponudu'));
  if (location != null) return linkIcon('${mapsOf(location)}', tr('Lokacija na Google Maps'));
  return null;
}

/// Changes what was written about a stay: its link, place, price and the rest.
web.HTMLElement _offerEdit(Ui ui, Offer offer) {
  final link = input(type: 'url', value: offer.link ?? '');
  final location = input(value: offer.location ?? '', placeholder: tr('Adresa ili link s Google Mapsa'));
  final price = numberInput()..value = (offer.pricePerNight / 100).toStringAsFixed(2).replaceFirst(RegExp(r'\.00$'), '');
  final rating = numberInput()..value = offer.rating?.toString().replaceAll('.', ',') ?? '';
  final beach = numberInput()..value = offer.beachMeters?.toString() ?? '';
  final error = errorLine();

  void save() {
    final cents = parseEuros(price.value);
    if (cents == null || cents == 0) {
      error.textContent = tr('Upiši cijenu po noći.');
      return;
    }
    final stars = double.tryParse(rating.value.trim().replaceAll(',', '.'));
    if (rating.value.trim().isNotEmpty && (stars == null || stars < 0 || stars > 5)) {
      error.textContent = tr('Ocjena ide od 0 do 5.');
      return;
    }
    final address = link.value.trim();
    final place = location.value.trim();
    offer
      ..link = address.isEmpty ? null : address
      ..source = _sourceOf(address)
      ..location = place.isEmpty ? null : place
      ..pricePerNight = cents
      ..rating = stars
      ..beachMeters = int.tryParse(beach.value.trim());
    ui.editingOffer = null;
    ui.changed();
  }

  return el('div', cls: 'offer-edit', children: [
    field(tr('Link ponude'), link),
    field(tr('Lokacija'), location),
    field(tr('Do plaže (m)'), beach),
    el('div', cls: 'fields', children: [
      field(tr('Cijena po noći (€)'), price, tight: true),
      field(tr('Ocjena (0 do 5)'), rating, tight: true),
    ]),
    error,
    el('div', attrs: {'style': 'display:flex;gap:12px;align-items:center;margin-top:10px'}, children: [
      primaryButton(tr('Spremi'), save, wide: false),
      button(cls: 'text-button', text: tr('Odustani'), onTap: () {
        ui.editingOffer = null;
        ui.rerender();
      }),
    ]),
  ]);
}

web.HTMLElement _offerCard(Ui ui, Trip trip, Offer offer, {required bool best}) {
  final me = ui.meIn(trip);
  final voted = offer.votes.contains(me);
  final chosen = trip.chosenOfferId == offer.id;
  final editing = ui.editingOffer == offer.id;
  final opener = _offerLink(offer);
  return el('div', cls: offer.reserved ? 'card offer reserved' : 'card offer', children: [
    removeWithUndo(ui, trip.offers, offer, offer.name, also: () {
      if (chosen) trip.chosenOfferId = null;
      return () {
        if (chosen) trip.chosenOfferId = offer.id;
      };
    })
      ..classList.add('offer-x'),
    el('div', attrs: {'style': 'display:flex;justify-content:space-between;gap:12px'},
        children: [
      el('div', cls: 'grow', children: [
        if (best) el('span', cls: 'badge', text: tr('Preporuka')),
        editableName(offer.name, tr('Naziv smještaja'), (name) {
          offer.name = name;
          ui.changed();
        })..style.fontSize = '16px',
        el('div', cls: 'small', text: offerFacts(offer)),
      ]),
      el('div', cls: 'price offer-price', children: [
        el('div', cls: 'small', text: '${nightsCount(trip.nights)} · ${euros(offer.pricePerNight * trip.nights)} ${tr('ukupno')}'),
        el('div', children: [
          el('span', text: euros(offer.pricePerNight), attrs: {'style': 'font-size:18px'}),
          el('span', cls: 'small', text: ' ${tr('po noći')}'),
        ]),
      ]),
    ]),
    // The icons go to a line of their own when the chips leave no room.
    el('div', attrs: {'style': 'display:flex;flex-wrap:wrap;gap:8px;margin-top:8px;align-items:center'},
        children: [
      // Everyone may vote for any number of stays; only Rezervirano picks one.
      chip('${tr('Glasaj')} · ${offer.votes.length}', () {
        voted ? offer.votes.remove(me) : offer.votes.add(me);
        ui.changed();
      }, on: voted),
      chip(tr('Rezervirano'), () {
        offer.reserved ? _unreserve(ui, trip, offer) : _reserve(ui, trip, offer);
      }, on: offer.reserved),
      el('div', attrs: {'style': 'display:flex;align-items:center;margin-left:auto'}, children: [
        if (opener != null) opener,
        button(
          cls: editing ? 'icon-button brush-small on' : 'icon-button brush-small',
          ariaLabel: tr('Uredi smještaj'),
          onTap: () {
            ui.editingOffer = editing ? null : offer.id;
            ui.rerender();
          },
          children: [icon('brush', size: 20)],
        ),
      ]),
    ]),
    if (editing) _offerEdit(ui, offer),
  ]);
}

/// Where a pasted offer came from, by its address.
String _sourceOf(String link) {
  final text = link.toLowerCase();
  if (text.contains('booking.')) return 'Booking';
  if (text.contains('airbnb.')) return 'Airbnb';
  return link.isEmpty ? 'Ručno' : 'Link';
}

web.HTMLElement _addOffer(Ui ui, Trip trip) {
  final name = input();
  final price = numberInput();
  final rating = numberInput();
  final beach = numberInput();
  final link = input(type: 'url');
  final location = input(placeholder: tr('Adresa ili link s Google Mapsa'));
  final error = errorLine();
  link.onInput.listen((_) {
    final found = nameFromLink(link.value);
    if (found != null && name.value.trim().isEmpty) name.value = found;
  });

  void add() {
    final cents = parseEuros(price.value);
    final noName = name.value.trim().isEmpty;
    final noPrice = cents == null || cents == 0;
    // Only what is missing is asked for.
    if (noName || noPrice) {
      error.textContent = noName && noPrice
          ? tr('Upiši naziv i cijenu po noći.')
          : noName
              ? tr('Upiši naziv.')
              : tr('Upiši cijenu po noći.');
      return;
    }
    final stars = double.tryParse(rating.value.trim().replaceAll(',', '.'));
    if (rating.value.trim().isNotEmpty && (stars == null || stars < 0 || stars > 5)) {
      error.textContent = tr('Ocjena ide od 0 do 5.');
      return;
    }
    final address = link.value.trim();
    final place = location.value.trim();
    trip.offers.add(Offer(
      id: ui.store.newId(),
      name: name.value.trim(),
      pricePerNight: cents,
      rating: stars,
      beachMeters: int.tryParse(beach.value.trim()),
      source: _sourceOf(address),
      link: address.isEmpty ? null : address,
      location: place.isEmpty ? null : place,
    ));
    ui.changed();
  }

  return adder(tr('Dodaj ponudu'), [
    field(tr('Naziv'), name),
    field(tr('Link ponude'), link),
    field(tr('Lokacija'), location),
    field(tr('Do plaže (m)'), beach),
    el('div', cls: 'fields', children: [
      field(tr('Cijena po noći (€)'), price, tight: true),
      field(tr('Ocjena (0 do 5)'), rating, tight: true),
    ]),
    error,
    primaryButton(tr('Dodaj ponudu'), add),
  ]);
}

web.HTMLElement stayScreen(Ui ui, Trip trip) {
  final offers = sortOffersBy(trip.offers, ui.offerSorts);
  final best = offers.isEmpty ? null : recommendedOffer(offers, trip.people);
  return el('div', children: [
    topBar(tr('Smještaj')),
    el('div', cls: 'two', attrs: {'style': 'padding-top:0'}, children: [
      outLink(tr('Traži na Bookingu'), bookingSearch(trip)),
      outLink(tr('Traži na Airbnbu'), airbnbSearch(trip)),
    ]),
    if (offers.isEmpty)
      el('p', cls: 'soft pad gap-top',
          text: tr('Nađite ponude koje vam se sviđaju i dodajte ih ovdje, pa ih usporedite i glasajte.'))
    else ...[
      // Sortiraj offers what to sort by; each picked one shows with an x, the
      // first deciding most.
      el('div', cls: 'chips', children: [
        chip(tr('Sortiraj'), () {
          // Turning Sortiraj off takes every sort away.
          if (ui.sortOpen) ui.offerSorts.clear();
          ui.sortOpen = !ui.sortOpen;
          ui.rerender();
        }, on: ui.sortOpen),
        if (ui.sortOpen)
          for (final sort in OfferSort.values)
            if (!ui.offerSorts.contains(sort))
              chip('+ ${sort.label}', () {
                ui.offerSorts.add(sort);
                ui.rerender();
              }),
      ]),
      if (ui.offerSorts.isNotEmpty)
        el('div', cls: 'checks', attrs: {'style': 'margin-top:8px'}, children: [
          for (final sort in ui.offerSorts)
            button(
              cls: 'chip sort-chip',
              ariaLabel: tr('Makni: {0}', [sort.label]),
              onTap: () {
                ui.offerSorts.remove(sort);
                ui.rerender();
              },
              children: [icon('close', size: 11), web.document.createTextNode(sort.label)],
            ),
        ]),
      for (final offer in offers)
        _offerCard(ui, trip, offer, best: identical(offer, best)),
    ],
    _addOffer(ui, trip),
  ]);
}
