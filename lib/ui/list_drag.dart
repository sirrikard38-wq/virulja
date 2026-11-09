import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

/// How long a finger rests on a card before it lifts.
const Duration _holdTime = Duration(milliseconds: 400);

/// A finger that moves this far first is scrolling, not lifting.
const double _stillDistance = 8;

/// Near the top or bottom of the screen, the page scrolls along.
const double _edge = 70;

/// The space between two cards.
const double _gap = 10;

/// Where the finger is, down the page. A phone gives it with decimals, which
/// the web package would wrongly take as whole numbers.
double _pageY(web.PointerEvent event) =>
    (event as JSObject).getProperty<JSNumber>('clientY'.toJS).toDartDouble + web.window.scrollY;

double _pageX(web.PointerEvent event) =>
    (event as JSObject).getProperty<JSNumber>('clientX'.toJS).toDartDouble;

/// Lets [card], one of [cards] as they stand one under another, be held and
/// carried up or down among them. While it is carried it follows the finger and
/// the others make room; let go, [move] gets where it was and where it goes.
/// A quick touch stays a tap, and a finger that moves at once scrolls as usual.
void movableUpDown(
  web.HTMLElement card,
  List<web.HTMLElement> cards,
  void Function(int from, int to) move,
) {
  final from = cards.indexOf(card);
  Timer? hold;
  Timer? scrolling;
  var lifted = false;
  var justMoved = false;
  var startX = 0.0, startY = 0.0, fingerY = 0.0, fingerClient = 0.0;
  var to = from;
  var middles = <double>[];
  var step = 0.0;

  void place() {
    final moved = fingerY - startY;
    card.style.transform = 'translateY(${moved}px)';
    final middle = middles[from] + moved;
    to = from;
    for (var i = 0; i < cards.length; i++) {
      if (i < from && middle < middles[i]) to = min(to, i);
      if (i > from && middle > middles[i]) to = max(to, i);
    }
    for (var i = 0; i < cards.length; i++) {
      if (i == from) continue;
      final shift = from < i && i <= to
          ? -step
          : to <= i && i < from
              ? step
              : 0.0;
      cards[i].style.transform = shift == 0 ? '' : 'translateY(${shift}px)';
    }
  }

  void lift(int pointer) {
    lifted = true;
    middles = [
      for (final each in cards)
        each.getBoundingClientRect().top + web.window.scrollY + each.offsetHeight / 2,
    ];
    step = card.offsetHeight + _gap;
    card.classList.add('carried');
    for (final each in cards) {
      if (each != card) each.classList.add('making-room');
    }
    try {
      card.setPointerCapture(pointer);
      web.window.navigator.vibrate(15.toJS);
    } on Object {
      // Not every browser can: the move still works.
    }
    scrolling = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final height = web.window.innerHeight.toDouble();
      final speed = fingerClient < _edge
          ? -(_edge - fingerClient) / 4
          : fingerClient > height - _edge
              ? (fingerClient - (height - _edge)) / 4
              : 0.0;
      if (speed == 0) return;
      final before = web.window.scrollY;
      web.window.scrollBy(0.toJS, speed);
      fingerY += web.window.scrollY - before;
      place();
    });
    place();
  }

  void end({required bool dropped}) {
    hold?.cancel();
    hold = null;
    if (!lifted) return;
    lifted = false;
    scrolling?.cancel();
    justMoved = true;
    Timer(const Duration(milliseconds: 400), () => justMoved = false);
    card.classList.remove('carried');
    for (final each in cards) {
      each.classList.remove('making-room');
      each.style.transform = '';
    }
    if (dropped && to != from) move(from, to);
  }

  card.addEventListener('pointerdown', ((web.PointerEvent event) {
    if (event.button != 0) return;
    startX = _pageX(event);
    startY = fingerY = _pageY(event);
    fingerClient = fingerY - web.window.scrollY;
    final pointer = event.pointerId;
    hold?.cancel();
    hold = Timer(_holdTime, () {
      hold = null;
      lift(pointer);
    });
  }).toJS);
  card.addEventListener('pointermove', ((web.PointerEvent event) {
    fingerY = _pageY(event);
    fingerClient = fingerY - web.window.scrollY;
    if (!lifted) {
      final moved = max((_pageX(event) - startX).abs(), (fingerY - startY).abs());
      if (moved > _stillDistance) {
        hold?.cancel();
        hold = null;
      }
      return;
    }
    place();
  }).toJS);
  card.addEventListener('pointerup', ((web.PointerEvent _) => end(dropped: true)).toJS);
  card.addEventListener('pointercancel', ((web.PointerEvent _) => end(dropped: false)).toJS);
  // While a card is carried nothing must scroll under the finger.
  card.addEventListener(
    'touchmove',
    ((web.TouchEvent event) {
      if (lifted) event.preventDefault();
    }).toJS,
    web.AddEventListenerOptions(passive: false),
  );
  // The tap a move ends with opens nothing.
  card.addEventListener(
    'click',
    ((web.Event event) {
      if (!justMoved) return;
      justMoved = false;
      event
        ..stopPropagation()
        ..preventDefault();
    }).toJS,
    web.AddEventListenerOptions(capture: true),
  );
  // A held finger would otherwise open the phone's menu.
  card.addEventListener('contextmenu', ((web.Event event) => event.preventDefault()).toJS);
}
