import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/show.dart';
import 'dom.dart';

/// Where the finger is across the screen. A phone gives it with decimals, which
/// the web package would wrongly take as a whole number.
double _across(web.PointerEvent event) =>
    (event as JSObject).getProperty<JSNumber>('clientX'.toJS).toDartDouble;

/// How much longer a transition takes, dragged with a finger along a bar that runs
/// from 0 to 12 s like the axis of a graph. Only up to [limit] can be reached: that
/// part has the colour of the seconds that can be picked, the rest of the axis is
/// greyer. The picked seconds fill it in green up to a round end, with the number
/// under it. [onChange] hears every move, and [done] once the finger lets go.
web.HTMLElement secondsBar({
  required double value,
  required double limit,
  required void Function(double seconds, {required bool done}) onChange,
}) {
  String at(double seconds) => '${(seconds / longestExtra * 100).toStringAsFixed(3)}%';
  var current = min(value, limit);

  final fill = el('div', cls: 'secbar-fill');
  final knob = el('div', cls: 'secbar-knob');
  final shown = el('span', cls: 'secbar-value');
  final track = el('div', cls: 'secbar-track', children: [
    el('div', cls: 'secbar-axis', children: [
      for (var second = 0; second <= longestExtra; second++)
        el('span', cls: 'secbar-tick', attrs: {'style': 'left:${at(second.toDouble())}'}),
    ]),
    el('div', cls: 'secbar-open', attrs: {'style': 'width:${at(limit)}'}),
    fill,
    knob,
  ]);
  final bar = el('div', cls: 'secbar', attrs: {
    'role': 'slider',
    'tabindex': '0',
    'aria-label': tr('Produljenje prijelaza'),
    'aria-valuemin': '0',
    'aria-valuemax': limit.toStringAsFixed(2),
  }, children: [
    el('div', cls: 'secbar-labels', children: [
      el('span', cls: 'secbar-start', text: '0 s'),
      if (limit < longestExtra)
        el('span', cls: 'secbar-limit', text: '${tenths(limit)} s', attrs: {'style': 'left:${at(limit)}'}),
      el('span', cls: 'secbar-end', text: '${longestExtra.round()} s'),
    ]),
    track,
    el('div', cls: 'secbar-under', children: [shown]),
  ]);

  void show() {
    fill.style.width = at(current);
    knob.style.left = at(current);
    shown
      ..textContent = '+${tenths(current)} s'
      ..style.left = at(current);
    bar
      ..setAttribute('aria-valuenow', current.toStringAsFixed(2))
      ..setAttribute('aria-valuetext', '${tenths(current)} s');
  }

  void moveTo(double x, {required bool done}) {
    final box = track.getBoundingClientRect();
    final seconds = (x - box.left) / box.width * longestExtra;
    current = ((seconds.clamp(0, limit)) * 100).round() / 100;
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
    current = (((current + step).clamp(0, limit)) * 100).round() / 100;
    show();
    onChange(current, done: true);
  }).toJS);
  show();
  return bar;
}
