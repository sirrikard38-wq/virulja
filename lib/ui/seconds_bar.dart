import 'dart:js_interop';
import 'dart:js_interop_unsafe';

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

  void moveTo(double x, {required bool done}) {
    final box = track.getBoundingClientRect();
    final seconds = (x - box.left) / box.width * longest;
    current = ((seconds.clamp(least, limit)) * 100).round() / 100;
    show();
    onChange(current, done: done);
  }

  var dragging = false;
  track.addEventListener('pointerdown', ((web.PointerEvent event) {
    dragging = true;
    moveTo(_across(event), done: false);
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
