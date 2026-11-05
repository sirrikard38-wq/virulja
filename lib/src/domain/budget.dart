import 'attack.dart';
import 'models.dart';

/// Plan and reality of one kind of cost.
class BudgetLine {
  const BudgetLine(this.category, {required this.planned, required this.actual, this.estimate = 0});

  final CostCategory category;

  /// Planirano: what the group planned to spend, per person times everyone.
  final int planned;

  /// Potrošeno.
  final int actual;

  /// The app's own estimate, from what was chosen and voted (see [plannedCost]).
  final int estimate;

  /// What the plan leaves, never below nothing.
  int get ahead => planned > actual ? planned - actual : 0;
}

/// Places of Hrana i piće in Plan napada whose day has come and whose real cost
/// is not written yet: Troškovi asks to split each.
List<Place> toSplit(Trip trip, [DateTime? now]) {
  final day = today(now).difference(trip.start).inDays;
  final written = {for (final cost in trip.expenses) _same(cost.title)};
  return [
    for (final item in planOfAttack(trip, now ?? DateTime.now()))
      if (item.place case final place?)
        if (item.days.isNotEmpty &&
            item.days.first <= day &&
            !trip.expenses.any((cost) => cost.id == place.expenseId) &&
            !written.contains(_same(place.name)))
          place,
  ];
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
      final booked = trip.expenses.any((cost) => cost.id == offer.expenseId);
      if (offer.reserved && !booked && !written.contains(_same(offer.name))) {
        actual[CostCategory.stay] = actual[CostCategory.stay]! + offer.pricePerNight * trip.nights;
      }
    }
    final plan = planOfAttack(trip, now ?? DateTime.now());
    for (final item in plan) {
      if (item.happened && !written.contains(_same(item.title))) {
        actual[item.category] = actual[item.category]! + item.cost;
      }
    }
    return Budget._([
      for (final category in CostCategory.values)
        // Planirano is only what the group planned, per person, for everyone;
        // the app's estimate stands apart and is never added to it.
        BudgetLine(
          category,
          planned: (setBudget(trip, category) ?? 0) * trip.people,
          actual: actual[category]!,
          estimate: plannedCost(trip, category),
        ),
    ], trip.people);
  }

  final List<BudgetLine> lines;
  final int _people;

  int get plannedTotal => lines.fold(0, (sum, line) => sum + line.planned);

  int get actualTotal => lines.fold(0, (sum, line) => sum + line.actual);

  int get aheadTotal => lines.fold(0, (sum, line) => sum + line.ahead);

  /// What the trip has really cost [person]: their part of each written cost
  /// they share, nothing planned.
  static int shareOf(Trip trip, String person) {
    var share = 0.0;
    for (final cost in trip.expenses) {
      if (cost.sharedBy.contains(person)) share += cost.amount / cost.sharedBy.length;
    }
    return share.round();
  }

  int get plannedPerPerson =>
      _people == 0 ? 0 : (plannedTotal / _people).round();

  BudgetLine line(CostCategory category) =>
      lines.firstWhere((line) => line.category == category);
}

String _same(String name) => name.trim().toLowerCase();

/// The key of the dishes among the categories of Hrana i piće.
const String dishesKind = 'dishes';

/// Where Planirani trošak of one category of Hrana i piće is kept in
/// `Trip.budgets`. A database key cannot have a slash.
String foodBudgetKey(String kind) => 'food:$kind';

/// The categories of Hrana i piće that can cost something: the dishes, the
/// app's own kinds of place, the group's own, and any a place still names.
Set<String> foodKinds(Trip trip) => {
      dishesKind,
      for (final kind in PlaceKind.values) kind.name,
      for (final custom in trip.customKinds) custom.id,
      for (final place in trip.places) place.customKindId ?? place.kind.name,
    };

/// The app's estimate for one category of Hrana i piće: its places in Plan
/// napada for the whole group, or the dishes to try.
int foodKindCost(Trip trip, String kind) => kind == dishesKind
    ? dishesCost(trip)
    : plannedPlacesCost(trip, trip.places.where((place) => (place.customKindId ?? place.kind.name) == kind));

/// What the group planned per person for [category] with Planirani trošak po
/// osobi, or null. Food is planned per category of Hrana i piće, and is the
/// sum of those planned; one with nothing planned adds nothing.
int? setBudget(Trip trip, CostCategory category) {
  if (category != CostCategory.food) return trip.budgets[category.name];
  final parts = [
    for (final entry in trip.budgets.entries)
      if (entry.key.startsWith('food:')) entry.value,
  ];
  if (parts.isEmpty) return trip.budgets['food'];
  return parts.fold<int>(0, (sum, cents) => sum + cents);
}

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
///  * activities: everything with a price on the day plan;
///  * shop: what was bought.
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
    case CostCategory.shop:
      // Nothing is planned for the shop: what was bought is the plan.
      return trip.expenses
          .where((cost) => cost.category == CostCategory.shop)
          .fold(0, (sum, cost) => sum + cost.amount);
    case CostCategory.other:
      return 0;
  }
}
