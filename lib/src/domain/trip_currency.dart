import 'currency.dart';
import 'models.dart';

/// Changes [trip]'s currency to [to] and converts every amount written in it
/// at [perEuro] (units per euro): prices, costs, payments, plans. False, with
/// nothing changed, when a rate is not known.
bool changeTripCurrency(Trip trip, String to, Map<String, double> perEuro) {
  final from = trip.currencies.first;
  if (from == to) return true;
  if (convert(100, from, to, perEuro) == null) return false;
  int c(int cents) => convert(cents, from, to, perEuro)!;
  int? maybe(int? cents) => cents == null ? null : c(cents);

  for (final offer in trip.offers) {
    offer.pricePerNight = c(offer.pricePerNight);
  }
  for (final place in trip.places) {
    place
      ..pricePerPerson = maybe(place.pricePerPerson)
      ..priceLow = maybe(place.priceLow)
      ..priceHigh = maybe(place.priceHigh);
  }
  for (final dish in trip.dishes) {
    dish.price = c(dish.price);
  }
  for (final stop in trip.stops) {
    stop.cost = c(stop.cost);
  }
  for (final leg in trip.legs) {
    leg.cost = c(leg.cost);
    final drive = leg.drive;
    if (drive != null) {
      drive
        ..fuelPrice = c(drive.fuelPrice)
        ..tolls = c(drive.tolls)
        ..ferry = c(drive.ferry)
        ..extra = c(drive.extra);
      if (drive.fuel case final paid?) drive.fuel = c(paid);
    }
  }
  trip.drive
    ..fuelPrice = c(trip.drive.fuelPrice)
    ..tolls = c(trip.drive.tolls)
    ..ferry = c(trip.drive.ferry);
  for (final expense in trip.expenses) {
    expense.amount = c(expense.amount);
  }
  trip.payments = [
    for (final payment in trip.payments)
      Payment(id: payment.id, fromId: payment.fromId, toId: payment.toId, amount: c(payment.amount)),
  ];
  trip.budgets = trip.budgets.map((key, cents) => MapEntry(key, c(cents)));
  trip.currencies = [to];
  return true;
}
