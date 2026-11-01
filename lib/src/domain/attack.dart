import 'models.dart';

/// One thing in the plan of attack: a stop of the plan or an active poll.
class NextUp {
  const NextUp(
    this.dayIndex,
    this.time,
    this.title, {
    this.detail,
    this.past = false,
    this.poll,
    this.stop,
  });

  final int dayIndex;

  /// `08:30`, or empty when the time does not matter.
  final String time;
  final String title;
  final String? detail;

  /// It has gone by; it stays in the list, greyed out.
  final bool past;

  /// What it came from: one of these two.
  final Poll? poll;
  final Stop? stop;

  NextUp asPast() => NextUp(dayIndex, time, title,
      detail: detail, past: true, poll: poll, stop: stop);
}

final RegExp _clock = RegExp(r'^\d\d:\d\d$');

NextUp _result(Poll poll) {
  final day = poll.plannedDay;
  // A yes or no about a place: its result says nothing worth showing here.
  if (poll.single) return NextUp(day, '', poll.title, poll: poll);
  PollOption? best;
  for (final option in poll.options) {
    if (option.votes.isNotEmpty &&
        (best == null || option.votes.length > best.votes.length)) {
      best = option;
    }
  }
  final choice = best?.time;
  if (choice == null) {
    return NextUp(day, '', poll.title, detail: 'Još nema glasova', poll: poll);
  }
  return _clock.hasMatch(choice)
      ? NextUp(day, choice, poll.title, poll: poll)
      : NextUp(day, '', poll.title, detail: choice, poll: poll);
}

/// The plan's stops and the active polls' results: what is still to come in
/// order, the next one first, then what has gone by at [now].
List<NextUp> planOfAttack(Trip trip, DateTime now) {
  final day = today(now);
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  final clock = '$hour:$minute';

  bool gone(NextUp item) {
    final date = trip.dayAt(item.dayIndex);
    if (date.isBefore(day)) return true;
    return !date.isAfter(day) && item.time.isNotEmpty && item.time.compareTo(clock) < 0;
  }

  final items = [
    for (final stop in trip.stops)
      if (!stop.hiddenInAttack) NextUp(stop.dayIndex, stop.time, stop.title, stop: stop),
    for (final poll in trip.polls)
      if (poll.active) _result(poll),
  ].map((item) => gone(item) ? item.asPast() : item).toList()
    ..sort((a, b) {
      if (a.past != b.past) return a.past ? 1 : -1;
      final days = a.dayIndex.compareTo(b.dayIndex);
      return days != 0 ? days : a.time.compareTo(b.time);
    });
  return items;
}

/// The days of [trip] that have not gone by at [now].
List<int> remainingDays(Trip trip, DateTime now) => [
      for (var i = 0; i < trip.dayCount; i++)
        if (!trip.dayAt(i).isBefore(today(now))) i,
    ];
