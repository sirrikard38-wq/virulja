import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'anthem.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'media.dart';
import 'widgets.dart';

/// The name of a song file, without its ending.
String _songName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(0, dot) : fileName;
}

web.HTMLElement _anthemCard(Ui ui, Trip trip, void Function(Trip) playAnthem) {
  // No file filter: on many phones an audio filter hides downloaded mp3s.
  final picker = el('input', cls: 'file', attrs: {
    'type': 'file',
  }) as web.HTMLInputElement;
  picker.onChange.listen((_) async {
    final files = pickedFiles(picker);
    if (files.isEmpty) return;
    ui.toast('Pripremam himnu...');
    try {
      final clip = await ui.anthem.firstSeconds(files.first);
      final id = ui.store.newId();
      await ui.store.putBlob(id, wavBlob(clip));
      final old = trip.anthemClipId;
      trip
        ..anthemClipId = id
        ..anthemTitle = _songName(files.first.name);
      if (old != null) ui.store.removeBlob(old);
      ui.changed();
      ui.toast('Himna je spremljena.');
    } on Object {
      ui.toast('Tu pjesmu ne mogu pročitati. Probaj mp3 ili m4a.');
    }
  });
  final title = trip.anthemTitle;
  return el('div', cls: 'anthem card', children: [
    el('div', cls: 'small', text: 'Himna putovanja'),
    el('div', cls: 'title', text: title ?? 'Još nema himne',
        attrs: {'style': 'font-size:26px;overflow-wrap:anywhere'}),
    el('div', cls: 'gap-top', attrs: {'style': 'display:flex;gap:8px'}, children: [
      if (title != null)
        button(
          cls: 'secondary',
          onTap: () {
            ui.anthem.wake();
            playAnthem(trip);
          },
          children: [
            icon('play', size: 20),
            web.document.createTextNode('Poslušaj'),
          ],
        ),
      el('label', cls: 'secondary', children: [
        picker,
        web.document.createTextNode(title == null ? 'Učitaj pjesmu' : 'Promijeni himnu'),
      ]),
    ]),
  ]);
}

web.HTMLElement _addSong(Ui ui, Trip trip) {
  final link = input(type: 'url');
  final title = input();
  final error = errorLine();

  void add() {
    final address = link.value.trim();
    final player = playerFor(address);
    if (player == null) {
      error.textContent = 'Zalijepi link sa Spotifyja, YouTubea ili Apple Musica.';
      return;
    }
    final name = title.value.trim();
    trip.songs.add(Song(
      id: ui.store.newId(),
      title: name.isEmpty ? 'Pjesma (${player.service})' : name,
      link: address,
      addedBy: ui.meIn(trip),
    ));
    ui.changed();
  }

  return adder('Dodaj pjesmu', [
    field('Link', link),
    field('Naziv', title),
    error,
    primaryButton('Dodaj pjesmu', add),
  ]);
}

/// Marks the whole queue as what is playing, in place of one song.
const String _queueId = 'red';

/// "Pusti sve" and "Nasumično", with the queue's player once it runs.
web.HTMLElement _queue(Ui ui, Trip trip) {
  void start({required bool shuffled}) {
    final links = [for (final song in trip.songs) song.link];
    if (shuffled) links.shuffle();
    final address = youTubeQueue(links);
    if (address == null) {
      ui.toast('Red radi samo s YouTube pjesmama.');
      return;
    }
    ui.anthem.stop();
    ui.queueAddress = address;
    ui.toast('Pritisni play u playeru.');
    ui.playingSongId = _queueId;
    ui.rerender();
  }

  final address = ui.queueAddress;
  return el('div', attrs: {'style': 'margin-bottom:16px'}, children: [
    el('div', cls: 'two', children: [
      secondaryButton('Pusti sve', () => start(shuffled: false)),
      secondaryButton('Nasumično', () => start(shuffled: true)),
    ]),
    if (ui.playingSongId == _queueId && address != null)
      _player(SongPlayer('YouTube', address, 200)),
  ]);
}

/// The service's own player; the song plays inside the app.
web.HTMLElement _player(SongPlayer player) => el('iframe', cls: 'player', attrs: {
      'src': player.address,
      'height': '${player.height}',
      'title': 'Player: ${player.service}',
      'allow': 'autoplay; clipboard-write; encrypted-media; fullscreen; picture-in-picture',
      'loading': 'lazy',
      'referrerpolicy': 'strict-origin-when-cross-origin',
    });

web.HTMLElement _songRow(Ui ui, Trip trip, Song song) {
  final player = playerFor(song.link);
  final playing = ui.playingSongId == song.id;

  void toggle() {
    ui.anthem.stop();
    ui.playingSongId = playing ? null : song.id;
    ui.rerender();
  }

  return el('div', children: [
    el('div', cls: 'row', attrs: {'style': 'padding:2px 0'}, children: [
      button(
        cls: 'icon-button',
        ariaLabel: playing ? 'Zatvori ${song.title}' : 'Pusti ${song.title}',
        onTap: toggle,
        children: [icon(playing ? 'minus' : 'play')],
      ),
      el('div', cls: 'grow', attrs: {'style': 'cursor:pointer'}, children: [
        el('div', cls: 'label', text: song.title),
        el('div', cls: 'small', text: '${player?.service ?? 'Link'} · ${ui.nameOf(song.addedBy)}'),
      ])
        ..onClick.listen((_) => toggle()),
      removeButton(song.title, () {
        trip.songs.remove(song);
        if (playing) ui.playingSongId = null;
        ui.changed();
      }),
    ]),
    if (playing && player != null) _player(player),
  ]);
}

web.HTMLElement playlistScreen(Ui ui, Trip trip, void Function(Trip) playAnthem) =>
    el('div', children: [
      topBar('Playlista'),
      el('p', cls: 'soft pad', text: '${trip.city} · ${songsCount(trip.songs.length)}',
          attrs: {'style': 'margin-bottom:8px'}),
      _anthemCard(ui, trip, playAnthem),
      sectionTitle('Pjesme'),
      if (trip.songs.isEmpty)
        el('p', cls: 'soft pad', text: 'Dodajte linkove pjesama koje vas podsjećaju na ovo putovanje.'),
      if (trip.songs.isNotEmpty) _queue(ui, trip),
      for (final song in trip.songs) _songRow(ui, trip, song),
      _addSong(ui, trip),
    ]);
