import 'i18n.dart';
import 'models.dart';

/// What the stays can be sorted by, in the order Sortiraj offers them.
enum OfferSort {
  votes('Glasovi'),
  price('Cijena'),
  rating('Ocjena'),
  beach('Blizina plaže');

  const OfferSort(this._label);

  final String _label;

  String get label => tr(_label);
}

/// A copy of [offers] in the order of [sort]. Offers without the value being
/// compared go last.
List<Offer> sortOffers(List<Offer> offers, OfferSort sort) => sortOffersBy(offers, [sort]);

/// A copy of [offers] ordered by each of [sorts] in turn: the first decides, the
/// next only between equals, and so on. With none they stay as they were added.
List<Offer> sortOffersBy(List<Offer> offers, List<OfferSort> sorts) {
  int compareMissingLast(num? a, num? b, {bool ascending = true}) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return ascending ? a.compareTo(b) : b.compareTo(a);
  }

  double? share(Offer offer) => switch (offer.rating) {
        final stars? => stars / ratingOutOf(offer.link),
        _ => null,
      };

  int by(OfferSort sort, Offer a, Offer b) => switch (sort) {
        OfferSort.price => a.pricePerNight.compareTo(b.pricePerNight),
        OfferSort.rating => compareMissingLast(share(a), share(b), ascending: false),
        OfferSort.beach => compareMissingLast(a.beachMeters, b.beachMeters),
        OfferSort.votes => b.votes.length.compareTo(a.votes.length),
      };

  final places = {for (var i = 0; i < offers.length; i++) offers[i]: i};
  return offers.toList()
    ..sort((a, b) {
      for (final sort in sorts) {
        final order = by(sort, a, b);
        if (order != 0) return order;
      }
      return places[a]!.compareTo(places[b]!);
    });
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
    rating: (offer.rating ?? 0) / ratingOutOf(offer.link),
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
/// What a stay's rating is out of: Booking rates out of 10, the rest out of 5.
int ratingOutOf(String? link) => (link ?? '').toLowerCase().contains('booking.') ? 10 : 5;
