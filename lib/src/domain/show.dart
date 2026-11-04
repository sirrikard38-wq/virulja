import 'dart:math';

import 'models.dart';

/// The whole bar of a transition's lengthening, and the part of it open from
/// the start: half.
const double longestExtra = 12;
const double firstExtra = 6;

/// Transitions there are from the start; the others open as the trip goes on.
const int firstTransitions = 5;

/// Seconds a transition takes before it is made longer, and then how long a
/// photo stands still before it may be made to stay longer.
const double transitionTime = 1;
const double stillTime = 4;

/// The bar for how much longer a photo stays: all of it open.
const double longestStay = 12;

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

/// How many transitions can be used on [now]: five at first and all of them on
/// the last day, in step with [extraLimit].
int openTransitions(Trip trip, DateTime now) {
  final share = (extraLimit(trip, now) - firstExtra) / (longestExtra - firstExtra);
  final later = Transition.values.length - firstTransitions;
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

/// The photos and videos of [show] in the order they were taken: everything in
/// Uspomene but what is left out.
List<Slide> slidesOf(Trip trip, Show show) {
  final photos = trip.photos.where((photo) => !show.leftOut.contains(photo.id)).toList()
    ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  return [
    for (final photo in photos)
      (
        photoId: photo.id,
        look: show.looks[photo.id] ?? show.look,
        video: photo.isVideo ? videoLength(photo) : null,
      ),
  ];
}

/// How long one photo or video takes: its transition, then a photo stands still
/// and a video plays its piece.
double slideLength(Slide slide) =>
    transitionTime +
    slide.look.extra +
    (slide.video == null ? stillTime + slide.look.stay : clipOf(slide).length);

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
        progress: min(1.0, left / (transitionTime + slide.look.extra)),
        into: left,
      );
    }
    left -= slideLength(slide);
  }
  return (index: 0, previous: null, progress: 1, into: 0);
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
