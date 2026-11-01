import 'package:web/web.dart' as web;

import '../src/domain/budget.dart';
import '../src/domain/format.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import '../src/domain/offers.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

web.HTMLElement _offerCard(Ui ui, Trip trip, Offer offer, {required bool best}) {
  final me = ui.meIn(trip);
  final voted = offer.votes.contains(me);
  final chosen = trip.chosenOfferId == offer.id;
  final link = offer.link;
  return el('div', cls: 'card', attrs: {
    'style': 'margin:10px 20px 0;padding:10px 12px',
  }, children: [
    el('div', attrs: {'style': 'display:flex;justify-content:space-between;gap:12px'},
        children: [
      el('div', cls: 'grow', children: [
        if (best) el('span', cls: 'badge', text: 'Preporuka'),
        el('div', cls: 'label', text: offer.name, attrs: {'style': 'font-size:16px'}),
        el('div', cls: 'small', text: offerFacts(offer)),
      ]),
      el('div', cls: 'price', children: [
        el('div', text: euros(offer.pricePerNight), attrs: {'style': 'font-size:18px'}),
        el('div', cls: 'small', text: 'po noći'),
      ]),
    ]),
    el('div', attrs: {'style': 'display:flex;gap:8px;margin-top:8px;align-items:center'},
        children: [
      button(
        cls: voted ? 'chip on' : 'chip',
        ariaLabel: 'Glasaj za ${offer.name}, ${offer.votes.length}',
        onTap: () {
          voted ? offer.votes.remove(me) : offer.votes.add(me);
          ui.changed();
        },
        children: [
          icon('thumb', size: 18),
          web.document.createTextNode('${offer.votes.length}'),
        ],
      ),
      chip(chosen ? 'Odabrano' : 'Odaberi', () {
        trip.chosenOfferId = chosen ? null : offer.id;
        ui.changed();
      }, on: chosen),
      el('span', cls: 'grow'),
      if (link != null) linkIcon(link, 'Otvori ponudu'),
      removeButton(offer.name, () {
        trip.offers.remove(offer);
        if (chosen) trip.chosenOfferId = null;
        ui.changed();
      }),
    ]),
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
  final name = input(placeholder: 'Kuća Mare');
  final price = numberInput(placeholder: '186');
  final rating = numberInput(placeholder: '4,8');
  final beach = numberInput(placeholder: '300');
  final link = input(type: 'url', placeholder: 'https://');
  final error = errorLine();

  void add() {
    final cents = parseEuros(price.value);
    if (name.value.trim().isEmpty || cents == null || cents == 0) {
      error.textContent = 'Upiši naziv i cijenu po noći.';
      return;
    }
    final stars = double.tryParse(rating.value.trim().replaceAll(',', '.'));
    if (rating.value.trim().isNotEmpty && (stars == null || stars < 0 || stars > 5)) {
      error.textContent = 'Ocjena ide od 0 do 5.';
      return;
    }
    final address = link.value.trim();
    trip.offers.add(Offer(
      id: ui.store.newId(),
      name: name.value.trim(),
      pricePerNight: cents,
      rating: stars,
      beachMeters: int.tryParse(beach.value.trim()),
      source: _sourceOf(address),
      link: address.isEmpty ? null : address,
    ));
    ui.changed();
  }

  return adder('Dodaj ponudu', [
    field('Naziv', name),
    el('div', cls: 'fields', children: [
      field('Cijena po noći (€)', price, tight: true),
      field('Ocjena (0 do 5)', rating, tight: true),
    ]),
    el('div', cls: 'fields', children: [
      field('Do plaže (m)', beach, tight: true),
      field('Link ponude', link, tight: true),
    ]),
    error,
    primaryButton('Dodaj ponudu', add),
  ]);
}

web.HTMLElement stayScreen(Ui ui, Trip trip) {
  final offers = sortOffers(trip.offers, ui.offerSort);
  final best = offers.isEmpty ? null : recommendedOffer(offers, trip.people);
  return el('div', children: [
    topBar('Smještaj'),
    el('div', cls: 'two', attrs: {'style': 'padding-top:0'}, children: [
      outLink('Traži na Bookingu', bookingSearch(trip)),
      outLink('Traži na Airbnbu', airbnbSearch(trip)),
    ]),
    if (offers.isEmpty)
      el('p', cls: 'soft pad gap-top',
          text: 'Nađite ponude koje vam se sviđaju i dodajte ih ovdje, '
              'pa ih usporedite i glasajte.')
    else ...[
      el('div', cls: 'chips', children: [
        for (final sort in OfferSort.values)
          chip(sort.label, () {
            ui.offerSort = sort;
            ui.rerender();
          }, on: ui.offerSort == sort),
      ]),
      for (final offer in offers)
        _offerCard(ui, trip, offer, best: identical(offer, best)),
      if (trip.chosenOffer != null)
        el('p', cls: 'soft pad gap-top', text: '${nightsCount(trip.nights)} · '
            '${euros(plannedCost(trip, CostCategory.stay))} ukupno'),
    ],
    _addOffer(ui, trip),
  ]);
}
