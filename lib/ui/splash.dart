import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'dom.dart';
import 'swipes.dart';

/// When the app opens: the letters of VIRULJA come up one after another in the
/// middle of the screen, over about three seconds, then the whole
/// fades away to the trips underneath. The page itself has it from its first
/// picture (`#splash` in index.html); this makes one only when it is missing.
void showSplash() {
  const word = 'VIRULJA';
  final quick = wantsLessMotion;
  var splash = web.document.querySelector('#splash');
  if (splash == null) {
    final made = el('div', cls: 'splash', attrs: {'aria-hidden': 'true'}, children: [
      el('div', cls: 'splash-word', children: [
        for (var i = 0; i < word.length; i++)
          el('span', text: word[i], attrs: {'style': 'animation-delay:${quick ? 0 : i * 256}ms'}),
      ]),
    ]);
    web.document.body!.append(made);
    splash = made;
  }
  final shown = splash;
  var gone = false;
  void leave() {
    if (gone) return;
    gone = true;
    shown.classList.add('leaving');
    Timer(const Duration(milliseconds: 650), () => shown.remove());
  }

  // The letters have been rising since the page was first drawn, while the
  // app loaded: the whole stays a moment after the last one has risen.
  final hold = Duration(milliseconds: quick ? 400 : 384);
  final last = shown.querySelector('.splash-word span:last-child');
  final rising = last?.getAnimations().toDart ?? const <web.Animation>[];
  // Never longer than before: a browser that draws nothing (a page out of
  // sight) leaves its animations waiting.
  Timer(Duration(milliseconds: quick ? 1100 : 3000), leave);
  if (rising.isEmpty) {
    Timer(hold, leave);
  } else {
    rising.first.finished.toDart.then((_) => Timer(hold, leave), onError: (_) => Timer(hold, leave));
  }
}
