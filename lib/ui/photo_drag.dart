import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'dom.dart';

/// How long a finger rests on a photo before it lifts.
const Duration _holdTime = Duration(milliseconds: 350);

/// A finger that moves this far first is scrolling the page, not lifting.
const double _stillDistance = 8;

/// Near the top or the bottom of the screen the page scrolls along.
const double _edge = 70;

/// The photo that follows the finger while one is moved.
web.HTMLElement? _ghost;

/// Set when a photo was just let go, so that the tap the finger ends with does
/// not also open it.
bool _justDropped = false;

/// True once after a photo was moved: the tap that ends a move is not a tap.
bool tapEndsMove() {
  final was = _justDropped;
  _justDropped = false;
  return was;
}

/// Where the finger is. A phone gives it with decimals, which the web package
/// would wrongly take as whole numbers.
({double x, double y}) _where(web.PointerEvent event) => (
      x: (event as JSObject).getProperty<JSNumber>('clientX'.toJS).toDartDouble,
      y: (event as JSObject).getProperty<JSNumber>('clientY'.toJS).toDartDouble,
    );

/// Lets [shot] be moved to another day: a finger held on it lifts it, the page
/// scrolls along near the edges, and where it is let go over a box with a
/// `data-day`, [drop] gets that day. A quick touch stays a tap, and a finger that
/// moves at once scrolls the page as usual.
void movableToDay(web.HTMLElement shot, void Function(int day) drop) {
  Timer? hold;
  Timer? scrolling;
  var start = (x: 0.0, y: 0.0);
  var finger = (x: 0.0, y: 0.0);
  web.HTMLElement? over;

  void mark(web.HTMLElement? day) {
    if (day == over) return;
    over?.classList.remove('drop');
    over = day?..classList.add('drop');
  }

  void follow() {
    final ghost = _ghost;
    if (ghost == null) return;
    ghost.style.transform = 'translate(${finger.x - 36}px, ${finger.y - 36}px)';
    final under = web.document.elementFromPoint(finger.x, finger.y);
    mark(under?.closest('[data-day]') as web.HTMLElement?);
  }

  void lift(int pointer) {
    final picture = shot.querySelector('img');
    _ghost = el('div', cls: 'drag-ghost', children: [
      if (picture != null) picture.cloneNode(true) as web.HTMLElement,
    ]);
    web.document.body!.append(_ghost!);
    shot.classList.add('lifted');
    try {
      shot.setPointerCapture(pointer);
      web.window.navigator.vibrate(15.toJS);
    } on Object {
      // Not every browser can: the move still works.
    }
    follow();
    scrolling = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final height = web.window.innerHeight;
      final speed = finger.y < _edge
          ? -(_edge - finger.y) / 4
          : finger.y > height - _edge
              ? (finger.y - (height - _edge)) / 4
              : 0.0;
      if (speed == 0) return;
      web.window.scrollBy(0.toJS, speed);
      follow();
    });
  }

  void end({required bool dropped}) {
    hold?.cancel();
    hold = null;
    final ghost = _ghost;
    if (ghost == null) return;
    scrolling?.cancel();
    ghost.remove();
    _ghost = null;
    shot.classList.remove('lifted');
    final day = int.tryParse(over?.getAttribute('data-day') ?? '');
    mark(null);
    _justDropped = true;
    Timer(const Duration(milliseconds: 500), () => _justDropped = false);
    if (dropped && day != null) drop(day);
  }

  shot.addEventListener('pointerdown', ((web.PointerEvent event) {
    if (event.button != 0) return;
    start = finger = _where(event);
    final pointer = event.pointerId;
    hold?.cancel();
    hold = Timer(_holdTime, () {
      hold = null;
      lift(pointer);
    });
  }).toJS);
  shot.addEventListener('pointermove', ((web.PointerEvent event) {
    finger = _where(event);
    if (_ghost == null) {
      final moved = max((finger.x - start.x).abs(), (finger.y - start.y).abs());
      if (moved > _stillDistance) {
        hold?.cancel();
        hold = null;
      }
      return;
    }
    follow();
  }).toJS);
  shot.addEventListener('pointerup', ((web.PointerEvent event) {
    finger = _where(event);
    follow();
    end(dropped: true);
  }).toJS);
  shot.addEventListener('pointercancel', ((web.PointerEvent _) => end(dropped: false)).toJS);
  // While a photo is lifted the page must not scroll under the finger.
  shot.addEventListener(
    'touchmove',
    ((web.TouchEvent event) {
      if (_ghost != null) event.preventDefault();
    }).toJS,
    web.AddEventListenerOptions(passive: false),
  );
  // A held finger would otherwise open the phone's menu for the picture.
  shot.addEventListener('contextmenu', ((web.Event event) => event.preventDefault()).toJS);
}
