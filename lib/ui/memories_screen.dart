import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'media.dart';
import 'widgets.dart';

const Map<Reaction, String> _reactionIcons = {
  Reaction.heart: 'heart',
  Reaction.laugh: 'laugh',
  Reaction.cheers: 'cheers',
  Reaction.sun: 'sun',
  Reaction.star: 'star',
};

/// Picks photos from the phone's gallery; the app sorts them by day itself.
web.HTMLElement _addPhotos(Ui ui, Trip trip) {
  final picker = el('input', cls: 'file', attrs: {
    'type': 'file',
    'accept': 'image/*',
    'multiple': '',
  }) as web.HTMLInputElement;
  picker.onChange.listen((_) async {
    final files = pickedFiles(picker);
    if (files.isEmpty) return;
    ui.toast('Spremam ${photosCount(files.length)}...');
    var failed = 0;
    for (final file in files) {
      final photo = await importPhoto(ui.store, file, ui.meIn(trip));
      if (photo == null) {
        failed++;
      } else {
        trip.photos.add(photo);
        trip.coverId ??= photo.id;
      }
    }
    ui.changed();
    ui.toast(failed == 0
        ? 'Fotografije su spremljene.'
        : 'Neke fotografije ne mogu pročitati ($failed).');
  });
  return el('label', cls: 'secondary', children: [
    picker,
    icon('plus', size: 18),
    web.document.createTextNode('Dodaj'),
  ]);
}

web.HTMLElement _shot(Ui ui, Trip trip, Photo photo) => button(
      cls: 'shot',
      ariaLabel: 'Fotografija, ${weekdayAndDate(photo.day)}',
      onTap: () => ui.go(ui.tripRoute(trip, 'foto/${photo.id}')),
      children: [
        storedImage(ui, trip, thumbId(photo.id), cls: ''),
        el('span', cls: 'counts', children: [
          icon('heart', size: 12),
          web.document.createTextNode(
              '${photo.reactions.values.fold(0, (sum, given) => sum + given.length)}'),
          icon('comment', size: 12),
          web.document.createTextNode('${photo.comments.length}'),
        ]),
      ],
    );

web.HTMLElement galleryTab(Ui ui, Trip trip) {
  final byDay = <DateTime, List<Photo>>{};
  for (final photo in trip.photos.toList()
    ..sort((a, b) => a.takenAt.compareTo(b.takenAt))) {
    byDay.putIfAbsent(photo.day, () => []).add(photo);
  }
  return el('div', children: [
    el('div', cls: 'head-row', attrs: {'style': 'align-items:center'}, children: [
      el('span', cls: 'soft', text: '${photosCount(trip.photos.length)} · '
          '${peopleCount(trip.people)}'),
      _addPhotos(ui, trip),
    ]),
    if (trip.photos.isEmpty)
      el('p', cls: 'soft pad gap-top',
          text: 'Dodajte fotografije iz galerije, a aplikacija će ih sama '
              'složiti po danima.'),
    for (final entry in byDay.entries) ...[
      el('div', cls: 'day-title', text: _dayTitle(trip, entry.key)),
      el('div', cls: 'grid', children: [
        for (final photo in entry.value) _shot(ui, trip, photo),
      ]),
    ],
  ]);
}

String _dayTitle(Trip trip, DateTime day) {
  final index = day.difference(trip.start).inDays;
  final date = weekdayAndDate(day);
  return index >= 0 && index < trip.dayCount ? 'Dan ${index + 1} · $date' : date;
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
          text: 'Odgovori',
          onTap: () {
            ui.replyingTo = threadId;
            ui.rerender();
          },
        ),
      ]),
    ]),
  ]);
}

web.HTMLElement photoScreen(Ui ui, Trip trip, Photo photo) {
  final me = ui.meIn(trip);
  final mine = photo.reactions[me] ?? const <Reaction>{};
  final onCard = trip.coverId == photo.id;
  final message = input(placeholder: 'Napiši komentar');

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
    storedImage(ui, trip, photo.id, cls: 'full-photo', alt: 'Fotografija s putovanja'),
    el('div', cls: 'head-row', attrs: {'style': 'align-items:center;justify-content:flex-start'},
        children: [
      personAvatar(ui, trip, photo.addedBy, big: true),
      el('div', cls: 'grow', children: [
        el('div', cls: 'label', text: ui.nameOf(photo.addedBy)),
        el('div', cls: 'small', text: '${weekdayAndDate(photo.day)} u ${_clock(photo.takenAt)}'),
      ]),
      removeButton('ovu fotografiju', () {
        trip.photos.remove(photo);
        if (onCard) trip.coverId = trip.photos.isEmpty ? null : trip.photos.first.id;
        for (final id in [photo.id, thumbId(photo.id)]) {
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
    el('div', cls: 'pad', children: [
      button(
        cls: 'text-button',
        onTap: () {
          trip.coverId = photo.id;
          ui.changed();
          ui.toast('Fotografija je na razglednici.');
        },
        children: [
          icon('photo', size: 20),
          web.document.createTextNode(
              onCard ? 'Ova je fotografija na razglednici' : 'Stavi na razglednicu'),
        ],
      ),
    ]),
    sectionTitle('Komentari'),
    if (photo.comments.isEmpty)
      el('p', cls: 'soft pad', text: 'Budi prvi koji će nešto napisati.'),
    for (final comment in photo.comments.where((c) => c.replyTo == null)) ...[
      _commentRow(ui, trip, comment, me, comment.id),
      for (final reply in photo.comments.where((c) => c.replyTo == comment.id))
        _commentRow(ui, trip, reply, me, comment.id, isReply: true),
    ],
    if (ui.replyingTo != null)
      el('div', cls: 'row', children: [
        el('div', cls: 'grow small', text: 'Pišeš odgovor'),
        chip('Odustani', () {
          ui.replyingTo = null;
          ui.rerender();
        }),
      ]),
    el('div', cls: 'composer', children: [
      el('label', attrs: {'style': 'display:contents'}, children: [message]),
      button(
        cls: 'send',
        ariaLabel: 'Pošalji komentar',
        onTap: send,
        children: [icon('send', size: 22)],
      ),
    ]),
  ]);
}
