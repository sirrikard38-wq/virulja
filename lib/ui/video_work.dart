import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/trip_tree.dart';
import 'context.dart';
import 'dom.dart';
import 'media.dart';
import 'widgets.dart';

/// A video straight from a phone would fill the group's free storage after a few
/// dozen, so only this much is kept: 3 to 6 MB. A browser can only make a video
/// smaller by playing it into a smaller picture, so this also takes as long as
/// the video, with the app open.
const int _maxSeconds = 30;
const int _longSide = 854;
const int _videoBits = 900000;
const int _audioBits = 64000;
const int _framesPerSecond = 30;

/// The picture for the grid comes from here, past a dark first frame.
const double _posterAt = 0.5;

/// How long a file may take to show what it is.
const Duration _loadTime = Duration(seconds: 20);

web.Event _noEvent(web.Event event) => event;

Future<web.Event> _next(web.EventTarget target, String name) =>
    web.EventStreamProvider<web.Event>(name).forTarget(target).map(_noEvent).first;

/// What this phone can record into, the kind every phone can play first.
String? _clipType() {
  try {
    for (final type in ['video/mp4', 'video/webm']) {
      if (web.MediaRecorder.isTypeSupported(type)) return type;
    }
  } on Object {
    // No recording on this phone at all.
  }
  return null;
}

int _even(double size) => max(2, (size / 2).round() * 2);

/// Stands over the app while picked videos are made small, one after another. It
/// waits for a tap, because only a tap lets a phone play with sound.
class _VideoWork {
  _VideoWork(this.ui, this.files, this.addedBy, this.type);

  final Ui ui;
  final List<web.File> files;
  final String addedBy;
  final String type;

  final web.HTMLVideoElement _player =
      el('video', cls: 'video-source', attrs: {'playsinline': ''}) as web.HTMLVideoElement;
  final web.HTMLCanvasElement _canvas = el('canvas') as web.HTMLCanvasElement;
  final web.HTMLElement _status = el('p', cls: 'soft');
  final Completer<bool> _answer = Completer();
  late final web.HTMLElement _screen;
  late final web.AudioContext _audio;
  late final web.MediaStreamAudioDestinationNode _sound;
  web.WakeLockSentinel? _awake;
  Completer<void> _recording = Completer();
  bool _left = false;
  bool _gaveUp = false;

  void _stopRecording() {
    if (!_recording.isCompleted) _recording.complete();
  }

  void _giveUp() {
    if (!_answer.isCompleted) _answer.complete(false);
    _gaveUp = true;
    _stopRecording();
  }

  /// The tap: everything that needs one happens here.
  void _begin() {
    _audio = web.AudioContext()..resume();
    _sound = _audio.createMediaStreamDestination();
    _audio.createMediaElementSource(_player).connect(_sound);
    _player.load();
    _screen.classList.add('working');
    _answer.complete(true);
  }

  Future<void> _keepAwake() async {
    try {
      _awake = await web.window.navigator.wakeLock.request('screen').toDart;
    } on Object {
      // Not every phone can.
    }
  }

  Future<void> _play() async {
    try {
      await _player.play().toDart;
    } on Object {
      _player.muted = true; // better a silent video than none
      await _player.play().toDart;
    }
  }

  Future<Photo> _prepare(web.File file, int index) async {
    final address = web.URL.createObjectURL(file);
    try {
      final broken = _next(_player, 'error').then<void>((_) => throw StateError('unreadable'));
      _player.src = address;
      await Future.any([_next(_player, 'loadedmetadata'), broken]).timeout(_loadTime);
      final scale = min(1.0, _longSide / max(_player.videoWidth, _player.videoHeight));
      final width = _even(_player.videoWidth * scale);
      final height = _even(_player.videoHeight * scale);
      _canvas
        ..width = width
        ..height = height;
      final context = _canvas.getContext('2d') as web.CanvasRenderingContext2D;
      final stream = _canvas.captureStream(_framesPerSecond);
      for (final track in _sound.stream.getAudioTracks().toDart) {
        stream.addTrack(track);
      }
      final pieces = <web.Blob>[];
      final recorder = web.MediaRecorder(
        stream,
        web.MediaRecorderOptions(
          mimeType: type,
          videoBitsPerSecond: _videoBits,
          audioBitsPerSecond: _audioBits,
        ),
      );
      recorder.addEventListener(
        'dataavailable',
        ((web.BlobEvent event) {
          if (event.data.size > 0) pieces.add(event.data);
        }).toJS,
      );
      final stopped = _next(recorder, 'stop');
      _recording = Completer();
      await _play();
      recorder.start(1000);

      final length = _player.duration.isFinite
          ? min(_player.duration, _maxSeconds.toDouble())
          : _maxSeconds.toDouble();
      final shown = files.length > 1 ? '${index + 1}/${files.length} · ' : '';
      Future<web.ImageBitmap>? poster;

      void draw(double now) {
        if (_recording.isCompleted) return;
        context.drawImage(_player, 0, 0, width, height);
        final at = _player.currentTime;
        if (at >= _posterAt) poster ??= web.window.createImageBitmap(_canvas).toDart;
        _status.textContent =
            shown + tr('Pripremam video: {0} s od {1} s', [at.floor(), length.ceil()]);
        if (_player.ended || at >= length) {
          _stopRecording();
        } else {
          web.window.requestAnimationFrame(draw.toJS);
        }
      }

      web.window.requestAnimationFrame(draw.toJS);
      await Future.any([_recording.future, _next(_player, 'ended')]);
      _stopRecording();
      _player.pause();
      recorder.stop();
      await stopped;
      if (_gaveUp || pieces.isEmpty) throw StateError('no clip');

      final clip = web.Blob(pieces.toJS, web.BlobPropertyBag(type: type));
      final id = ui.store.newId();
      await storeVideo(
        ui.store,
        id,
        clip,
        await (poster ?? web.window.createImageBitmap(_canvas).toDart),
      );
      return Photo(
        id: id,
        takenAt: await videoTakenAt(file),
        addedBy: addedBy,
        videoType: type,
        parts: piecesFor(clip.size.toInt()),
      );
    } finally {
      web.URL.revokeObjectURL(address);
    }
  }

  void _close(JSFunction onHidden) {
    web.document.removeEventListener('visibilitychange', onHidden);
    _screen.remove();
    _awake?.release();
  }

  Future<List<Photo>> run() async {
    _screen = el('div', cls: 'video-work', children: [
      el('div', cls: 'card video-card', children: [
        _canvas,
        _player,
        el('p', cls: 'video-note soft',
            text: tr('Spremit će se prvih {0} sekundi, u manjoj kvaliteti, da stane u besplatni prostor grupe. Priprema traje koliko i video, pa ostani u aplikaciji.', [_maxSeconds])),
        _status,
        primaryButton(tr('Pripremi video'), _begin),
        button(cls: 'text-button', text: tr('Odustani'), onTap: _giveUp),
      ]),
    ]);
    web.document.body!.append(_screen);
    final onHidden = ((web.Event event) {
      if (web.document.visibilityState != 'visible') {
        _left = true;
        _giveUp();
      }
    }).toJS;
    web.document.addEventListener('visibilitychange', onHidden);

    final saved = <Photo>[];
    var failed = 0;
    if (await _answer.future) {
      await _keepAwake();
      for (var i = 0; i < files.length && !_gaveUp; i++) {
        try {
          saved.add(await _prepare(files[i], i));
        } on Object {
          if (!_gaveUp) failed++;
        }
      }
      await _audio.close().toDart;
    }
    _close(onHidden);
    if (_left) {
      ui.toast(tr('Video nije spremljen. Ostani u aplikaciji dok se priprema.'));
    } else if (failed > 0) {
      ui.toast(tr('Ovaj mobitel ne može pripremiti video.'));
    } else if (saved.isNotEmpty) {
      ui.toast(tr('Video je spremljen.'));
    }
    return saved;
  }
}

/// Makes the picked [files] small enough to keep and share. Returns those that
/// could be saved; a phone that cannot do it says so.
Future<List<Photo>> prepareVideos(Ui ui, List<web.File> files, String addedBy) async {
  final type = _clipType();
  if (type == null) {
    ui.toast(tr('Ovaj mobitel ne može pripremiti video.'));
    return const [];
  }
  return _VideoWork(ui, files, addedBy, type).run();
}
