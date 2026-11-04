import 'dart:math';

import 'format.dart';
import 'i18n.dart';
import 'models.dart';

/// The whole bar of a transition's lengthening, and the part of it open from
/// the start: half.
const double longestExtra = 12;
const double firstExtra = 6;

/// Transitions there are from the start; the others open as the trip goes on.
const int firstTransitions = 5;

/// Seconds a transition takes before it is made longer.
const double transitionTime = 1;

/// The shortest time a photo may stand still. How long it can stand grows with
/// the days like the lengthening of a transition, up to 12 s.
const double leastStill = .5;

/// How many presentations each person may make.
const int showsEach = 3;

/// A presentation may show this much of every 30 seconds of a video.
const double clipPer30 = 6;

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

/// The most each day of the trip opens, from the first to the last: the marks
/// on the bars of a presentation.
List<double> dayLimits(Trip trip) => [
      for (var day = 0; day < trip.dayCount; day++)
        extraLimit(trip, trip.start.add(Duration(days: day))),
    ];

/// The fifteen transitions that open with the days, without Ništa.
final List<Transition> effects = [
  for (final transition in Transition.values)
    if (transition != Transition.none) transition,
];

/// How many of [effects] can be used on [now]: five at first and all of them on
/// the last day, in step with [extraLimit].
int openTransitions(Trip trip, DateTime now) {
  final share = (extraLimit(trip, now) - firstExtra) / (longestExtra - firstExtra);
  final later = effects.length - firstTransitions;
  return firstTransitions + (share * later + 1e-9).floor();
}

/// One photo or video of a presentation and the way it comes in. [video] is how
/// long a video is; null for a photo.
typedef Slide = ({String photoId, Look look, double? video});

/// How long a video of [seconds] is when its length is not known: the most the
/// app keeps.
const double _keptVideo = 30;

/// The longest piece of a video of [seconds] a presentation may show: 6 s of
/// every 30 s it lasts.
double longestClip(double seconds) =>
    min(seconds, clipPer30 * max(1, (seconds / 30 - 1e-9).ceil()));

/// The piece of the video [slide] plays: where it starts and how long it is.
({double from, double length}) clipOf(Slide slide) {
  final video = slide.video ?? 0;
  final length = min(slide.look.length, longestClip(video));
  return (from: slide.look.from.clamp(0, max(0.0, video - length)).toDouble(), length: length);
}

/// How long [video] is, or the most the app keeps when that is not known.
double videoLength(Photo video) => video.seconds ?? _keptVideo;

/// The heading of [day] of Uspomene: before the trip, a day of it, or after.
String photoDayTitle(Trip trip, int day) {
  if (day < 0) return tr('Prije puta');
  if (day >= trip.dayCount) return tr('Poslije puta');
  return tr('{0} Dan · {1}', [day + 1, weekdayAndDate(trip.dayAt(day))]);
}

/// The photos and videos of [trip] by day, and in each day as they were taken.
List<Photo> photosByDay(Trip trip) => trip.photos.toList()
  ..sort((a, b) {
    final days = trip.photoDay(a).compareTo(trip.photoDay(b));
    return days != 0 ? days : a.takenAt.compareTo(b.takenAt);
  });

/// The photos and videos of [show] in its order. One made before photos were
/// picked one by one has everything in Uspomene but what is left out.
List<Slide> slidesOf(Trip trip, Show show) {
  final chosen = show.chosen;
  final List<Photo> photos;
  if (chosen == null) {
    photos = photosByDay(trip).where((photo) => !show.leftOut.contains(photo.id)).toList();
  } else {
    final byId = {for (final photo in trip.photos) photo.id: photo};
    photos = [for (final id in chosen) if (byId[id] != null) byId[id]!];
  }
  return [
    for (final photo in photos)
      (
        photoId: photo.id,
        look: show.looks[photo.id] ?? show.look,
        video: photo.isVideo ? videoLength(photo) : null,
      ),
  ];
}

/// Seconds [look] takes to come in: none for Ništa, which cuts at once.
double movingTime(Look look) =>
    look.transition == Transition.none ? 0 : transitionTime + look.extra;

/// How long one photo or video takes: its transition, then a photo stands still
/// and a video plays its piece.
double slideLength(Slide slide) =>
    movingTime(slide.look) + (slide.video == null ? slide.look.still : clipOf(slide).length);

/// Seconds from the start of [slides] to the one at [index].
double secondsBefore(List<Slide> slides, int index) =>
    slides.take(index).fold(0.0, (sum, slide) => sum + slideLength(slide));

/// Where a presentation is after [seconds], going round and round: which photo,
/// the one it comes after, how far its transition has come, from 0 to 1, and how
/// many seconds of it have gone. The very first photo comes after none.
({int index, int? previous, double progress, double into}) frameAt(
  List<Slide> slides,
  double seconds,
) {
  if (slides.isEmpty) return (index: 0, previous: null, progress: 1, into: 0);
  final round = secondsBefore(slides, slides.length);
  var left = seconds % round;
  for (var i = 0; i < slides.length; i++) {
    final slide = slides[i];
    if (left < slideLength(slide) || i == slides.length - 1) {
      final first = i == 0 && seconds < round;
      return (
        index: i,
        previous: first ? null : (i - 1 + slides.length) % slides.length,
        progress: movingTime(slide.look) == 0 ? 1.0 : min(1.0, left / movingTime(slide.look)),
        into: left,
      );
    }
    left -= slideLength(slide);
  }
  return (index: 0, previous: null, progress: 1, into: 0);
}

/// The presentations [person] made, first to last: [showsEach] at most.
List<Show> showsBy(Trip trip, String person) =>
    [for (final show in trip.shows) if (show.addedBy == person) show];

/// How many of the group voted for [show].
int picksOf(Trip trip, Show show) =>
    trip.memberIds.where((person) => trip.showPicks[person] == show.id).length;

/// The presentation most of the group voted for: the presentation of the day. It
/// stays so while another only has as many votes; only more votes take its place.
/// Without one before, the first of equals is it. Null while nobody has voted.
Show? showOfTheDay(Trip trip) {
  final most = trip.shows.fold(0, (best, show) => max(best, picksOf(trip, show)));
  if (most == 0) return null;
  Show? first;
  for (final show in trip.shows) {
    if (picksOf(trip, show) != most) continue;
    if (show.id == trip.dayShowId) return show;
    first ??= show;
  }
  return first;
}

/// Remembers the presentation of the day for the next change of votes. True when
/// it changed, so the trip needs saving.
bool keepShowOfTheDay(Trip trip) {
  final now = showOfTheDay(trip)?.id;
  if (now == trip.dayShowId) return false;
  trip.dayShowId = now;
  return true;
}

/// What plays on the trip's cover: the presentation of the day, or before the
/// first vote the newest presentation, one that has something to show.
Show? onCover(Trip trip) {
  final best = showOfTheDay(trip);
  if (best != null && slidesOf(trip, best).isNotEmpty) return best;
  for (final show in trip.shows.reversed) {
    if (slidesOf(trip, show).isNotEmpty) return show;
  }
  return null;
}
