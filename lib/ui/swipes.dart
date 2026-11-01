import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

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

/// Lets [sliding] follow the finger across [page]. Past the swipe length [move]
/// is called at once, with +1 for the next page, -1 for the one before. Lists of
/// chips scroll by themselves, and an open form would lose what was typed in it,
/// so those are left alone.
void followSwipes(
  web.HTMLElement page,
  web.HTMLElement sliding,
  bool Function(int step) canMove,
  void Function(int step) move,
) {
  double? startX;
  double startY = 0;
  var sideways = false;

  page.onTouchStart.listen((event) {
    final touch = event.changedTouches.item(0)!;
    final inChips = (event.target as web.Element).closest('.chips') != null;
    final formOpen = web.document.querySelector('details[open], .new-kind') != null;
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
    final free = canMove(across < 0 ? 1 : -1);
    sliding.style.transform = 'translateX(${free ? across : across * _resistance}px)';
  });
  page.onTouchEnd.listen((event) {
    final from = startX;
    startX = null;
    if (from == null || !sideways) return;
    final across = event.changedTouches.item(0)!.clientX - from;
    final step = across < 0 ? 1 : -1;
    final done = across.abs() >= _swipeLength && canMove(step);
    if (done) {
      move(step);
    } else {
      sliding.style
        ..transition = _slide
        ..transform = '';
    }
  });
  page.onTouchCancel.listen((_) {
    startX = null;
    sliding.style
      ..transition = _slide
      ..transform = '';
  });
}

/// Brings the freshly drawn page in from the side the swipe came from.
void slideIn(int step) {
  final fresh = web.document.querySelector('.slide-page') as web.HTMLElement?;
  if (fresh == null || wantsLessMotion) return;
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
