import 'models.dart';

/// One payment that evens out the group.
class Transfer {
  const Transfer({required this.fromId, required this.toId, required this.amount});

  final String fromId;
  final String toId;
  final int amount;
}

/// Splits [amount] between [sharers]. The cents that do not divide evenly go to
/// the first people, so the parts always add up to [amount].
Map<String, int> splitEqually(int amount, List<String> sharers) {
  final base = amount ~/ sharers.length;
  final extra = amount - base * sharers.length;
  return {
    for (var i = 0; i < sharers.length; i++)
      sharers[i]: base + (i < extra ? 1 : 0),
  };
}

/// What each person is owed (positive) or owes (negative), after all expenses
/// and all payments so far. The numbers always add up to zero.
Map<String, int> balances(Trip trip) {
  final result = {for (final id in trip.memberIds) id: 0};
  void add(String id, int amount) => result[id] = (result[id] ?? 0) + amount;

  for (final expense in trip.expenses) {
    add(expense.payerId, expense.amount);
    splitEqually(expense.amount, expense.sharedBy)
        .forEach((id, share) => add(id, -share));
  }
  for (final payment in trip.payments) {
    add(payment.fromId, payment.amount);
    add(payment.toId, -payment.amount);
  }
  return result;
}

/// The few payments that bring every balance to zero: the one who owes the most
/// pays the one who is owed the most, until nobody owes anything.
List<Transfer> settle(Map<String, int> balances) {
  final order = balances.keys.toList();
  final left = Map.of(balances);
  final transfers = <Transfer>[];

  String? largest(bool Function(int) wanted) {
    String? best;
    for (final id in order) {
      if (!wanted(left[id]!)) continue;
      if (best == null || left[id]!.abs() > left[best]!.abs()) best = id;
    }
    return best;
  }

  while (true) {
    final debtor = largest((amount) => amount < 0);
    final creditor = largest((amount) => amount > 0);
    if (debtor == null || creditor == null) return transfers;
    final amount = (-left[debtor]!) < left[creditor]!
        ? -left[debtor]!
        : left[creditor]!;
    transfers.add(Transfer(fromId: debtor, toId: creditor, amount: amount));
    left[debtor] = left[debtor]! + amount;
    left[creditor] = left[creditor]! - amount;
  }
}
