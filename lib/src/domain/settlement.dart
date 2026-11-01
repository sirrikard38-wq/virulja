import 'models.dart';

/// What one person owes another.
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

/// Everything anyone owes anyone, each pair once: what their expenses and payments
/// leave between the two of them. Debts in both directions cancel out.
List<Transfer> debts(Trip trip) {
  final owes = <String, Map<String, int>>{};
  void add(String from, String to, int amount) {
    (owes[from] ??= {}).update(to, (sum) => sum + amount, ifAbsent: () => amount);
    (owes[to] ??= {}).update(from, (sum) => sum - amount, ifAbsent: () => -amount);
  }

  for (final expense in trip.expenses) {
    splitEqually(expense.amount, expense.sharedBy).forEach((id, share) {
      if (id != expense.payerId) add(id, expense.payerId, share);
    });
  }
  for (final payment in trip.payments) {
    add(payment.toId, payment.fromId, payment.amount);
  }
  final people = {...trip.memberIds, ...owes.keys};
  return [
    for (final from in people)
      for (final to in people)
        if ((owes[from]?[to] ?? 0) > 0)
          Transfer(fromId: from, toId: to, amount: owes[from]![to]!),
  ];
}
