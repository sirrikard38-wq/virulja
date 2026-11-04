import 'attack.dart';
import 'models.dart';

/// Plan and reality of one kind of cost.
class BudgetLine {
  const BudgetLine(this.category, {required this.planned, required this.actual});

  final CostCategory category;
  final int planned;
  final int actual;
}

/// What a trip should cost and what it has cost so far at [now]. Something in
/// Plan napada whose day is over counts as spent, unless a real cost of the same
/// name was written down: then that one counts instead.
class Budget {
  Budget._(this.lines, this._people);

  factory Budget.of(Trip trip, [DateTime? now]) {
    final actual = {for (final category in CostCategory.values) category: 0};
    for (final expense in trip.expenses) {
      actual[expense.category] = actual[expense.category]! + expense.amount;
    }
    final written = {for (final expense in trip.expenses) _same(expense.title)};
    // A reserved stay is as good as paid.
    for (final offer in trip.offers) {
      if (offer.reserved && !written.contains(_same(offer.name))) {
        actual[CostCategory.stay] = actual[CostCategory.stay]! + offer.pricePerNight * trip.nights;
      }
    }
    for (final item in planOfAttack(trip, now ?? DateTime.now())) {
      if (item.happened && !written.contains(_same(item.title))) {
        actual[item.category] = actual[item.category]! + item.cost;
      }
    }
    return Budget._([
      for (final category in CostCategory.values)
        BudgetLine(
          category,
          planned: plannedCost(trip, category),
          actual: actual[category]!,
        ),
    ], trip.people);
  }

  final List<BudgetLine> lines;
  final int _people;

  int get plannedTotal => lines.fold(0, (sum, line) => sum + line.planned);

  int get actualTotal => lines.fold(0, (sum, line) => sum + line.actual);

  int get plannedPerPerson =>
      _people == 0 ? 0 : (plannedTotal / _people).round();

  BudgetLine line(CostCategory category) =>
      lines.firstWhere((line) => line.category == category);
}

String _same(String name) => name.trim().toLowerCase();

/// What those of [places] in Plan napada cost the whole group.
int plannedPlacesCost(Trip trip, Iterable<Place> places) => places
    .where((place) => placeInAttack(trip, place))
    .fold(0, (sum, place) => sum + (place.pricePerPerson ?? 0) * trip.people);

/// What the dishes to try cost.
int dishesCost(Trip trip) =>
    trip.dishes.fold(0, (sum, dish) => sum + dish.price * dish.servings);

/// The estimate for one [category]:
///  * stay: the chosen offer, every night;
///  * food: places in Plan napada for the whole group, plus the dishes to try;
///  * transport: the drive and every other leg of the journey;
///  * activities: everything with a price on the day plan.
int plannedCost(Trip trip, CostCategory category) {
  switch (category) {
    case CostCategory.stay:
      final reserved = trip.offers.where((offer) => offer.reserved);
      if (reserved.isNotEmpty) {
        return reserved.fold(0, (sum, offer) => sum + offer.pricePerNight * trip.nights);
      }
      return (trip.chosenOffer?.pricePerNight ?? 0) * trip.nights;
    case CostCategory.food:
      return plannedPlacesCost(trip, trip.places) + dishesCost(trip);
    case CostCategory.transport:
      return trip.legs.fold(trip.drive.totalCost, (sum, leg) => sum + leg.cost);
    case CostCategory.activities:
      return trip.stops.fold(0, (sum, stop) => sum + stop.cost);
    case CostCategory.other:
      return 0;
  }
}
