import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import '../src/domain/show.dart';
import 'context.dart';
import 'dom.dart';
import 'swipes.dart';

/// Plays a presentation in a box. The picture at any moment follows only from the
/// time since it started, so a redraw of the screen can take the same player into
/// the new screen and it goes on without a jump.
class ShowPlayer {
  ShowPlayer(this._ui, this._trip, this._slides, {double from = 0, this.key = ''})
      : _started = DateTime.now().subtract(Duration(milliseconds: (from * 1000).round()));

  final Ui _ui;
  final Trip _trip;
  final List<Slide> _slides;
  final DateTime _started;

  /// What it plays, to know whether a redraw can keep it.
  final String key;
  final web.HTMLElement element = el('div', cls: 'show-player');
  final Map<String, web.HTMLImageElement> _pictures = {};
  final Set<web.HTMLImageElement> _shown = {};
  late final JSFunction _onFrame = _frame.toJS;
  bool _running = false;

  web.HTMLImageElement _picture(String id) => _pictures.putIfAbsent(id, () {
        final image = el('img', attrs: {'alt': ''}) as web.HTMLImageElement;
        _ui.imageAddress(_trip, id).then((address) {
          if (address != null) image.src = address;
        });
        element.append(image);
        return image;
      });

  /// Starts drawing, or goes on after the player was off the screen.
  void start() {
    if (_running) return;
    _running = true;
    web.window.requestAnimationFrame(_onFrame);
  }

  void _frame(double _) {
    if (!element.isConnected) {
      _running = false;
      return;
    }
    _draw();
    web.window.requestAnimationFrame(_onFrame);
  }

  void _draw() {
    if (_slides.isEmpty) return;
    final seconds = DateTime.now().difference(_started).inMilliseconds / 1000;
    final frame = frameAt(_slides, seconds);
    final slide = _slides[frame.index];
    final previous = frame.previous;
    final incoming = _picture(slide.photoId);
    final outgoing = previous == null || previous == frame.index || frame.progress >= 1
        ? null
        : _picture(_slides[previous].photoId);
    _picture(_slides[(frame.index + 1) % _slides.length].photoId); // ready in time
    for (final image in _shown) {
      if (image != incoming && image != outgoing) image.style.display = 'none';
    }
    _shown
      ..clear()
      ..add(incoming);
    if (outgoing != null) _shown.add(outgoing);
    _plain(incoming, 2);
    if (outgoing != null) _plain(outgoing, 1);
    final progress = wantsLessMotion ? 1.0 : _ease(frame.progress);
    if (progress < 1) _move(slide.look.transition, progress, incoming, outgoing);
  }
}

void _plain(web.HTMLElement image, int layer) {
  image.style
    ..display = 'block'
    ..zIndex = '$layer'
    ..setProperty('opacity', '1')
    ..setProperty('transform', 'none')
    ..setProperty('clip-path', 'none')
    ..setProperty('filter', 'none');
}

/// Slow at both ends, like a slide changing in PowerPoint.
double _ease(double t) => t < .5 ? 4 * t * t * t : 1 - _cube(-2 * t + 2) / 2;

double _cube(double x) => x * x * x;

String _n(double value) => value.toStringAsFixed(3);

/// One moment of [kind], [p] of the way from the photo [outgoing] to [incoming].
/// Before the very first photo there is none: it comes out of black.
void _move(Transition kind, double p, web.HTMLElement incoming, web.HTMLElement? outgoing) {
  void into(String name, String value) => incoming.style.setProperty(name, value);
  void out(String name, String value) => outgoing?.style.setProperty(name, value);
  final q = 1 - p;
  switch (kind) {
    case Transition.fade:
      into('opacity', _n(p));
    case Transition.push:
      into('transform', 'translateX(${_n(q * 100)}%)');
      out('transform', 'translateX(${_n(-p * 100)}%)');
    case Transition.wipe:
      into('clip-path', 'inset(0 ${_n(q * 100)}% 0 0)');
    case Transition.zoom:
      into('opacity', _n(p));
      into('transform', 'scale(${_n(1.3 - .3 * p)})');
    case Transition.circle:
      into('clip-path', 'circle(${_n(p * 75)}% at 50% 50%)');
    case Transition.pushUp:
      into('transform', 'translateY(${_n(q * 100)}%)');
      out('transform', 'translateY(${_n(-p * 100)}%)');
    case Transition.cover:
      into('transform', 'translateX(${_n(q * 100)}%)');
    case Transition.uncover:
      outgoing?.style.zIndex = '3';
      out('transform', 'translateX(${_n(-p * 100)}%)');
    case Transition.split:
      into('clip-path', 'inset(0 ${_n(q * 50)}% 0 ${_n(q * 50)}%)');
    case Transition.diamond:
      final r = p * 100;
      into('clip-path',
          'polygon(50% ${_n(50 - r)}%, ${_n(50 + r)}% 50%, 50% ${_n(50 + r)}%, ${_n(50 - r)}% 50%)');
    case Transition.black:
      if (p < .5) {
        into('opacity', '0');
        out('opacity', _n(1 - 2 * p));
      } else {
        out('opacity', '0');
        into('opacity', _n(2 * p - 1));
      }
    case Transition.flip:
      if (p < .5) {
        into('opacity', '0');
        out('transform', 'perspective(900px) rotateY(${_n(p * 180)}deg)');
      } else {
        out('opacity', '0');
        into('transform', 'perspective(900px) rotateY(${_n((p - 1) * 180)}deg)');
      }
    case Transition.blur:
      into('opacity', _n(p));
      into('filter', 'blur(${_n(q * 14)}px)');
      out('filter', 'blur(${_n(p * 14)}px)');
    case Transition.spin:
      into('opacity', _n(p));
      into('transform', 'rotate(${_n(-q * 200)}deg) scale(${_n(.2 + .8 * p)})');
    case Transition.zoomOut:
      outgoing?.style.zIndex = '3';
      out('transform', 'scale(${_n(1 + .5 * p)})');
      out('opacity', _n(q));
  }
}

/// The players a redraw hands on, by where they play: the cover of a trip, or the
/// whole screen.
final Map<String, ShowPlayer> _kept = {};

/// Lets the next presentation shown at [place] start from its beginning.
void forgetPlayer(String place) => _kept.remove(place);

/// The player of [show] for [place]. It stays the same across redraws as long as
/// the presentation does not change, so it does not start again.
ShowPlayer keptPlayer(Ui ui, Trip trip, Show show, String place) {
  final slides = slidesOf(trip, show);
  final key = '${trip.id} ${show.id} ${Object.hashAll([
    for (final slide in slides) ...[slide.photoId, slide.look.transition, slide.look.extra],
  ])}';
  final known = _kept[place];
  if (known != null && known.key == key) return known..start();
  return _kept[place] = ShowPlayer(ui, trip, slides, key: key)..start();
}
