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
import 'seconds_bar.dart';
import 'show_player.dart';
import 'widgets.dart';

/// A presentation being made, kept apart from the trip until it is saved, so that
/// a redraw of the screen keeps it.
class _Draft {
  _Draft(this.tripId, Show? show)
      : editing = show?.id,
        name = show?.name ?? '',
        look = (show?.look ?? Look(Transition.fade)).copy(),
        looks = {
          for (final entry in (show?.looks ?? const <String, Look>{}).entries)
            entry.key: entry.value.copy(),
        },
        leftOut = {...?show?.leftOut};

  final String tripId;

  /// The presentation being changed; null for a new one.
  final String? editing;
  String name;
  Look look;
  Map<String, Look> looks;
  Set<String> leftOut;

  /// The photo whose transition is being set.
  String? chosen;

  /// How far the row of photos is scrolled.
  double strip = 0;

  Show asShow(String person) => Show(
        id: editing ?? '',
        name: name,
        addedBy: person,
        look: look,
        looks: looks,
        leftOut: leftOut,
      );
}

_Draft? _draft;

/// Opens the making of this person's presentation: a new one, or theirs to change.
void openShowBuilder(Ui ui, Trip trip) {
  _draft = _Draft(trip.id, showBy(trip, ui.meIn(trip)));
  ui.go(ui.tripRoute(trip, 'prezentacija'));
}

/// What a lengthening of transitions this trip opens next.
String _growth(Trip trip, DateTime now, double limit) {
  if (limit >= longestExtra) return tr('Otvoreno je svih 12 s i svih 15 prijelaza.');
  final tomorrow = extraLimit(trip, now.add(const Duration(days: 1)));
  return tomorrow > limit
      ? tr('Sutra se otvara do {0} s, a zadnji dan putovanja do 12 s.', [tenths(tomorrow)])
      : tr('Svaki dan putovanja otvara dulje prijelaze, do 12 s zadnji dan.');
}

/// How long [photo] stays: a photo 4 s and as much longer as wanted, a video the
/// piece of it that is picked, 6 s of every 30 s at most.
List<web.HTMLElement> _howLong(Ui ui, Photo photo, Look look, Look Function() own) {
  if (!photo.isVideo) {
    return [
      el('p', cls: 'label pad gap-top', text: tr('Koliko dugo se prikazuje')),
      secondsBar(
        value: look.stay,
        limit: longestStay,
        longest: longestStay,
        label: tr('Koliko dugo se prikazuje'),
        onChange: (seconds, {required done}) {
          own().stay = seconds;
          if (done) ui.rerender();
        },
      ),
      el('p', cls: 'small pad', text: tr('Svaka fotografija stoji 4 s, i još koliko ovdje dodaš.')),
    ];
  }
  final length = videoLength(photo);
  final clip = clipOf((photoId: photo.id, look: look, video: length));
  final longest = longestClip(length);
  return [
    el('p', cls: 'label pad gap-top', text: tr('Koliko videa ide u prezentaciju')),
    secondsBar(
      value: clip.length,
      limit: longest,
      longest: longest,
      added: false,
      label: tr('Koliko videa ide u prezentaciju'),
      onChange: (seconds, {required done}) {
        own().length = max(1, seconds);
        if (done) ui.rerender();
      },
    ),
    if (length - clip.length > .05) ...[
      el('p', cls: 'label pad gap-top', text: tr('Od koje sekunde')),
      secondsBar(
        value: clip.from,
        limit: length - clip.length,
        longest: length,
        added: false,
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

/// Makes or changes this person's presentation of the trip's photos. On top it
/// plays as it will on the trip's cover, from the photo being set.
web.HTMLElement showBuilder(Ui ui, Trip trip) {
  final me = ui.meIn(trip);
  final draft = _draft?.tripId == trip.id ? _draft! : _draft = _Draft(trip.id, showBy(trip, me));
  final now = DateTime.now();
  final limit = extraLimit(trip, now);
  final open = openTransitions(trip, now);
  final photos = trip.photos.toList()..sort((a, b) => a.takenAt.compareTo(b.takenAt));
  if (!photos.any((photo) => photo.id == draft.chosen)) {
    draft.chosen = photos.isEmpty ? null : photos.first.id;
  }
  final chosen = draft.chosen;
  final slides = slidesOf(trip, draft.asShow(me));
  final at = slides.indexWhere((slide) => slide.photoId == chosen);
  final preview = ShowPlayer(ui, trip, slides, from: at <= 0 ? 0 : secondsBefore(slides, at))
    ..start();
  final error = errorLine();
  final name = input(value: draft.name);
  name.onInput.listen((_) => draft.name = name.value);

  Look lookOf(String photo) => draft.looks[photo] ?? draft.look;
  Look own(String photo) => draft.looks.putIfAbsent(photo, () => draft.look.copy());

  Show? existing() {
    for (final show in trip.shows) {
      if (show.id == draft.editing) return show;
    }
    return null;
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
    final kept = {for (final photo in photos) photo.id};
    draft.looks.removeWhere((photo, _) => !kept.contains(photo));
    draft.leftOut.removeWhere((photo) => !kept.contains(photo));
    final show = existing();
    if (show != null) {
      show
        ..name = title
        ..look = draft.look
        ..looks = draft.looks
        ..leftOut = draft.leftOut;
    } else if (showBy(trip, me) != null) {
      error.textContent = tr('Već imaš prezentaciju na ovom putovanju.');
      return;
    } else {
      final made = Show(
        id: ui.store.newId(),
        name: title,
        addedBy: me,
        look: draft.look,
        looks: draft.looks,
        leftOut: draft.leftOut,
      );
      trip.shows.add(made);
      trip.showPicks.putIfAbsent(me, () => made.id);
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

  final strip = el('div', cls: 'show-strip', children: [
    for (final photo in photos)
      button(
        cls: [
          'show-thumb',
          if (photo.id == chosen) 'on',
          if (draft.leftOut.contains(photo.id)) 'out',
        ].join(' '),
        ariaLabel: photo.isVideo
            ? tr('Video, {0}', [weekdayAndDate(photo.day)])
            : tr('Fotografija, {0}', [weekdayAndDate(photo.day)]),
        onTap: () {
          draft.chosen = photo.id;
          ui.rerender();
        },
        children: [
          el('span', cls: 'show-thumb-picture', children: [
            storedImage(ui, trip, thumbId(photo.id), cls: ''),
            if (photo.isVideo) el('span', cls: 'shot-play', children: [icon('play', size: 18)]),
          ]),
          el('span', cls: 'show-thumb-label', text: lookOf(photo.id).transition.label),
        ],
      ),
  ]);
  strip.onScroll.listen((_) => draft.strip = strip.scrollLeft.toDouble());
  scheduleMicrotask(() => strip.scrollLeft = draft.strip);

  final show = existing();
  return el('div', children: [
    topBar(show == null ? tr('Nova prezentacija') : tr('Tvoja prezentacija')),
    el('div', cls: 'show-preview', children: [preview.element]),
    el('p', cls: 'small pad', attrs: {'style': 'margin-top:6px'},
        text: tr('Ovako će svirati na naslovnoj slici putovanja.')),
    field(tr('Naziv'), name),
    if (photos.isEmpty)
      el('p', cls: 'soft pad gap-top', text: tr('Prvo dodajte fotografije u Uspomene.'))
    else ...[
      sectionTitle(tr('Uspomene ({0} od {1})', [slides.length, photos.length])),
      strip,
    ],
    if (chosen != null) ...[
      el('div', cls: 'pad', attrs: {'style': 'margin-top:4px'}, children: [
        tick(tr('U prezentaciji'), !draft.leftOut.contains(chosen), () {
          if (!draft.leftOut.remove(chosen)) draft.leftOut.add(chosen);
          ui.rerender();
        }),
      ]),
      el('p', cls: 'label pad gap-top', text: tr('Prijelaz')),
      el('div', cls: 'checks', children: [
        for (var i = 0; i < Transition.values.length; i++)
          if (i < open)
            chip(Transition.values[i].label, () {
              own(chosen).transition = Transition.values[i];
              ui.rerender();
            }, on: lookOf(chosen).transition == Transition.values[i])
          else
            button(
              cls: 'chip locked',
              text: Transition.values[i].label,
              onTap: () => ui.toast(tr('Ovaj prijelaz se otvara kasnije tijekom putovanja.')),
            ),
      ]),
      if (open < Transition.values.length)
        el('p', cls: 'small pad', attrs: {'style': 'margin-top:6px'},
            text: tr('Još {0} prijelaza otvara se tijekom putovanja.', [Transition.values.length - open])),
      el('p', cls: 'label pad gap-top', text: tr('Produljenje prijelaza')),
      secondsBar(
        value: lookOf(chosen).extra,
        limit: limit,
        label: tr('Produljenje prijelaza'),
        onChange: (seconds, {required done}) {
          own(chosen).extra = seconds;
          if (done) ui.rerender();
        },
      ),
      el('p', cls: 'small pad', text: _growth(trip, now, limit)),
      ..._howLong(ui, photos.firstWhere((photo) => photo.id == chosen), lookOf(chosen),
          () => own(chosen)),
      el('div', cls: 'pad', children: [
        button(
          cls: 'text-button',
          text: tr('Isto za sve fotografije'),
          onTap: () {
            draft
              ..look = lookOf(chosen).copy()
              ..looks.clear();
            ui.toast(tr('Sve fotografije imaju isti prijelaz.'));
            ui.rerender();
          },
        ),
      ]),
    ],
    error,
    primaryButton(tr('Spremi prezentaciju'), save),
    if (show != null)
      el('div', cls: 'pad gap-top', children: [
        button(cls: 'text-button danger', text: tr('Obriši prezentaciju'), onTap: () => remove(show)),
      ]),
  ]);
}
