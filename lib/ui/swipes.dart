import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'dom.dart';
import 'widgets.dart';

/// A swipe must be this long, in pixels, to change the page.
const double _swipeLength = 60;

/// After this many pixels it is clear whether the finger goes sideways or down.
const double _lockDistance = 10;

/// A swipe from this close to the left edge is an iPhone's way back.
const double _backGestureEdge = 30;

/// How far the page follows the finger when there is no next page.
const double _resistance = 0.25;

const Duration _slideTime = Duration(milliseconds: 80);
const String _slide = 'transform 80ms ease-out';

const Duration glideTime = Duration(milliseconds: 160);

bool get wantsLessMotion =>
    web.window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/// When a swipe last ended on the next page: the page drawn then is already
/// in place, so it comes in with no slide of its own.
DateTime _landedAt = DateTime(2000);

/// Whether the screen being drawn is the end of a swipe that already brought
/// it in place.
bool get justSwiped => DateTime.now().difference(_landedAt) < const Duration(milliseconds: 400);

const Duration _finishTime = Duration(milliseconds: 180);

/// Lets [sliding] follow the finger across [page]. With [peek] the next page
/// comes along beside it, as far as the finger has gone, and [follow] hears
/// how far: 0 to 1 on the way to the page one [step] away, 0 when it goes
/// back. Past the swipe length the page glides the rest of the way and [move]
/// is called with +1 for the next page, -1 for the one before. Lists of chips
/// scroll by themselves, and an open form would lose what was typed in it, so
/// those are left alone.
void followSwipes(
  web.HTMLElement page,
  web.HTMLElement sliding,
  bool Function(int step) canMove,
  void Function(int step) move, {
  web.HTMLElement? Function(int step)? peek,
  void Function(int step, double fraction)? follow,
}) {
  double? startX;
  double startY = 0;
  var sideways = false;
  web.HTMLElement? beside;
  var besideStep = 0;

  void showBeside(int step) {
    if (besideStep == step) return;
    beside?.remove();
    beside = null;
    besideStep = step;
    if (peek == null || !canMove(step)) return;
    final next = peek(step);
    if (next == null) return;
    next.style
      ..position = 'absolute'
      ..top = '0'
      ..left = '${step * 100}%'
      ..width = '100%';
    sliding.style.position = 'relative';
    sliding.append(next);
    beside = next;
    markEdges();
  }

  void clearBeside() {
    beside?.remove();
    beside = null;
    besideStep = 0;
  }

  page.onTouchStart.listen((event) {
    final touch = event.changedTouches.item(0)!;
    final inChips = (event.target as web.Element).closest('.chips') != null;
    // A form with something typed in it would lose it.
    final typed = (web.document.querySelector('.new-kind input') as web.HTMLInputElement?)?.value ?? '';
    final formOpen = web.document.querySelector('details[open]') != null || typed.isNotEmpty;
    final usable = event.touches.length == 1 &&
        touch.clientX >= _backGestureEdge &&
        !inChips &&
        !formOpen;
    startX = usable ? touch.clientX.toDouble() : null;
    startY = touch.clientY.toDouble();
    sideways = false;
  });
  page.onTouchMove.listen((event) {
    final from = startX;
    if (from == null) return;
    if (web.document.querySelector('.drag-ghost') != null) {
      // A photo is being moved to another day: the page stays.
      startX = null;
      sliding.style.transform = '';
      clearBeside();
      return;
    }
    final touch = event.changedTouches.item(0)!;
    final across = touch.clientX - from;
    final down = touch.clientY - startY;
    if (!sideways) {
      if (max(across.abs(), down.abs()) < _lockDistance) return;
      if (across.abs() < down.abs() * 2) {
        startX = null;
        return;
      }
      sideways = true;
      sliding.style.transition = 'none';
    }
    final step = across < 0 ? 1 : -1;
    final free = canMove(step);
    showBeside(step);
    sliding.style.transform = 'translateX(${free ? across : across * _resistance}px)';
    final width = max(sliding.offsetWidth, 1);
    follow?.call(step, free ? min(1, across.abs() / width).toDouble() : 0);
  });

  void goBack(int step) {
    sliding.style
      ..transition = _slide
      ..transform = '';
    follow?.call(step, 0);
    Timer(_slideTime + const Duration(milliseconds: 40), clearBeside);
  }

  page.onTouchEnd.listen((event) {
    final from = startX;
    startX = null;
    if (from == null || !sideways) return;
    final across = event.changedTouches.item(0)!.clientX - from;
    final step = across < 0 ? 1 : -1;
    final done = across.abs() >= _swipeLength && canMove(step);
    if (!done) {
      goBack(step);
      return;
    }
    if (beside == null || wantsLessMotion) {
      clearBeside();
      move(step);
      return;
    }
    // The rest of the way, then the next page is drawn where it already is.
    sliding.style
      ..transition = 'transform ${_finishTime.inMilliseconds}ms ease-out'
      ..transform = 'translateX(${-step * 100}%)';
    follow?.call(step, 1);
    Timer(_finishTime, () {
      _landedAt = DateTime.now();
      move(step);
    });
  });
  page.onTouchCancel.listen((_) {
    startX = null;
    goBack(besideStep == 0 ? 1 : besideStep);
  });
}

/// A green mark that goes with a swipe from the chosen choice of [row] to the
/// next, as far as the swipe has gone: the line under a tab ([line]) or the
/// fill behind a chip, the row turning with it.
class SwipeMark {
  SwipeMark(this.row, {this.line = false});

  final web.HTMLElement row;
  final bool line;
  web.HTMLElement? _mark;
  web.HTMLElement? _words;
  double _scroll = 0;

  web.HTMLElement? get _chosen =>
      row.querySelector(line ? '.tab.on' : '.chip.on') as web.HTMLElement?;

  /// Moves the mark [fraction] of the way to [to].
  void follow(web.HTMLElement? to, double fraction) {
    final from = _chosen;
    if (from == null || to == null || fraction <= 0) {
      clear();
      return;
    }
    var mark = _mark;
    if (mark == null) {
      mark = el('span', cls: line ? 'tab-line' : 'chip-marker carrying');
      if (!line) {
        // The same chips again inside the green, dark, laid exactly over the
        // row's own: only what the green covers of them shows.
        final words = (row.cloneNode(true) as web.HTMLElement)
          ..className = 'chips marker-words'
          ..removeAttribute('data-edges')
          ..style.width = '${row.scrollWidth}px';
        mark.style
          ..top = '${from.offsetTop}px'
          ..height = '${from.offsetHeight}px'
          ..borderRadius = web.window.getComputedStyle(from).borderRadius;
        mark.append(words);
        _words = words;
        row.classList.add('glide-start');
      }
      row
        ..append(mark)
        ..classList.add('gliding');
      _scroll = row.scrollLeft.toDouble();
      _mark = mark;
    }
    final left = from.offsetLeft + (to.offsetLeft - from.offsetLeft) * fraction;
    mark.style
      ..left = '${left}px'
      ..width = '${from.offsetWidth + (to.offsetWidth - from.offsetWidth) * fraction}px';
    _words?.style
      ?..left = '${-left}px'
      ..top = '${-from.offsetTop}px';
    if (!line) {
      final most = max(row.scrollWidth - row.clientWidth, 0).toDouble();
      final centred = (to.offsetLeft - (row.clientWidth - to.offsetWidth) / 2).clamp(0.0, most);
      row.scrollLeft = _scroll + (centred - _scroll) * fraction;
    }
  }

  /// Takes the mark away, the row as it was.
  void clear() {
    final mark = _mark;
    if (mark == null) return;
    mark.remove();
    _mark = null;
    _words = null;
    row.classList
      ..remove('gliding')
      ..remove('glide-start');
    row.scrollLeft = _scroll;
  }
}

/// Brings the freshly drawn page in from the side the swipe came from.
void slideIn(int step) {
  final fresh = web.document.querySelector('.slide-page') as web.HTMLElement?;
  if (fresh == null || wantsLessMotion || justSwiped) return;
  fresh.style
    ..transition = 'none'
    ..transform = 'translateX(${step * 100}%)';
  fresh.getBoundingClientRect(); // so that the browser sees where it starts
  fresh.style
    ..transition = _slide
    ..transform = '';
  // Should the animation not run, the page must still end up in its place.
  Timer(_slideTime * 2, () => fresh.style.transition = 'none');
}

/// Calls [frame] with the progress, from 0 to 1, on every frame for [length],
/// then [end]. A hidden page gets no frames, so a timer makes sure it ends.
void animate(Duration length, void Function(double progress) frame, void Function() end) {
  final started = web.window.performance.now();
  var finished = false;

  void finish() {
    if (finished) return;
    finished = true;
    frame(1);
    end();
  }

  void tick(double now) {
    if (finished) return;
    final time = (now - started) / length.inMilliseconds;
    if (time >= 1) {
      finish();
    } else {
      frame(1 - pow(1 - max(time, 0), 3).toDouble());
      web.window.requestAnimationFrame(tick.toJS);
    }
  }

  web.window.requestAnimationFrame(tick.toJS);
  Timer(length * 2, finish);
}
