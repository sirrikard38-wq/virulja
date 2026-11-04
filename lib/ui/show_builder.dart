import 'dart:async';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/show.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'photo_drag.dart';
import 'seconds_bar.dart';
import 'show_player.dart';
import 'widgets.dart';

Map<String, Look> _copies(Map<String, Look> looks) =>
    {for (final entry in looks.entries) entry.key: entry.value.copy()};

/// A presentation being made, kept apart from the trip until it is saved, so that
/// a redraw of the screen keeps it.
class _Draft {
  _Draft(this.tripId, Show? show, List<Slide> slides)
      : editing = show?.id,
        name = show?.name ?? '',
        look = (show?.look ?? Look(Transition.fade)).copy(),
        looks = _copies(show?.looks ?? const {}),
        chosen = [for (final slide in slides) slide.photoId];

  final String tripId;

  /// The presentation being changed; null for a new one.
  final String? editing;
  String name;
  Look look;
  Map<String, Look> looks;

  /// The photos and videos in it, in their order.
  List<String> chosen;

  /// The photo whose transition is being set.
  String? current;

  /// How every photo came in before they were all made the same, to go back to.
  ({Look look, Map<String, Look> looks})? before;

  /// How far each row of photos is scrolled.
  final Map<String, double> scrolled = {};

  Show asShow(String person) => Show(
        id: editing ?? '',
        name: name,
        addedBy: person,
        look: look,
        looks: looks,
        chosen: chosen,
      );
}

_Draft? _draft;

/// Opens the making of a presentation of this person: [show] to change, or a
/// new one when null.
void openShowBuilder(Ui ui, Trip trip, Show? show) {
  _draft = _Draft(trip.id, show, show == null ? const [] : slidesOf(trip, show));
  ui.go(ui.tripRoute(trip, show == null ? 'prezentacija' : 'prezentacija/${show.id}'));
}

/// How long [photo] stays: a photo as long as its bar says, a video the piece of
/// it that is picked, 6 s of every 30 s at most.
List<web.HTMLElement> _howLong(
  Ui ui,
  Photo photo,
  Look look,
  Look Function() own,
  double limit,
  List<double> marks,
) {
  if (!photo.isVideo) {
    return [
      el('p', cls: 'label pad gap-top bar-title', text: tr('Duljina uspomene')),
      secondsBar(
        value: look.still,
        limit: limit,
        least: leastStill,
        marks: marks,
        label: tr('Duljina uspomene'),
        onChange: (seconds, {required done}) {
          own().still = seconds;
          if (done) ui.rerender();
        },
      ),
    ];
  }
  final length = videoLength(photo);
  final clip = clipOf((photoId: photo.id, look: look, video: length));
  final longest = longestClip(length);
  return [
    el('p', cls: 'label pad gap-top bar-title', text: tr('Koliko videa ide u prezentaciju')),
    secondsBar(
      value: clip.length,
      limit: longest,
      longest: longest,
      least: min(1, longest),
      label: tr('Koliko videa ide u prezentaciju'),
      onChange: (seconds, {required done}) {
        own().length = seconds;
        if (done) ui.rerender();
      },
    ),
    if (length - clip.length > .05) ...[
      el('p', cls: 'label pad gap-top bar-title', text: tr('Od koje sekunde')),
      secondsBar(
        value: clip.from,
        limit: length - clip.length,
        longest: length,
        label: tr('Od koje sekunde'),
        onChange: (seconds, {required done}) {
          own().from = seconds;
          if (done) ui.rerender();
        },
      ),
    ],
    el('p', cls: 'small pad', text: tr('Od svakih 30 s videa u prezentaciju ide najviše 6 s.')),
  ];
}

/// A row of small pictures that scrolls sideways and keeps where it was across
/// redraws.
web.HTMLElement _strip(_Draft draft, String key, List<web.HTMLElement> pictures) {
  final strip = el('div', cls: 'show-strip', children: pictures);
  strip.onScroll.listen((_) => draft.scrolled[key] = strip.scrollLeft.toDouble());
  scheduleMicrotask(() => strip.scrollLeft = draft.scrolled[key] ?? 0);
  return strip;
}

web.HTMLElement _thumb(
  Ui ui,
  Trip trip,
  Photo photo, {
  required String cls,
  required void Function() onTap,
  String? label,
  int? place,
}) =>
    button(
      cls: 'show-thumb $cls',
      ariaLabel: photo.isVideo
          ? tr('Video, {0}', [weekdayAndDate(photo.day)])
          : tr('Fotografija, {0}', [weekdayAndDate(photo.day)]),
      onTap: onTap,
      children: [
        el('span', cls: 'show-thumb-picture', children: [
          storedImage(ui, trip, thumbId(photo.id), cls: ''),
          if (photo.isVideo) el('span', cls: 'shot-play', children: [icon('play', size: 18)]),
          if (place != null) el('span', cls: 'show-thumb-place', text: '$place'),
        ]),
        if (label != null) el('span', cls: 'show-thumb-label', text: label),
      ],
    );

/// Makes or changes a presentation of the trip's photos. Under its name is the
/// row of the presentation itself, where a finger held on a photo changes the
/// order, and under that every day of Uspomene in a row of its own, the last day
/// on top: a tap there puts a photo in or takes it out. Then the presentation
/// plays from the photo being set, and stays in sight while its transition and
/// time are set under it.
web.HTMLElement showBuilder(Ui ui, Trip trip, String? showId) {
  final me = ui.meIn(trip);
  Show? existing() {
    for (final show in trip.shows) {
      if (show.id == showId && show.addedBy == me) return show;
    }
    return null;
  }

  final show = existing();
  if (showId != null && show == null) {
    // Each person changes only their own presentations.
    final someoneElses = trip.shows.any((other) => other.id == showId);
    return el('div', children: [
      topBar(tr('Prezentacija')),
      el('p', cls: 'soft pad', text: someoneElses
          ? tr('Prezentaciju može mijenjati samo onaj tko ju je napravio.')
          : tr('Te prezentacije više nema.')),
    ]);
  }
  var made = _draft;
  if (made == null || made.tripId != trip.id || made.editing != showId) {
    made = _draft = _Draft(trip.id, show, show == null ? const [] : slidesOf(trip, show));
  }
  final draft = made;
  final now = DateTime.now();
  final limit = extraLimit(trip, now);
  final open = ui.allTransitions ? effects.length : openTransitions(trip, now);
  final marks = [for (var second = 0.0; second < firstExtra; second++) second, ...dayLimits(trip)];
  final photos = photosByDay(trip);
  final byId = {for (final photo in photos) photo.id: photo};
  draft.chosen.removeWhere((id) => !byId.containsKey(id));
  if (!draft.chosen.contains(draft.current)) {
    draft.current = draft.chosen.isEmpty ? null : draft.chosen.first;
  }
  final current = draft.current;
  final slides = slidesOf(trip, draft.asShow(me));
  final at = slides.indexWhere((slide) => slide.photoId == current);
  final preview = ShowPlayer(ui, trip, slides, from: at <= 0 ? 0 : secondsBefore(slides, at))
    ..start();
  final error = errorLine();
  final name = input(value: draft.name);
  name.onInput.listen((_) => draft.name = name.value);
  final mine = showsBy(trip, me);
  final number = show == null ? mine.length + 1 : mine.indexOf(show) + 1;

  Look lookOf(String photo) => draft.looks[photo] ?? draft.look;
  Look own(String photo) {
    draft.before = null; // a change of one photo ends the way back
    return draft.looks.putIfAbsent(photo, () => draft.look.copy());
  }

  void toggle(String photo) {
    if (draft.chosen.remove(photo)) {
      if (draft.current == photo) draft.current = null;
    } else {
      draft
        ..chosen.add(photo)
        ..current = photo;
    }
    ui.rerender();
  }

  void save() {
    final title = draft.name.trim();
    if (title.isEmpty) {
      error.textContent = tr('Upiši naziv prezentacije.');
      return;
    }
    if (slides.isEmpty) {
      error.textContent = tr('U prezentaciji treba biti barem jedna fotografija.');
      return;
    }
    final kept = draft.chosen.toSet();
    draft.looks.removeWhere((photo, _) => !kept.contains(photo));
    if (show != null) {
      show
        ..name = title
        ..look = draft.look
        ..looks = draft.looks
        ..chosen = [...draft.chosen]
        ..leftOut = {};
    } else if (mine.length >= showsEach) {
      error.textContent = tr('Već imaš 3 prezentacije na ovom putovanju.');
      return;
    } else {
      trip.shows.add(Show(
        id: ui.store.newId(),
        name: title,
        addedBy: me,
        look: draft.look,
        looks: draft.looks,
        chosen: [...draft.chosen],
      ));
    }
    _draft = null;
    ui.saved();
    ui.toast(tr('Prezentacija je spremljena.'));
    ui.back();
  }

  void remove(Show show) {
    final place = trip.shows.indexOf(show);
    final picks = {
      for (final entry in trip.showPicks.entries)
        if (entry.value == show.id) entry.key: entry.value,
    };
    trip.shows.remove(show);
    trip.showPicks.removeWhere((_, id) => id == show.id);
    _draft = null;
    ui.saved();
    ui.back();
    ui.offerUndo(tr('Uklonjeno: {0}', [show.name]), () {
      trip.shows.insert(min(place, trip.shows.length), show);
      trip.showPicks.addAll(picks);
      ui.changed();
    });
  }

  /// The presentation's own row: a tap picks the photo to set, a finger held on
  /// it moves it to another place.
  web.HTMLElement presentationRow() {
    final thumbs = [
      for (final id in draft.chosen)
        _thumb(ui, trip, byId[id]!,
            cls: id == current ? 'on' : '',
            label: lookOf(id).transition.label, onTap: () {
          if (tapEndsMove()) return;
          draft.current = id;
          ui.rerender();
        }),
    ];
    final row = _strip(draft, 'top', thumbs);
    for (var i = 0; i < thumbs.length; i++) {
      reorderable(thumbs[i], row, i, (from, to) {
        draft.chosen.insert(to, draft.chosen.removeAt(from));
        ui.rerender();
      });
    }
    return row;
  }

  final days = <int, List<Photo>>{};
  for (final photo in photos) {
    days.putIfAbsent(trip.photoDay(photo), () => []).add(photo);
  }
  final shownDays = days.keys.toList()..sort((a, b) => b.compareTo(a));

  return el('div', children: [
    topBar(tr('Prezentacija'))
      ..querySelector('h1')!.append(el('span', cls: 'show-count', text: ' $number/$showsEach')),
    field(tr('Naziv'), name),
    if (limit < longestExtra)
      el('p', cls: 'small pad', attrs: {'style': 'margin-top:8px'},
          text: tr('Svaki dan dobivaš dulje prijelaze, fotografije i ekstra efekte.')),
    if (photos.isEmpty)
      el('p', cls: 'soft pad gap-top', text: tr('Prvo dodajte fotografije u Uspomene.'))
    else ...[
      sectionTitle(tr('Uspomene')),
      for (final day in shownDays) ...[
        el('div', cls: 'show-day', text: tr('{0} Dan · {1}', [day + 1, weekdayAndDate(trip.dayAt(day))])),
        _strip(draft, 'day $day', [
          for (final photo in days[day]!)
            _thumb(ui, trip, photo,
                cls: draft.chosen.contains(photo.id) ? 'in' : '',
                place: draft.chosen.contains(photo.id) ? draft.chosen.indexOf(photo.id) + 1 : null,
                onTap: () => toggle(photo.id)),
        ]),
      ],
    ],
    if (photos.isNotEmpty) ...[
      sectionTitle(tr('Odabrano za prezentaciju')),
      if (draft.chosen.isEmpty)
        el('p', cls: 'show-empty', text: tr('Dodirni fotografije iznad i dodaj ih u prezentaciju.'))
      else ...[
        presentationRow(),
        if (draft.chosen.length > 1)
          el('p', cls: 'small pad', text: tr('Drži prst na fotografiji i pomakni je da promijeniš redoslijed.')),
      ],
    ],
    el('div', cls: 'show-preview-wrap', children: [
      el('div', cls: 'show-preview', children: [preview.element]),
    ]),
    if (current != null) ...[
      el('p', cls: 'label pad gap-top', text: tr('Prijelaz')),
      el('div', cls: 'checks', children: [
        for (final transition in [Transition.none, ...effects])
          if (transition == Transition.none || effects.indexOf(transition) < open)
            chip(transition.label, () {
              own(current).transition = transition;
              ui.rerender();
            }, on: lookOf(current).transition == transition)
          else
            button(
              cls: 'chip locked',
              text: transition.label,
              onTap: () => ui.toast(tr('Ovaj prijelaz se otvara kasnije tijekom putovanja.')),
            ),
      ]),
      // Ništa cuts at once, so there is nothing to make longer.
      if (lookOf(current).transition != Transition.none) ...[
        el('p', cls: 'label pad gap-top bar-title', text: tr('Produljenje prijelaza')),
        secondsBar(
          value: lookOf(current).extra,
          limit: limit,
          marks: marks,
          label: tr('Produljenje prijelaza'),
          onChange: (seconds, {required done}) {
            own(current).extra = seconds;
            if (done) ui.rerender();
          },
        ),
      ],
      ..._howLong(ui, byId[current]!, lookOf(current), () => own(current), limit, marks),
      el('div', cls: 'pad centered gap-top', children: [
        button(
          cls: 'text-button',
          text: draft.before == null ? tr('Isti prijelazi i duljina uspomene za sve') : tr('Vrati natrag'),
          onTap: () {
            final before = draft.before;
            if (before == null) {
              final same = lookOf(current).copy();
              draft
                ..before = (look: draft.look, looks: draft.looks)
                ..look = same
                ..looks = {};
            } else {
              draft
                ..look = before.look
                ..looks = before.looks
                ..before = null;
            }
            ui.rerender();
          },
        ),
      ]),
    ],
    error,
    primaryButton(tr('Spremi prezentaciju'), save),
    if (show != null)
      el('div', cls: 'pad centered gap-top', children: [
        button(cls: 'text-button danger', text: tr('Obriši prezentaciju'), onTap: () => remove(show)),
      ]),
  ]);
}
