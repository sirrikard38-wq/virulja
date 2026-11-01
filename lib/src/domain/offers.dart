import 'i18n.dart';
import 'models.dart';

enum OfferSort {
  price('Cijena'),
  rating('Ocjena'),
  beach('Blizina plaže'),
  votes('Glasovi');

  const OfferSort(this._label);

  final String _label;

  String get label => tr(_label);
}

/// A copy of [offers] in the order of [sort]. Offers without the value being
/// compared go last.
List<Offer> sortOffers(List<Offer> offers, OfferSort sort) {
  int compareMissingLast(num? a, num? b, {bool ascending = true}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return ascending ? a.compareTo(b) : b.compareTo(a);
  }

  final sorted = offers.toList();
  switch (sort) {
    case OfferSort.price:
      sorted.sort((a, b) => a.pricePerNight.compareTo(b.pricePerNight));
    case OfferSort.rating:
      sorted.sort(
          (a, b) => compareMissingLast(a.rating, b.rating, ascending: false));
    case OfferSort.beach:
      sorted.sort((a, b) => compareMissingLast(a.beachMeters, b.beachMeters));
    case OfferSort.votes:
      sorted.sort((a, b) => b.votes.length.compareTo(a.votes.length));
  }
  return sorted;
}

/// How one offer compares with the others. Every number runs from 0 (worst) to
/// 1 (best), so they can be weighed against each other.
class OfferFacts {
  const OfferFacts({
    required this.price,
    required this.rating,
    required this.beach,
    required this.votes,
  });

  /// 1 for the cheapest offer, less the more expensive it is.
  final double price;

  /// The rating out of 5; 0 when the offer has none.
  final double rating;

  /// 1 for the offer nearest the beach; 0 when the distance is unknown.
  final double beach;

  /// The share of the group that voted for it.
  final double votes;
}

OfferFacts factsFor(Offer offer, List<Offer> all, int groupSize) {
  final cheapest =
      all.map((item) => item.pricePerNight).reduce((a, b) => a < b ? a : b);
  final distances = all.map((item) => item.beachMeters).whereType<int>();
  final nearest =
      distances.isEmpty ? null : distances.reduce((a, b) => a < b ? a : b);
  final beachMeters = offer.beachMeters;
  return OfferFacts(
    price: offer.pricePerNight == 0 ? 0 : cheapest / offer.pricePerNight,
    rating: (offer.rating ?? 0) / 5,
    beach: beachMeters == null || nearest == null
        ? 0
        : (nearest + 50) / (beachMeters + 50),
    votes: groupSize == 0 ? 0 : offer.votes.length / groupSize,
  );
}

/// How good an offer is for this group; the highest score gets the
/// "Preporuka" mark on the accommodation screen. 0 means no mark at all.
double offerScore(OfferFacts facts) {
  // TODO(human): decide how much each thing matters to your group.
  return 0;
}

/// The offer with the best [offerScore], if any offer scores above zero.
Offer? recommendedOffer(List<Offer> offers, int groupSize) {
  Offer? best;
  var bestScore = 0.0;
  for (final offer in offers) {
    final score = offerScore(factsFor(offer, offers, groupSize));
    if (score > bestScore) {
      best = offer;
      bestScore = score;
    }
  }
  return best;
}
