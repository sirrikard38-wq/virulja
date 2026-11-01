import 'models.dart';

/// One thing still to come: a stop of the plan or the result of a poll.
class NextUp {
  const NextUp(this.dayIndex, this.time, this.title, this.detail);

  final int dayIndex;

  /// `08:30`, or empty when the time does not matter.
  final String time;
  final String title;
  final String? detail;
}

final RegExp _clock = RegExp(r'^\d\d:\d\d$');

NextUp _result(Poll poll) {
  PollOption? best;
  for (final option in poll.options) {
    if (option.votes.isNotEmpty &&
        (best == null || option.votes.length > best.votes.length)) {
      best = option;
    }
  }
  final choice = best?.time;
  if (choice == null) {
    return NextUp(poll.dayIndex, '', poll.title, 'Još nema glasova');
  }
  return _clock.hasMatch(choice)
      ? NextUp(poll.dayIndex, choice, poll.title, null)
      : NextUp(poll.dayIndex, '', poll.title, choice);
}

/// The plan's stops and the active polls' results that have not passed at
/// [now], the next one first.
List<NextUp> planOfAttack(Trip trip, DateTime now) {
  final day = today(now);
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  final clock = '$hour:$minute';
  final items = [
    for (final stop in trip.stops)
      NextUp(stop.dayIndex, stop.time, stop.title, null),
    for (final poll in trip.polls)
      if (poll.active) _result(poll),
  ].where((item) {
    final date = trip.dayAt(item.dayIndex);
    if (date.isBefore(day)) return false;
    return date.isAfter(day) || item.time.isEmpty || item.time.compareTo(clock) >= 0;
  }).toList()
    ..sort((a, b) {
      final days = a.dayIndex.compareTo(b.dayIndex);
      return days != 0 ? days : a.time.compareTo(b.time);
    });
  return items;
}
