import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/show.dart';
import 'dom.dart';

/// Where the finger is across the screen. A phone gives it with decimals, which
/// the web package would wrongly take as a whole number.
double _across(web.PointerEvent event) =>
    (event as JSObject).getProperty<JSNumber>('clientX'.toJS).toDartDouble;

/// Seconds as the bars write them: one decimal, cut, none when it is 0, and the
/// s right after the number, as in 6s or 7,5s.
String _seconds(double value) => '${tenths(value).replaceFirst(RegExp(r'[,.]0$'), '')}s';

/// Seconds dragged with a finger along a bar that runs from 0 to [longest] like
/// the axis of a graph: how much longer a transition takes, how long a photo
/// stands, which piece of a video plays. Only from [least] up to [limit] can be
/// reached: that part has the colour of the seconds that can be picked, the rest
/// of the axis is greyer. The picked seconds fill it in green up to a round end,
/// with the number under it. [marks] are where the axis is marked, every second
/// when not given. [onChange] hears every move, and [done] once the finger lets go.
web.HTMLElement secondsBar({
  required double value,
  required double limit,
  required String label,
  required void Function(double seconds, {required bool done}) onChange,
  double longest = longestExtra,
  double least = 0,
  List<double>? marks,
}) {
  String at(double seconds) => '${(seconds / longest * 100).toStringAsFixed(3)}%';
  var current = value.clamp(least, limit).toDouble();
  final step = longest > 15 ? 5 : 1;
  final ticks = {
    0.0,
    ...marks ?? [for (var second = 0; second <= longest; second += step) second.toDouble()],
    longest,
  };

  final fill = el('div', cls: 'secbar-fill');
  final knob = el('div', cls: 'secbar-knob');
  final shown = el('span', cls: 'secbar-value');
  final track = el('div', cls: 'secbar-track', children: [
    el('div', cls: 'secbar-axis', children: [
      for (final second in ticks)
        if (second <= longest)
          el('span', cls: 'secbar-tick', attrs: {'style': 'left:${at(second)}'}),
    ]),
    el('div', cls: 'secbar-open', attrs: {'style': 'width:${at(limit)}'}),
    fill,
    knob,
  ]);
  final bar = el('div', cls: 'secbar', attrs: {
    'role': 'slider',
    'tabindex': '0',
    'aria-label': label,
    'aria-valuemin': least.toStringAsFixed(2),
    'aria-valuemax': limit.toStringAsFixed(2),
  }, children: [
    el('div', cls: 'secbar-labels', children: [
      el('span', cls: 'secbar-start', text: _seconds(0)),
      if (limit < longest)
        el('span', cls: 'secbar-limit', text: _seconds(limit), attrs: {'style': 'left:${at(limit)}'}),
      el('span', cls: 'secbar-end', text: _seconds(longest)),
    ]),
    track,
    el('div', cls: 'secbar-under', children: [shown]),
  ]);

  void show() {
    fill.style.width = at(current);
    knob.style.left = at(current);
    shown
      ..textContent = _seconds(current)
      ..style.left = at(current);
    bar
      ..setAttribute('aria-valuenow', current.toStringAsFixed(2))
      ..setAttribute('aria-valuetext', _seconds(current));
  }

  // Where the finger took the knob, and what the bar said then: the knob moves
  // as far as the finger does, so taking it never makes it jump.
  var grabX = 0.0;
  var grabValue = 0.0;

  void moveTo(double x, {required bool done}) {
    final box = track.getBoundingClientRect();
    final seconds = grabValue + (x - grabX) / box.width * longest;
    current = ((seconds.clamp(least, limit)) * 100).round() / 100;
    show();
    onChange(current, done: done);
  }

  var dragging = false;
  track.addEventListener('pointerdown', ((web.PointerEvent event) {
    final x = _across(event);
    final box = track.getBoundingClientRect();
    // Only the knob moves the bar; a tap anywhere else changes nothing.
    if ((x - (box.left + current / longest * box.width)).abs() > 24) return;
    grabX = x;
    grabValue = current;
    dragging = true;
    try {
      // The finger keeps the bar even when it slides off it.
      track.setPointerCapture(event.pointerId);
    } on Object {
      // A pointer the browser no longer knows: the bar still follows it.
    }
  }).toJS);
  track.addEventListener('pointermove', ((web.PointerEvent event) {
    if (dragging) moveTo(_across(event), done: false);
  }).toJS);
  void letGo(web.PointerEvent event) {
    if (!dragging) return;
    dragging = false;
    moveTo(_across(event), done: true);
  }

  track.addEventListener('pointerup', letGo.toJS);
  track.addEventListener('pointercancel', ((web.PointerEvent event) {
    dragging = false;
    onChange(current, done: true);
  }).toJS);
  bar.addEventListener('keydown', ((web.KeyboardEvent event) {
    final step = switch (event.key) { 'ArrowRight' || 'ArrowUp' => .1, 'ArrowLeft' || 'ArrowDown' => -.1, _ => 0.0 };
    if (step == 0) return;
    event.preventDefault();
    current = (((current + step).clamp(least, limit)) * 100).round() / 100;
    show();
    onChange(current, done: true);
  }).toJS);
  show();
  return bar;
}
/// The piece of a video that plays, on a bar as long as the whole video: the
/// piece is the green part between two round ends. Its ends drag to make it
/// shorter or longer, up to [longest]; the piece itself drags to move it; a tap
/// elsewhere changes nothing. [onChange] hears every move with [at], the second
/// to show under the finger, and [done] once the finger lets go.
web.HTMLElement clipBar({
  required double length,
  required double from,
  required double clip,
  required double longest,
  required String label,
  required void Function(double from, double length, {required bool done, required double at}) onChange,
}) {
  String at(double seconds) => '${(seconds / length * 100).toStringAsFixed(3)}%';
  final least = min(1.0, length);
  var start = from;
  var size = clip.clamp(least, longest).toDouble();
  final step = length > 15 ? 5 : 1;

  final fill = el('div', cls: 'secbar-fill');
  final left = el('div', cls: 'secbar-knob');
  final right = el('div', cls: 'secbar-knob');
  final shown = el('span', cls: 'secbar-value');
  final track = el('div', cls: 'secbar-track', children: [
    el('div', cls: 'secbar-axis', children: [
      for (var second = 0; second <= length; second += step)
        el('span', cls: 'secbar-tick', attrs: {'style': 'left:${at(second.toDouble())}'}),
    ]),
    el('div', cls: 'secbar-open', attrs: {'style': 'width:100%;opacity:.35'}),
    fill,
    left,
    right,
  ]);
  final box = el('div', cls: 'secbar', attrs: {
    'role': 'slider',
    'tabindex': '0',
    'aria-label': label,
  }, children: [
    el('div', cls: 'secbar-labels', children: [
      el('span', cls: 'secbar-start', text: _seconds(0)),
      el('span', cls: 'secbar-end', text: _seconds(length)),
    ]),
    track,
    el('div', cls: 'secbar-under', children: [shown]),
  ]);

  void show() {
    fill.style
      ..left = at(start)
      ..width = at(size);
    left.style.left = at(start);
    right.style.left = at(start + size);
    shown
      ..textContent = '${_seconds(start)} – ${_seconds(start + size)}'
      ..style.left = at(start + size / 2);
    box
      ..setAttribute('aria-valuenow', start.toStringAsFixed(2))
      ..setAttribute('aria-valuetext', '${_seconds(start)} – ${_seconds(start + size)}');
  }

  double hundredths(double value) => (value * 100).round() / 100;

  // What the finger holds: an end, or the piece with how far into it.
  String? holding;
  var grip = 0.0;

  double secondAt(double x) {
    final rect = track.getBoundingClientRect();
    return ((x - rect.left) / rect.width * length).clamp(0, length).toDouble();
  }

  void moveTo(double x, {required bool done}) {
    final second = secondAt(x);
    double shownAt;
    switch (holding) {
      case 'start':
        final end = start + size;
        start = hundredths(second.clamp(max(0.0, end - longest), end - least).toDouble());
        size = hundredths(end - start);
        shownAt = start;
      case 'end':
        size = hundredths((second.clamp(start + least, min(length, start + longest)) - start).toDouble());
        shownAt = start + size;
      default:
        start = hundredths((second - grip).clamp(0, length - size).toDouble());
        shownAt = start;
    }
    show();
    onChange(start, size, done: done, at: shownAt);
  }

  var dragging = false;
  track.addEventListener('pointerdown', ((web.PointerEvent event) {
    final x = _across(event);
    final rect = track.getBoundingClientRect();
    final perSecond = rect.width / length;
    final startX = rect.left + start * perSecond;
    final endX = rect.left + (start + size) * perSecond;
    final second = secondAt(x);
    if ((x - endX).abs() <= 20 && (x - endX).abs() <= (x - startX).abs()) {
      holding = 'end';
    } else if ((x - startX).abs() <= 20) {
      holding = 'start';
    } else if (second >= start && second <= start + size) {
      holding = 'piece';
      grip = second - start;
    } else {
      return; // only the round ends and the piece itself move it
    }
    dragging = true;
    try {
      track.setPointerCapture(event.pointerId);
    } on Object {
      // A pointer the browser no longer knows: the bar still follows it.
    }
  }).toJS);
  track.addEventListener('pointermove', ((web.PointerEvent event) {
    if (dragging) moveTo(_across(event), done: false);
  }).toJS);
  track.addEventListener('pointerup', ((web.PointerEvent event) {
    if (!dragging) return;
    dragging = false;
    moveTo(_across(event), done: true);
  }).toJS);
  track.addEventListener('pointercancel', ((web.PointerEvent event) {
    dragging = false;
    onChange(start, size, done: true, at: start);
  }).toJS);
  box.addEventListener('keydown', ((web.KeyboardEvent event) {
    final step = switch (event.key) { 'ArrowRight' || 'ArrowUp' => .1, 'ArrowLeft' || 'ArrowDown' => -.1, _ => 0.0 };
    if (step == 0) return;
    event.preventDefault();
    start = hundredths((start + step).clamp(0, length - size).toDouble());
    show();
    onChange(start, size, done: true, at: start);
  }).toJS);
  show();
  return box;
}
