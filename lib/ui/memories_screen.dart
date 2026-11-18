import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/show.dart';
import '../src/domain/trip_tree.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'media.dart';
import 'photo_drag.dart';
import 'shows_section.dart';
import 'swipes.dart' show wantsLessMotion;
import 'trip_screen.dart' show redrawTripTab;
import 'video_work.dart';
import 'widgets.dart';

const Map<Reaction, String> _reactionIcons = {
  Reaction.heart: 'heart',
  Reaction.laugh: 'laugh',
  Reaction.cheers: 'cheers',
  Reaction.sun: 'sun',
  Reaction.star: 'star',
};

Future<void> _savePictures(Ui ui, Trip trip, List<web.File> files) async {
  ui.toast(tr('Spremam {0}...', [photosCount(files.length)]));
  var failed = 0;
  for (final file in files) {
    final photo = await importPhoto(ui.store, file, ui.meIn(trip));
    if (photo == null) {
      failed++;
    } else {
      trip.photos.add(photo..dayIndex = trip.dayOfAdding(today()));
      trip.coverId ??= photo.id;
    }
  }
  _keepStill(ui, trip, ui.saved);
  ui.toast(failed == 0
      ? _addedMessage(files.length)
      : tr('Neke fotografije ne mogu pročitati ({0}).', [failed]));
}

/// Picks photos and videos from the phone's gallery; the app sorts them by day
/// itself.
web.HTMLElement _addPhotos(Ui ui, Trip trip) {
  final picker = el('input', cls: 'file', attrs: {
    'type': 'file',
    'accept': 'image/*,video/*',
    'multiple': '',
  }) as web.HTMLInputElement;
  picker.onChange.listen((_) async {
    final files = pickedFiles(picker);
    final pictures = files.where((file) => !isVideoFile(file)).toList();
    final videos = files.where(isVideoFile).toList();
    if (pictures.isNotEmpty) await _savePictures(ui, trip, pictures);
    if (videos.isNotEmpty) {
      final added = trip.dayOfAdding(today());
      final made = await prepareVideos(ui, videos, ui.meIn(trip));
      trip.photos.addAll([for (final video in made) video..dayIndex = added]);
      _keepStill(ui, trip, ui.saved);
      if (made.isNotEmpty) ui.toast(_addedMessage(made.length));
    }
  });
  return el('label', cls: 'secondary', children: [
    picker,
    icon('plus', size: 18),
    web.document.createTextNode(tr('Dodaj')),
  ]);
}

/// One photo or video of the grid: a tap opens it, a finger held on it moves it
/// to another day.
web.HTMLElement _shot(Ui ui, Trip trip, Photo photo) {
  final shot = button(
      cls: 'shot',
      ariaLabel: photo.isVideo
          ? tr('Video, {0}', [weekdayAndDate(photo.day)])
          : tr('Fotografija, {0}', [weekdayAndDate(photo.day)]),
      onTap: () {
        if (tapEndsMove()) return;
        ui.go(ui.tripRoute(trip, 'foto/${photo.id}'));
      },
      children: [
        storedImage(ui, trip, thumbId(photo.id), cls: ''),
        if (photo.isVideo)
          el('span', cls: 'shot-play', children: [icon('play', size: 22)]),
        el('span', cls: 'counts', children: [
          icon('heart', size: 12),
          web.document.createTextNode(
              '${photo.reactions.values.fold(0, (sum, given) => sum + given.length)}'),
          icon('comment', size: 12),
          web.document.createTextNode('${photo.comments.length}'),
        ]),
      ],
    );
  shot.setAttribute('data-photo', photo.id);
  movableToDay(shot, (day) {
    if (trip.photoDay(photo) == day) return;
    photo.dayIndex = day >= trip.dayCount ? afterTrip : day;
    ui.changed();
    ui.toast(tr('Premješteno: {0}', [photoDayTitle(trip, day).split(' · ').first]), short: true);
  });
  return shot;
}

/// Uspomene: the presentations, then Prije puta, every day of the trip and
/// Poslije puta, each with its photos and videos by when they were taken; any
/// of them can be moved to another.
web.HTMLElement galleryTab(Ui ui, Trip trip) {
  final byDay = <int, List<Photo>>{};
  for (final photo in photosByDay(trip)) {
    byDay.putIfAbsent(trip.photoDay(photo), () => []).add(photo);
  }
  return el('div', children: [
    showsSection(ui, trip),
    el('hr', cls: 'split'),
    el('div', cls: 'head-row', attrs: {'style': 'align-items:center;justify-content:center'}, children: [
      _addPhotos(ui, trip),
    ]),
    if (trip.photos.isEmpty)
      el('p', cls: 'soft pad gap-top',
          text: tr('Dodajte fotografije i videe iz galerije, a aplikacija će ih sama složiti po danima.')),
    if (trip.photos.isNotEmpty) ...[
      el('p', cls: 'small pad', attrs: {'style': 'margin-top:16px'},
          text: tr('Povuci uspomenu na drugi dan.')),
      for (var day = -1; day <= trip.dayCount; day++) _dayGroup(ui, trip, day, byDay[day]),
    ],
  ]);
}

String _clock(DateTime at) => '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// One comment with its reactions. Answers all sit under the first comment
/// ([threadId]), so a conversation stays one level deep and easy to read.
web.HTMLElement _commentRow(
  Ui ui,
  Trip trip,
  Comment comment,
  String me,
  String threadId, {
  bool isReply = false,
}) {
  final mine = comment.reactions[me] ?? const <Reaction>{};
  return el('div', cls: isReply ? 'comment reply' : 'comment', children: [
    personAvatar(ui, trip, comment.authorId),
    el('div', cls: 'grow', children: [
      el('div', cls: 'small', children: [
        el('span', cls: 'strong', text: ui.nameOf(comment.authorId)),
        web.document.createTextNode(' · ${ago(comment.at, DateTime.now().toUtc())}'),
      ]),
      el('p', text: comment.text),
      el('div', cls: 'comment-actions', children: [
        for (final reaction in Reaction.values)
          button(
            cls: mine.contains(reaction) ? 'tiny on' : 'tiny',
            ariaLabel: '${reaction.label}, ${reactionCount(comment.reactions, reaction)}',
            onTap: () {
              toggleReaction(comment.reactions, me, reaction);
              ui.changed();
            },
            children: [
              icon(_reactionIcons[reaction]!, size: 16),
              if (reactionCount(comment.reactions, reaction) > 0)
                web.document.createTextNode(
                    '${reactionCount(comment.reactions, reaction)}'),
            ],
          ),
        button(
          cls: 'tiny',
          text: tr('Odgovori'),
          onTap: () {
            ui.replyingTo = threadId;
            ui.rerender();
          },
        ),
      ]),
    ]),
  ]);
}

/// A video, with its picture from the grid until the file has arrived.
web.HTMLElement _videoPlayer(Ui ui, Trip trip, Photo photo) {
  final player = el('video', cls: 'full-photo', attrs: {
    'controls': '',
    'playsinline': '',
    'preload': 'metadata',
  }) as web.HTMLVideoElement;
  ui.imageAddress(trip, thumbId(photo.id)).then((address) {
    if (address != null) player.poster = address;
  });
  ui.imageAddress(trip, photo.id).then((address) {
    if (address != null) player.src = address;
  });
  return player;
}

web.HTMLElement photoScreen(Ui ui, Trip trip, Photo photo) {
  final me = ui.meIn(trip);
  final mine = photo.reactions[me] ?? const <Reaction>{};
  final onCard = trip.coverId == photo.id;
  final message = input(placeholder: tr('Napiši komentar'));

  void send() {
    final text = message.value.trim();
    if (text.isEmpty) return;
    photo.comments.add(Comment(
      id: ui.store.newId(),
      authorId: me,
      text: text,
      at: DateTime.now().toUtc(),
      replyTo: ui.replyingTo,
    ));
    ui.replyingTo = null;
    ui.changed();
  }

  message.onKeyDown.listen((event) {
    if (event.key == 'Enter') send();
  });

  return el('div', children: [
    if (photo.isVideo)
      _videoPlayer(ui, trip, photo)
    else
      storedImage(ui, trip, photo.id, cls: 'full-photo', alt: tr('Fotografija s putovanja')),
    el('div', cls: 'head-row', attrs: {'style': 'align-items:center;justify-content:flex-start'},
        children: [
      personAvatar(ui, trip, photo.addedBy, big: true),
      el('div', cls: 'grow', children: [
        el('div', cls: 'label', text: ui.nameOf(photo.addedBy)),
        el('div', cls: 'small', text: '${weekdayAndDate(photo.day)} u ${_clock(photo.takenAt)}'),
      ]),
      removeButton(photo.isVideo ? tr('ovaj video') : tr('ovu fotografiju'), () {
        trip.photos.remove(photo);
        if (onCard) {
          final pictures = trip.photos.where((item) => !item.isVideo);
          trip.coverId = pictures.isEmpty ? null : pictures.first.id;
        }
        for (final id in [
          for (var i = 0; i < photo.parts; i++) pieceId(photo.id, i),
          thumbId(photo.id),
        ]) {
          ui.store.removeBlob(id);
          ui.cloud?.removeBlob(trip, id);
        }
        ui.saved();
        ui.back();
      }),
    ]),
    el('div', cls: 'reactions', children: [
      for (final reaction in Reaction.values)
        button(
          cls: mine.contains(reaction) ? 'reaction on' : 'reaction',
          ariaLabel: '${reaction.label}, '
              '${reactionCount(photo.reactions, reaction)}',
          onTap: () {
            toggleReaction(photo.reactions, me, reaction);
            ui.changed();
          },
          children: [
            el('span', children: [icon(_reactionIcons[reaction]!, size: 26)]),
            web.document.createTextNode(
                '${reactionCount(photo.reactions, reaction)}'),
          ],
        ),
    ]),
    if (!photo.isVideo)
      el('div', cls: 'pad', children: [
        button(
          cls: 'text-button',
          onTap: () {
            trip.coverId = photo.id;
            ui.changed();
            ui.toast(tr('Fotografija je na razglednici.'));
          },
          children: [
            icon('photo', size: 20),
            web.document.createTextNode(
                onCard ? tr('Ova je fotografija na razglednici') : tr('Stavi na razglednicu')),
          ],
        ),
      ]),
    sectionTitle(tr('Komentari')),
    if (photo.comments.isEmpty)
      el('p', cls: 'soft pad', text: tr('Budi prvi koji će nešto napisati.')),
    for (final comment in photo.comments.where((c) => c.replyTo == null)) ...[
      _commentRow(ui, trip, comment, me, comment.id),
      for (final reply in photo.comments.where((c) => c.replyTo == comment.id))
        _commentRow(ui, trip, reply, me, comment.id, isReply: true),
    ],
    if (ui.replyingTo != null)
      el('div', cls: 'row', children: [
        el('div', cls: 'grow small', text: tr('Pišeš odgovor')),
        chip(tr('Odustani'), () {
          ui.replyingTo = null;
          ui.rerender();
        }),
      ]),
    el('div', cls: 'composer', children: [
      el('label', attrs: {'style': 'display:contents'}, children: [message]),
      button(
        cls: 'send',
        ariaLabel: tr('Pošalji komentar'),
        onTap: send,
        children: [icon('send', size: 22)],
      ),
    ]),
  ]);
}

/// How many photos a day shows before a tap on its name shows them all.
const _photosShown = 9;

/// A day of Uspomene: its name and photos, at most [_photosShown] of them with
/// the last row fading while there are more; a tap on the name shows them all
/// and another folds them again.
web.HTMLElement _dayGroup(Ui ui, Trip trip, int day, List<Photo>? photos) {
  final key = 'photos:${trip.id}:$day';
  final open = ui.openFolds.contains(key);
  final more = (photos?.length ?? 0) - _photosShown;
  final title = photoDayTitle(trip, day);
  return el('div', cls: 'day-group', attrs: {'data-day': '$day'}, children: [
    if (more > 0)
      button(
        cls: 'day-title day-more',
        text: open ? '$title  −' : '$title  +$more',
        onTap: () => _showAll(ui, trip, key, day),
      )..setAttribute('aria-expanded', '$open')
    else
      el('div', cls: 'day-title', text: title),
    if (photos == null)
      el('div', cls: 'day-empty', text: tr('Ovdje još nema ničega.'))
    else
      el('div', cls: more > 0 && !open ? 'grid folded' : 'grid', children: [
        for (final photo in open ? photos : photos.take(_photosShown)) _shot(ui, trip, photo),
        if (more > 0 && !open)
          button(
            cls: 'more-fade',
            ariaLabel: tr('Prikaži sve'),
            onTap: () => _showAll(ui, trip, key, day),
          ),
      ]),
  ]);
}

String _addedMessage(int count) => count == 1 ? tr('Medij dodan.') : tr('Mediji dodani.');

/// Shows all the photos of a day, or folds them back to nine.
void _showAll(Ui ui, Trip trip, String key, int day) {
  _keepStill(ui, trip, () {
    if (!ui.openFolds.remove(key)) ui.openFolds.add(key);
  }, day: day);
}

/// Makes [change] and redraws Uspomene alone, with the page standing still:
/// what is at the top of the screen stays there, the day [day] folds open or
/// shut smoothly and what is under it follows. A full redraw made an iPhone
/// jump, as it did when polls were changed.
void _keepStill(Ui ui, Trip trip, void Function() change, {int? day}) {
  web.HTMLElement? group(int at) =>
      web.document.querySelector('.day-group[data-day="$at"]') as web.HTMLElement?;
  web.Element? find(String? selector) => selector == null ? null : web.document.querySelector(selector);
  // The page never gets shorter under the finger.
  final frame = web.document.querySelector('.frame') as web.HTMLElement?;
  if (frame != null) {
    final need = web.window.scrollY + web.window.innerHeight;
    final has = double.tryParse(frame.style.minHeight.replaceAll('px', '')) ?? 0;
    if (need > has) frame.style.minHeight = '${need.round()}px';
  }
  // What is held still: the name of the day folding, else the first photo,
  // day name or empty day at the top of the screen.
  String? anchor = day == null ? null : '.day-group[data-day="$day"] .day-title';
  if (anchor == null) {
    final seen = web.document.querySelectorAll('.day-group .day-title, .day-group .shot, .day-group .day-empty');
    for (var i = 0; i < seen.length; i++) {
      final one = seen.item(i) as web.Element;
      if (one.getBoundingClientRect().top < 70) continue;
      final photo = one.getAttribute('data-photo');
      final at = one.closest('.day-group')?.getAttribute('data-day');
      anchor = photo != null
          ? '.shot[data-photo="$photo"]'
          : '.day-group[data-day="$at"] .${one.classList.contains('day-title') ? 'day-title' : 'day-empty'}';
      break;
    }
  }
  final before = find(anchor)?.getBoundingClientRect().top;
  final from = day == null ? 0 : group(day)?.offsetHeight ?? 0;
  change();
  redrawTripTab(ui, trip);
  if (before != null) {
    final after = find(anchor)?.getBoundingClientRect().top;
    if (after != null && (after - before).abs() > 1) web.window.scrollBy(web.ScrollToOptions(top: after - before));
  }
  final folding = day == null ? null : group(day);
  if (folding == null || wantsLessMotion) return;
  final to = folding.offsetHeight;
  if (from == 0 || from == to) return;
  folding.style
    ..transition = 'none'
    ..overflow = 'hidden'
    ..height = '${from}px';
  folding.getBoundingClientRect(); // so that the browser sees where it starts
  folding.style
    ..transition = 'height 260ms ease'
    ..height = '${to}px';
  Timer(const Duration(milliseconds: 300), () {
    folding.style
      ..transition = ''
      ..overflow = ''
      ..height = '';
  });
}
