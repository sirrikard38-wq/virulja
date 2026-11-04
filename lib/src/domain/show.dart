import 'dart:math';

import 'models.dart';

/// The whole bar of a transition's lengthening, and the part of it open from
/// the start: half.
const double longestExtra = 12;
const double firstExtra = 6;

/// Transitions there are from the start; the others open as the trip goes on.
const int firstTransitions = 5;

/// Seconds a transition takes before it is made longer, and then how long the
/// photo stands still.
const double transitionTime = 1;
const double stillTime = 2.5;

double _hundredths(double value) => (value * 100).round() / 100;

/// How much a transition can be made longer on [now]: 6 s up to the first day of
/// the trip. Each later day adds what is left up to 12 s divided by the days left,
/// that one included, in hundredths, so the last day reaches 12 s.
double extraLimit(Trip trip, DateTime now) {
  final day = today(now).difference(trip.start).inDays;
  if (day <= 0) return firstExtra;
  if (day >= trip.dayCount - 1) return longestExtra;
  var limit = firstExtra;
  for (var passed = 1; passed <= day; passed++) {
    limit = _hundredths(limit + _hundredths((longestExtra - limit) / (trip.dayCount - passed)));
  }
  return min(limit, longestExtra);
}

/// How many transitions can be used on [now]: five at first and all of them on
/// the last day, in step with [extraLimit].
int openTransitions(Trip trip, DateTime now) {
  final share = (extraLimit(trip, now) - firstExtra) / (longestExtra - firstExtra);
  final later = Transition.values.length - firstTransitions;
  return firstTransitions + (share * later + 1e-9).floor();
}

/// One photo of a presentation and the way it comes in.
typedef Slide = ({String photoId, Look look});

/// The photos of [show] in the order they were taken: every photo of the trip,
/// not videos and not those left out.
List<Slide> slidesOf(Trip trip, Show show) {
  final photos = trip.photos
      .where((photo) => !photo.isVideo && !show.leftOut.contains(photo.id))
      .toList()
    ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  return [
    for (final photo in photos) (photoId: photo.id, look: show.looks[photo.id] ?? show.look),
  ];
}

/// How long one photo takes: its transition, then standing still.
double slideLength(Look look) => transitionTime + look.extra + stillTime;

/// Seconds from the start of [slides] to the photo at [index].
double secondsBefore(List<Slide> slides, int index) => slides
    .take(index)
    .fold(0.0, (sum, slide) => sum + slideLength(slide.look));

/// Where a presentation is after [seconds], going round and round: which photo,
/// the one it comes after, and how far its transition has come, from 0 to 1. The
/// very first photo comes after none.
({int index, int? previous, double progress}) frameAt(List<Slide> slides, double seconds) {
  if (slides.isEmpty) return (index: 0, previous: null, progress: 1);
  final round = secondsBefore(slides, slides.length);
  var left = seconds % round;
  for (var i = 0; i < slides.length; i++) {
    final look = slides[i].look;
    if (left < slideLength(look) || i == slides.length - 1) {
      final first = i == 0 && seconds < round;
      return (
        index: i,
        previous: first ? null : (i - 1 + slides.length) % slides.length,
        progress: min(1.0, left / (transitionTime + look.extra)),
      );
    }
    left -= slideLength(look);
  }
  return (index: 0, previous: null, progress: 1);
}

/// The presentation [person] made, if any: each makes one at most.
Show? showBy(Trip trip, String person) {
  for (final show in trip.shows) {
    if (show.addedBy == person) return show;
  }
  return null;
}

/// How many of the group have [show] on their screens.
int picksOf(Trip trip, Show show) =>
    trip.memberIds.where((person) => trip.showPicks[person] == show.id).length;

/// The presentation most of the group have on their screens: the presentation of
/// the day. Of equals the newest wins. Null while nobody has picked one.
Show? showOfTheDay(Trip trip) {
  Show? best;
  var most = 0;
  for (final show in trip.shows) {
    final picks = picksOf(trip, show);
    if (picks > 0 && picks >= most) {
      best = show;
      most = picks;
    }
  }
  return best;
}

/// What plays on the screen of [person]: the presentation they picked, or else
/// the presentation of the day.
Show? shownTo(Trip trip, String person) {
  final picked = trip.showPicks[person];
  for (final show in trip.shows) {
    if (show.id == picked) return show;
  }
  return showOfTheDay(trip);
}
