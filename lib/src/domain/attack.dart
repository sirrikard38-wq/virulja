import 'i18n.dart';
import 'models.dart';

/// One thing in the plan of attack: a stop of the plan, a place from Hrana i piće
/// or an active poll.
class NextUp {
  const NextUp(
    this.title, {
    required this.days,
    required this.dayVotes,
    this.time = '',
    this.detail,
    this.past = false,
    this.cost = 0,
    this.category = CostCategory.other,
    this.poll,
    this.stop,
    this.place,
  });

  final String title;

  /// The days the group agreed on, in order. A stop also has its own day.
  final List<int> days;

  /// Day -> who can go that day.
  final Map<int, Set<String>> dayVotes;

  /// `08:30`, or empty when the time does not matter.
  final String time;
  final String? detail;

  /// It has gone by: every day agreed on is over, or the whole trip is. It stays
  /// in the list, greyed out.
  final bool past;

  /// What it costs the whole group, and where that goes in Troškovi.
  final int cost;
  final CostCategory category;

  /// What it came from: one of these three.
  final Poll? poll;
  final Stop? stop;
  final Place? place;

  String get id => poll?.id ?? place?.id ?? stop!.id;

  /// It had a day and that day is over, so what it costs counts as spent.
  bool get happened => past && days.isNotEmpty;
}

final RegExp _clock = RegExp(r'^\d\d:\d\d$');

/// The answers of a plain yes or no poll.
const Set<String> yesOrNo = {'Da', 'Ne', 'Možda'};

/// Whether each person may give only one answer: on a place, and on any yes or no.
bool onlyOneAnswer(Poll poll) =>
    poll.single || poll.options.every((option) => yesOrNo.contains(option.time));

/// The days enough of the group can go, in order.
List<int> agreedDays(Trip trip, Map<int, Set<String>> votes) => [
      for (final day in votes.keys.toList()..sort())
        if (day >= 0 &&
            day < trip.dayCount &&
            trip.membersAmong(votes[day]!) >= trip.votesToAgree)
          day,
    ];

/// The answer enough of the group voted for: for a yes or no only a yes counts,
/// otherwise the one with most votes. Null while the group has not agreed.
PollOption? agreedOption(Trip trip, Poll poll) {
  final plain = poll.options.every((option) => yesOrNo.contains(option.time));
  PollOption? best;
  var most = 0;
  for (final option in poll.options) {
    if (plain && option.time != 'Da') continue;
    final votes = trip.membersAmong(option.votes);
    if (votes > most) {
      best = option;
      most = votes;
    }
  }
  return most >= trip.votesToAgree ? best : null;
}

/// The place of Hrana i piće a yes or no poll is about.
Place? placeOf(Trip trip, Poll poll) {
  if (!poll.single) return null;
  for (final place in trip.places) {
    if (place.name == poll.title) return place;
  }
  return null;
}

Dish? _dishOf(Trip trip, Poll poll) {
  if (!poll.single) return null;
  for (final dish in trip.dishes) {
    if (dish.name == poll.title) return dish;
  }
  return null;
}

bool _isAbout(Poll poll, Place place) => poll.single && poll.title == place.name;

/// Whether [place] is in Plan napada: put there from Hrana i piće or, in older
/// versions, through its poll.
bool placeInAttack(Trip trip, Place place) =>
    place.planned || trip.polls.any((poll) => poll.active && _isAbout(poll, place));

/// Puts [place] in Plan napada or takes it out, by [person].
void setPlaceInAttack(Trip trip, Place place, bool on, String person) {
  place
    ..planned = on
    ..plannedBy = on ? person : null;
  if (on) return;
  for (final poll in trip.polls) {
    if (_isAbout(poll, place)) {
      poll
        ..active = false
        ..activeBy = null;
    }
  }
}

/// Whether the result of [poll] is in Plan napada.
bool pollInAttack(Trip trip, Poll poll) {
  final place = placeOf(trip, poll);
  return place == null ? poll.active : placeInAttack(trip, place);
}

/// Puts the result of [poll] in Plan napada or takes it out. A poll on a place
/// moves the place itself, so that it is there once.
void setPollInAttack(Trip trip, Poll poll, bool on, String person) {
  final place = placeOf(trip, poll);
  if (place != null) {
    setPlaceInAttack(trip, place, on, person);
    return;
  }
  poll
    ..active = on
    ..activeBy = on ? person : null;
}

/// What [poll] shows in Plan napada: a time when it decided one, the answer
/// with most votes, or nothing for a yes or no.
({String time, String? detail}) _result(Poll poll) {
  if (poll.options.every((option) => yesOrNo.contains(option.time))) {
    return (time: '', detail: null);
  }
  PollOption? best;
  for (final option in poll.options) {
    if (option.votes.isNotEmpty &&
        (best == null || option.votes.length > best.votes.length)) {
      best = option;
    }
  }
  final choice = best?.time;
  if (choice == null) return (time: '', detail: tr('Još nema glasova'));
  return _clock.hasMatch(choice) ? (time: choice, detail: null) : (time: '', detail: choice);
}

/// Everything in Plan napada at [now]: what is still to come by its first day,
/// then what has no day yet, and at the end what has gone by.
List<NextUp> planOfAttack(Trip trip, DateTime now) {
  final day = today(now);
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  final clock = '$hour:$minute';
  final tripOver = remainingDays(trip, now).isEmpty;

  bool gone(int index, String time) {
    final date = trip.dayAt(index);
    if (date.isBefore(day)) return true;
    return !date.isAfter(day) && time.isNotEmpty && time.compareTo(clock) < 0;
  }

  NextUp item(
    String title,
    Map<int, Set<String>> votes, {
    String time = '',
    String? detail,
    int? ownDay,
    int cost = 0,
    CostCategory category = CostCategory.other,
    Poll? poll,
    Stop? stop,
    Place? place,
  }) {
    final days = {
      if (ownDay != null && ownDay >= 0 && ownDay < trip.dayCount) ownDay,
      ...agreedDays(trip, votes),
    }.toList()
      ..sort();
    return NextUp(
      title,
      days: days,
      dayVotes: votes,
      time: time,
      detail: detail,
      past: tripOver || (days.isNotEmpty && days.every((day) => gone(day, time))),
      cost: cost,
      category: category,
      poll: poll,
      stop: stop,
      place: place,
    );
  }

  NextUp fromPoll(Poll poll) {
    final shown = _result(poll);
    final dish = _dishOf(trip, poll);
    return item(poll.title, poll.dayVotes,
        time: shown.time,
        detail: shown.detail,
        // Older polls were made for a day.
        ownDay: poll.single ? null : poll.dayIndex,
        cost: dish == null ? 0 : dish.price * dish.servings,
        category: CostCategory.food,
        poll: poll);
  }

  final items = [
    for (final stop in trip.stops)
      if (!stop.hiddenInAttack)
        item(stop.title, stop.dayVotes,
            time: stop.time,
            ownDay: stop.dayIndex,
            cost: stop.cost,
            category: CostCategory.activities,
            stop: stop),
    for (final place in trip.places)
      if (placeInAttack(trip, place))
        item(place.name, place.dayVotes,
            cost: (place.pricePerPerson ?? 0) * trip.people,
            category: CostCategory.food,
            place: place),
    for (final poll in trip.polls)
      if (poll.active && placeOf(trip, poll) == null) fromPoll(poll),
  ];
  int first(NextUp item) => item.days.isEmpty ? trip.dayCount : item.days.first;
  return items
    ..sort((a, b) {
      if (a.past != b.past) return a.past ? 1 : -1;
      final days = first(a).compareTo(first(b));
      if (days != 0) return days;
      final times = a.time.compareTo(b.time);
      return times != 0 ? times : a.title.compareTo(b.title);
    });
}

/// The days of [trip] that have not gone by at [now].
List<int> remainingDays(Trip trip, DateTime now) => [
      for (var i = 0; i < trip.dayCount; i++)
        if (!trip.dayAt(i).isBefore(today(now))) i,
    ];
