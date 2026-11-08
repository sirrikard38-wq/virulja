import 'dart:async';

import 'package:web/web.dart' as web;

import 'dom.dart';
import 'swipes.dart';

/// When the app opens: the letters of VIRULJA come up one after another in the
/// middle of the screen, over about three seconds, then the whole
/// fades away to the trips underneath.
void showSplash() {
  const word = 'VIRULJA';
  final quick = wantsLessMotion;
  final splash = el('div', cls: 'splash', attrs: {'aria-hidden': 'true'}, children: [
    el('div', cls: 'splash-word', children: [
      for (var i = 0; i < word.length; i++)
        el('span', text: word[i], attrs: {'style': 'animation-delay:${quick ? 0 : i * 256}ms'}),
    ]),
  ]);
  web.document.body!.append(splash);
  Timer(Duration(milliseconds: quick ? 700 : 2640), () {
    splash.classList.add('leaving');
    Timer(const Duration(milliseconds: 650), () => splash.remove());
  });
}
