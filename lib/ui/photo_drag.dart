import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

import 'dom.dart';

/// How long a finger rests on a photo before it lifts.
const Duration _holdTime = Duration(milliseconds: 350);

/// A finger that moves this far first is scrolling, not lifting.
const double _stillDistance = 8;

/// Near the ends of what scrolls, it scrolls along.
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

typedef _Point = ({double x, double y});

/// Where the finger is. A phone gives it with decimals, which the web package
/// would wrongly take as whole numbers.
_Point _where(web.PointerEvent event) => (
      x: (event as JSObject).getProperty<JSNumber>('clientX'.toJS).toDartDouble,
      y: (event as JSObject).getProperty<JSNumber>('clientY'.toJS).toDartDouble,
    );

/// Lets [shot] be lifted by a finger held on it and carried. While it is
/// carried, [moving] hears where the finger is; [ended] hears where it was let
/// go, with [dropped] false when the phone took the finger away. Near its ends
/// [row] scrolls along sideways, or the page up and down when there is no row.
/// A quick touch stays a tap, and a finger that moves at once scrolls as usual.
void _liftable(
  web.HTMLElement shot, {
  required void Function(_Point finger) moving,
  required void Function(_Point finger, {required bool dropped}) ended,
  web.HTMLElement? row,
}) {
  Timer? hold;
  Timer? scrolling;
  var start = (x: 0.0, y: 0.0);
  var finger = (x: 0.0, y: 0.0);

  void follow() {
    _ghost?.style.transform = 'translate(${finger.x - 36}px, ${finger.y - 36}px)';
    moving(finger);
  }

  double speed(double at, double from, double to) => at < from + _edge
      ? -(from + _edge - at) / 4
      : at > to - _edge
          ? (at - (to - _edge)) / 4
          : 0.0;

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
      if (row != null) {
        final box = row.getBoundingClientRect();
        final step = speed(finger.x, box.left, box.right);
        if (step == 0) return;
        row.scrollLeft += step;
      } else {
        final step = speed(finger.y, 0, web.window.innerHeight.toDouble());
        if (step == 0) return;
        web.window.scrollBy(0.toJS, step);
      }
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
    _justDropped = true;
    Timer(const Duration(milliseconds: 500), () => _justDropped = false);
    ended(finger, dropped: dropped);
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
    if (_ghost != null) follow();
    end(dropped: true);
  }).toJS);
  shot.addEventListener('pointercancel', ((web.PointerEvent _) => end(dropped: false)).toJS);
  // While a photo is lifted nothing must scroll under the finger.
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

/// Lets [shot] be moved to another day: where it is let go over a box with a
/// `data-day`, [drop] gets that day. The box under the finger is marked.
void movableToDay(web.HTMLElement shot, void Function(int day) drop) {
  web.HTMLElement? over;

  void mark(web.HTMLElement? day) {
    if (day == over) return;
    over?.classList.remove('drop');
    over = day?..classList.add('drop');
  }

  _liftable(
    shot,
    moving: (finger) {
      final under = web.document.elementFromPoint(finger.x, finger.y);
      mark(under?.closest('[data-day]') as web.HTMLElement?);
    },
    ended: (finger, {required dropped}) {
      final day = int.tryParse(over?.getAttribute('data-day') ?? '');
      mark(null);
      if (dropped && day != null) drop(day);
    },
  );
}

/// Lets [thumb], the one at [from] in [row], be put elsewhere in the row: it
/// goes in front of the first picture whose middle is right of the finger, and
/// [move] gets where it was and where it goes. The place it would go is marked.
void reorderable(
  web.HTMLElement thumb,
  web.HTMLElement row,
  int from,
  void Function(int from, int to) move,
) {
  var to = from;

  List<web.HTMLElement> others() => [
        for (var i = 0; i < row.children.length; i++)
          if (row.children.item(i) != thumb) row.children.item(i)! as web.HTMLElement,
      ];

  void clear() {
    for (final other in others()) {
      other.classList
        ..remove('drop-before')
        ..remove('drop-after');
    }
  }

  _liftable(
    thumb,
    row: row,
    moving: (finger) {
      final rest = others();
      to = rest.where((other) {
        final box = other.getBoundingClientRect();
        return box.left + box.width / 2 < finger.x;
      }).length;
      clear();
      if (rest.isEmpty) return;
      to < rest.length
          ? rest[to].classList.add('drop-before')
          : rest.last.classList.add('drop-after');
    },
    ended: (finger, {required dropped}) {
      clear();
      if (dropped && to != from) move(from, to);
    },
  );
}
