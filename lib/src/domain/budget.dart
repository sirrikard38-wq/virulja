import 'models.dart';

/// Plan and reality of one kind of cost.
class BudgetLine {
  const BudgetLine(this.category, {required this.planned, required this.actual});

  final CostCategory category;
  final int planned;
  final int actual;
}

/// What a trip should cost and what it has cost so far.
class Budget {
  Budget._(this.lines, this._people);

  factory Budget.of(Trip trip) {
    final actual = {for (final category in CostCategory.values) category: 0};
    for (final expense in trip.expenses) {
      actual[expense.category] = actual[expense.category]! + expense.amount;
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

/// The estimate for one [category]:
///  * stay: the chosen offer, every night;
///  * food: planned places for the whole group, plus the dishes to try;
///  * transport: the drive and every other leg of the journey;
///  * activities: everything with a price on the day plan.
int plannedCost(Trip trip, CostCategory category) {
  switch (category) {
    case CostCategory.stay:
      return (trip.chosenOffer?.pricePerNight ?? 0) * trip.nights;
    case CostCategory.food:
      final places = trip.places.where((place) => place.planned).fold(
          0, (sum, place) => sum + (place.pricePerPerson ?? 0) * trip.people);
      final dishes = trip.dishes
          .fold(0, (sum, dish) => sum + dish.price * dish.servings);
      return places + dishes;
    case CostCategory.transport:
      return trip.legs.fold(trip.drive.totalCost, (sum, leg) => sum + leg.cost);
    case CostCategory.activities:
      return trip.stops.fold(0, (sum, stop) => sum + stop.cost);
    case CostCategory.other:
      return 0;
  }
}
