import 'dart:async';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../src/domain/wav.dart';

/// Plays a trip's anthem: its first seconds, quietly, in the background.
///
/// The sound goes through a gain node of an audio context. A plain <audio>
/// element would not do: iPhones ignore its volume setting.
class AnthemPlayer {
  /// Background level, well under the phone's own volume.
  static const double quiet = 0.28;
  static const double _fadeIn = 1.5;
  static const double _fadeOut = 5;

  /// Clips are small: one channel, enough quality for 10 seconds of music.
  static const int _clipRate = 22050;
  static const Duration _tick = Duration(milliseconds: 100);

  web.AudioContext? _context;
  web.AudioBufferSourceNode? _source;
  Timer? _ticker;

  /// How far the anthem is, from 0 to 1, and 0 again when it stops.
  void Function(double progress)? onProgress;

  bool get isPlaying => _source != null;

  /// Phones only let a page make sound from a context a tap has woken, so this
  /// is called right inside the tap that opens a trip.
  void wake() {
    try {
      _context ??= web.AudioContext();
      if (_context!.state != 'running') _context!.resume();
    } on Object {
      // No sound on this device: the app works without it.
    }
  }

  /// Plays the clip in [wav]. Failing quietly is fine: it is only an extra.
  Future<void> play(web.Blob wav) async {
    stop();
    final context = _context;
    if (context == null) return;
    try {
      final bytes = await wav.arrayBuffer().toDart;
      final sound = await context.decodeAudioData(bytes).toDart;
      final gain = context.createGain();
      // Rises gently, then a long fade to silence, so it never starts or stops
      // abruptly.
      final begin = context.currentTime;
      final finish = begin + sound.duration;
      gain.gain
        ..setValueAtTime(0, begin)
        ..linearRampToValueAtTime(quiet, begin + _fadeIn)
        ..setValueAtTime(quiet, finish - _fadeOut)
        ..linearRampToValueAtTime(0, finish);
      gain.connect(context.destination);
      final source = context.createBufferSource()
        ..buffer = sound
        ..connect(gain);
      source.start();
      _source = source;
      final started = DateTime.now();
      final length = sound.duration * 1000;
      _ticker = Timer.periodic(_tick, (_) {
        final passed = DateTime.now().difference(started).inMilliseconds;
        if (passed >= length) {
          stop();
        } else {
          onProgress?.call(passed / length);
        }
      });
    } on Object {
      stop();
    }
  }

  void stop() {
    _ticker?.cancel();
    _ticker = null;
    try {
      _source?.stop();
    } on Object {
      // It had already ended.
    }
    _source = null;
    onProgress?.call(0);
  }

  /// The very start of the song in [file], as a small WAV. Throws if the file
  /// is not a song this phone can read.
  Future<Uint8List> firstSeconds(web.File file) async {
    final context = _context ??= web.AudioContext();
    final song = await context
        .decodeAudioData(await file.arrayBuffer().toDart)
        .toDart;
    final seconds = min(song.duration, anthemLength.inSeconds.toDouble());
    final length = (seconds * _clipRate).round();
    final render = web.OfflineAudioContext(1.toJS, length, _clipRate);
    final source = render.createBufferSource()
      ..buffer = song
      ..connect(render.destination);
    source.start();
    final clip = await render.startRendering().toDart;
    return encodeWav(clip.getChannelData(0).toDart, _clipRate);
  }
}

/// A WAV clip as something the browser can store and play.
web.Blob wavBlob(Uint8List bytes) => web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'audio/wav'),
    );
