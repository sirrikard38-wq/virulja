import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'anthem.dart';
import 'show_builder.dart';
import 'shop_screen.dart';
import 'show_player.dart';
import 'shows_section.dart';
import 'cloud.dart';
import 'currency_wheel.dart';
import 'context.dart';
import 'costs_screen.dart';
import 'dom.dart';
import 'food_screen.dart';
import 'group_screen.dart';
import 'home_screen.dart';
import 'icons.dart';
import 'install.dart';
import 'language_section.dart';
import 'memories_screen.dart';
import 'playlist_screen.dart';
import 'route_screen.dart';
import 'stay_screen.dart';
import 'store.dart';
import 'trip_form.dart';
import 'trip_screen.dart';
import 'widgets.dart';

/// Where the app is, read from the address (`#/p/<trip>/<section>/<photo>`), so
/// the phone's back button works like in any app.
class _Place {
  _Place(String hash) {
    final parts = hash.replaceFirst(RegExp(r'^#/?'), '').split('/');
    page = parts.first;
    if (page == 'p' && parts.length > 1) {
      tripId = parts[1];
      section = parts.length > 2 ? parts[2] : null;
      photoId = parts.length > 3 ? parts[3] : null;
    }
  }

  late final String page;
  String? tripId;
  String? section;
  String? photoId;
}

/// Mounts the app and redraws the current screen after every change.
class ViruljaApp {
  ViruljaApp(this._root, this._store, this._cloud) {
    _ui = Ui(
      store: _store,
      cloud: _cloud,
      anthem: _anthem,
      go: _go,
      swap: _swap,
      back: _back,
      openTrip: _openTrip,
      startAnthem: _startAnthem,
      rerender: render,
      toast: _showToast,
      offerUndo: _offerUndo,
    );
    _anthem.onProgress = _showProgress;
    _toast = el('div', cls: 'toast', attrs: {'role': 'status', 'aria-live': 'polite'});
    web.document.body!.appendChild(_toast);
    _undoBar = el('div', cls: 'undo-bar', attrs: {'role': 'status'});
    web.document.body!.appendChild(_undoBar);
    // An iPhone zooms with two fingers whatever the page says, unless told not to.
    web.document.addEventListener('gesturestart', ((web.Event event) => event.preventDefault()).toJS);
    final known = _stepOf();
    known == null ? _markStep() : _step = known;
    // Opened anew, Putovanja stands on a step of its own over the first one,
    // so that going back to it wipes the way forward as on any other screen.
    final state = web.window.history.state.dartify();
    _firstStep = state is Map && state['afterStart'] == true ? _step - 1 : _step;
    // Every change of screen comes through the address, as phones expect.
    web.window.addEventListener(
      'hashchange',
      ((web.Event event) {
        final hash = web.window.location.hash;
        final again = _rewinding;
        if (again != null) {
          // One step past the screen shown, out of sight: from here it is put
          // back as a fresh step, which wipes out the way forward.
          _rewinding = null;
          _returning = again;
          _step = (_stepOf() ?? _step) + 1;
          web.window.location.hash = again.isEmpty ? '#/' : again;
          return;
        }
        if (_returning != null) {
          // The screen shown, back as a fresh step: nothing changes on it.
          _returning = null;
          _markStep();
          return;
        }
        final step = _stepOf();
        final wentBack = step != null && step < _step;
        if (step == null) {
          _step++;
          _markStep();
        } else {
          _step = step;
        }
        if (wentBack) _settleAfterBack(hash);
        if (_trail.isNotEmpty && _trail.last == web.window.location.hash) {
          _trail.removeLast(); // the phone's back button
        }
        _arrive();
      }).toJS,
    );
    watchForInstall(render);
    _cloud?.onChange = _groupChanged;
    _cloud?.onNotice = _showToast;
    Timer.periodic(_redrawCheck, (_) {
      if (_redrawWaiting && !_busy) render();
    });
  }

  final web.Element _root;
  final AppStore _store;
  final CloudSync? _cloud;
  final AnthemPlayer _anthem = AnthemPlayer();
  late final Ui _ui;
  late final web.HTMLElement _toast;
  late final web.HTMLElement _undoBar;
  final List<String> _trail = [];
  web.Element? _ring;
  Timer? _toastTimer;
  Timer? _undoTimer;
  bool _redrawWaiting = false;
  bool _languageOpen = false;

  /// Ring length of the speaker: the circumference of its circle.
  static const double _ringLength = 125.7;
  static const Duration _undoTime = Duration(seconds: 5);

  /// Sections that are a trip's main screen rather than a category.
  static const Set<String?> _mainTabs = {
    null,
    'plan',
    'naputu',
    'slike',
    'ankete',
    'napad',
  };
  static const Duration _redrawCheck = Duration(seconds: 2);

  /// True while a redraw would get in the way: someone is typing, a form is
  /// open, or a song or video is playing in its player.
  bool get _busy {
    final active = web.document.activeElement?.tagName;
    final video = web.document.querySelector('video:not(.show-video)') as web.HTMLVideoElement?;
    return active == 'INPUT' ||
        (video != null && !video.paused) ||
        active == 'TEXTAREA' ||
        active == 'SELECT' ||
        web.document.querySelector('details[open]') != null ||
        web.document.querySelector('.drag-ghost') != null ||
        _ui.playingSongId != null;
  }

  /// News from the group: shown at once, or as soon as it disturbs nobody.
  void _groupChanged() {
    if (_busy) {
      _redrawWaiting = true;
    } else {
      render();
    }
  }

  AppData get _data => _store.data;

  /// A good moment to show a new version of the app: nothing is being typed,
  /// no form or box is open and nothing plays. The address keeps the screen,
  /// so the new version opens where this one was.
  bool get isIdle {
    final place = _Place(web.window.location.hash);
    final form = place.page == 'novo' || place.section == 'uredi' || place.section == 'foto';
    return !form && !_busy && !_settling && web.document.querySelector('.sheet') == null;
  }

  void _go(String route) {
    if (web.window.location.hash == route) {
      render();
      return;
    }
    _trail.add(web.window.location.hash);
    _step++;
    web.window.location.hash = route;
    _markStep();
  }

  /// A new screen: the list of people folds, the page starts at the top, and
  /// the language menu closes.
  void _arrive() {
    _languageOpen = false;
    final place = _Place(web.window.location.hash);
    if (place.tripId != null && _mainTabs.contains(place.section)) {
      if (_ui.showPeople) _ui.peopleFold = PeopleFold.closing;
    } else {
      _ui.showPeople = false;
    }
    web.window.scrollTo(0.toJS, 0);
    render();
  }


  /// Where the phone was last found, for the walk to the stay to start there.
  ({double latitude, double longitude})? _here;

  /// The pin under the speaker: Google Maps on foot from here to the reserved
  /// stay. A plain link, as opening a window from code left an iPhone's home
  /// screen app white when it came back. Where the phone is, once it allows
  /// that, goes into the link as its start.
  web.HTMLElement _walkLink(Trip trip, Offer stay) {
    final link = el('a', cls: trip.anthemClipId != null ? 'round right third' : 'round right second', attrs: {
      'href': '${walkTo(stay, trip, from: _here)}',
      'target': '_blank',
      'rel': 'noopener',
      'aria-label': tr('Pješice do smještaja'),
    }, children: [icon('pin', size: 22)]);
    void find() {
      try {
        web.window.navigator.geolocation.getCurrentPosition(
          ((web.GeolocationPosition position) {
            _here = (latitude: position.coords.latitude.toDouble(), longitude: position.coords.longitude.toDouble());
            link.setAttribute('href', '${walkTo(stay, trip, from: _here)}');
          }).toJS,
          ((web.GeolocationPositionError _) {}).toJS,
          web.PositionOptions(maximumAge: 300000, timeout: 8000),
        );
      } on Object {
        // No location here: Google Maps starts from "My Location".
      }
    }

    // Asks only where the phone already allows it; a tap asks for next time.
    try {
      web.window.navigator.permissions
          .query({'name': 'geolocation'}.jsify()! as JSObject)
          .toDart
          .then((status) {
        if (status.state == 'granted') find();
      }, onError: (Object _) {});
    } on Object {
      // A phone without the question: the tap asks.
    }
    link.onClick.listen((_) {
      if (_here == null) find();
    });
    return link;
  }

  /// The step the app started on: there is nothing of it before that.
  int _firstStep = 0;

  /// The screen being put back as a fresh step, while the step before it passes
  /// out of sight; then the moment it comes back.
  String? _rewinding;
  String? _returning;

  /// When the last step back began to settle: a newer version waits until it
  /// is done, or the way forward would stay.
  DateTime _settlingSince = DateTime(2000);

  bool get _settling =>
      _rewinding != null ||
      _returning != null ||
      DateTime.now().difference(_settlingSince) < const Duration(milliseconds: 1200);

  /// After a step back (the arrow, the phone's back button, a swipe from the
  /// left edge), the screen left behind stays as a step forward, which an
  /// iPhone reaches with a swipe from the right edge. A moment later, once the
  /// phone is done, the app goes one more step back out of sight and puts the
  /// screen shown back as a fresh step, through the address. That wipes the way
  /// forward out and leaves no copy of a screen to swipe back to. On the first
  /// step of all there is nothing before, so the way forward stays.
  void _settleAfterBack(String landed) {
    final step = _stepOf();
    if (step == null || step <= _firstStep) return;
    _settlingSince = DateTime.now();
    Timer(const Duration(milliseconds: 400), () {
      if (web.window.location.hash != landed || _rewinding != null) return;
      _rewinding = landed;
      web.window.history.back();
    });
  }

  /// Whether Plan napada was the screen last drawn, and when it was left: back
  /// within [_attackMemory] it keeps its day.
  bool _onAttack = false;

  /// The address last drawn: a redraw of the same screen keeps what is above.
  String? _drawnHash;
  DateTime? _leftAttack;
  static const Duration _attackMemory = Duration(seconds: 20);

  /// Which step of the phone's history the app is on, counted from its start.
  int _step = 0;

  int? _stepOf() {
    final state = web.window.history.state.dartify();
    return state is Map && state['step'] is num ? (state['step'] as num).toInt() : null;
  }

  void _markStep() => web.window.history.replaceState({'step': _step}.jsify(), '');

  /// Back to the screen before, a real step back; the way forward it leaves
  /// is wiped out a moment later (`_settleAfterBack`).
  void _back() {
    if (_trail.isNotEmpty) {
      web.window.history.back();
      return;
    }
    final place = _Place(web.window.location.hash);
    _go(place.tripId == null || place.section == null
        ? '#/'
        : '#/p/${place.tripId}');
  }

  /// The on-screen arrow: from a trip's main screen it always leaves the trip,
  /// wherever the person came from.
  void _arrow() {
    final place = _Place(web.window.location.hash);
    if (place.tripId != null &&
        _mainTabs.contains(place.section) &&
        _trail.isEmpty) {
      _go('#/');
    } else {
      _back();
    }
  }

  /// Changes the address without a new history step, so the iPhone's back
  /// swipe skips this screen: tabs of a trip count as one place.
  void _swap(String route) {
    web.window.location.replace(route);
    _markStep();
  }

  /// A tap on a trip in a list. The tap is what lets the phone play sound, so
  /// the anthem starts here, not when the screen changes; moving around inside
  /// the trip later never restarts it.
  void _openTrip(Trip trip) {
    _anthem.wake();
    if (!_data.anthemMuted) _playAnthem(trip);
    final fromForm = _Place(web.window.location.hash).page == 'novo';
    (fromForm ? _swap : _go)('#/p/${trip.id}');
  }

  /// Plays the trip's anthem. When it cannot, and [say] is set (a tap meant to
  /// hear it), a message says why: the file has not reached this phone, or the
  /// phone cannot play it.
  Future<void> _playAnthem(Trip trip, {bool say = false}) async {
    final clip = trip.anthemClipId;
    if (clip == null) return;
    final wav = await _store.getBlob(clip) ?? await _cloud?.fetchBlob(trip, clip);
    if (wav == null) {
      if (say) _showToast(tr('Himna još nije stigla na ovaj mobitel. Neka je pošalje mobitel koji ju je dodao: dovoljno je da na njemu otvoriš putovanje.'), long: true);
      return;
    }
    if (!await _anthem.play(wav) && say) {
      _showToast(tr('Ovaj mobitel ne može pustiti himnu. Probaj je dodati ponovo.'), long: true);
    }
  }

  /// How far the anthem is, kept so that a new screen's ring starts there.
  double _progress = 0;

  String _dashes(double progress) => '${(progress * _ringLength).toStringAsFixed(1)} $_ringLength';

  void _showProgress(double progress) {
    _progress = progress;
    _ring?.setAttribute('stroke-dasharray', _dashes(progress));
  }

  void _startAnthem(Trip trip) {
    _anthem.wake(evenOnSilent: true);
    if (!_anthem.isPlaying) _playAnthem(trip, say: true);
    if (_data.anthemMuted) {
      _data.anthemMuted = false;
      _ui.changed();
    }
  }

  void _tapSpeaker(Trip trip) {
    _anthem.wake(evenOnSilent: true);
    if (_data.anthemMuted) {
      _data.anthemMuted = false;
      _playAnthem(trip, say: true);
    } else if (_anthem.isPlaying) {
      _anthem.stop();
      _data.anthemMuted = true;
    } else {
      _playAnthem(trip, say: true);
    }
    _ui.changed();
  }

  /// The speaker of the anthem: in the corner, or under the settings when
  /// [below].
  web.HTMLElement _speaker(Trip trip, {bool below = false}) {
    final ring = svg('circle', attrs: {
      'cx': '22',
      'cy': '22',
      'r': '20',
      // Where the anthem already is: a ring from nothing at each screen would jump.
      'stroke-dasharray': _dashes(_progress),
    });
    _ring = ring;
    return button(
      cls: below ? 'round right second' : 'round right',
      ariaLabel: _data.anthemMuted ? tr('Uključi himnu') : tr('Utišaj himnu'),
      onTap: () => _tapSpeaker(trip),
      children: [
        svg('svg', cls: 'ring', attrs: {
          'viewBox': '0 0 44 44',
          'width': '44',
          'height': '44',
          'aria-hidden': 'true',
        }, children: [ring]),
        icon(_data.anthemMuted ? 'muted' : 'sound', size: 22),
      ],
    );
  }

  /// At the top of the screens that are not about one trip or its memories.
  List<web.HTMLElement> _languageCorner() => [
        button(
          cls: 'round right lang-button',
          ariaLabel: tr('Jezik'),
          text: language.name.toUpperCase(),
          onTap: () {
            _languageOpen = !_languageOpen;
            render();
          },
        ),
        if (_languageOpen)
          el('div', cls: 'lang-menu card', children: [
            for (final choice in Language.values)
              button(
                text: choice.label,
                cls: choice == language ? 'on' : null,
                onTap: () {
                  _languageOpen = false;
                  chooseLanguage(_ui, choice);
                },
              ),
          ]),
      ];

  web.HTMLElement _backButton() => button(
        cls: 'round left',
        ariaLabel: tr('Natrag'),
        onTap: _arrow,
        children: [icon('back')],
      );

  web.HTMLElement _menu(String page) {
    web.HTMLElement item(String route, String name, String label, bool on) => button(
          cls: on ? 'nav-item on' : 'nav-item',
          onTap: () {
            _anthem.stop();
            _go(route);
          },
          children: [icon(name), web.document.createTextNode(label)],
        );
    return el('nav', cls: 'nav', children: [
      item('#/', 'compass', tr('Putovanja'), page != 'grupa'),
      item('#/grupa', 'tool', tr('Postavke'), page == 'grupa'),
    ]);
  }

  web.HTMLElement _tripPage(Trip trip, _Place place) {
    final section = place.section ?? defaultTab(trip);
    switch (section) {
      case 'smjestaj':
        return stayScreen(_ui, trip);
      case 'hrana':
        return foodScreen(_ui, trip);
      case 'put':
        return routeScreen(_ui, trip);
      case 'troskovi':
        return costsScreen(_ui, trip);
      case 'ducan':
        return shopScreen(_ui, trip);
      case 'playlista':
        return playlistScreen(_ui, trip, _playAnthem);
      case 'uredi':
        return tripForm(_ui, trip: trip);
      case 'prezentacija':
        return showBuilder(_ui, trip, place.photoId);
      case 'gledaj':
        return watchScreen(_ui, trip, place.photoId);
      case 'foto':
        for (final photo in trip.photos) {
          if (photo.id == place.photoId) return photoScreen(_ui, trip, photo);
        }
        return tripScreen(_ui, trip, 'slike');
      default:
        return tripScreen(_ui, trip, section);
    }
  }

  void _applyTheme() {
    final root = web.document.documentElement!;
    switch (_data.theme) {
      case ThemeChoice.system:
        root.removeAttribute('data-theme');
      case ThemeChoice.light:
        root.setAttribute('data-theme', 'light');
      case ThemeChoice.dark:
        root.setAttribute('data-theme', 'dark');
    }
  }

  void render() {
    // Leaving a screen that keeps something then, such as a trip's settings.
    if (web.window.location.hash != _drawnHash) {
      final leave = _ui.onLeave;
      _ui.onLeave = null;
      leave?.call();
      _ui.openFolds.clear();
      _ui.noticesOpen = false;
      _ui.hiddenCodesOpen = false;
      final arriving = _Place(web.window.location.hash);
      final going = arriving.tripId == null ? null : _data.tripById(arriving.tripId!);
      if (going != null && arriving.section == 'put' && _Place(_drawnHash ?? '').section != 'put') {
        final day = today().difference(going.start).inDays;
        _ui.routeDay = day >= 0 && day < going.dayCount ? day : 0;
      }
    }
    language = _data.chosenLanguage;
    web.document.documentElement?.setAttribute('lang', language.name);
    _redrawWaiting = false;
    _applyTheme();
    final place = _Place(web.window.location.hash);
    final tripId = place.tripId;
    final trip = tripId == null ? null : _data.tripById(tripId);
    if (trip == null && _anthem.isPlaying) _anthem.stop();
    // Leaving Plan napada lets what was voted elsewhere move to its day. Back
    // within 20 s it opens on the same day; later, on Sve.
    if (place.section != 'ankete') {
      _ui.pollsKept = null;
      _ui.editingPoll = null;
    }
    if (place.section != 'napad') {
      _ui.attackKept = null;
      _ui.attackOrder = null;
      if (_onAttack) _leftAttack = DateTime.now();
      _onAttack = false;
    } else {
      final left = _leftAttack;
      if (!_onAttack && left != null && DateTime.now().difference(left) > _attackMemory) {
        _ui.attackDays.clear();
        _ui.attackWeeks.clear();
      }
      _onAttack = true;
    }
    _cloud?.watch(trip?.id);
    _ring = null;
    // Amounts in the trip's currency, and the one beside them converted.
    final money = trip?.currencies ?? _data.currencies;
    moneyCode = money.first;
    alsoCode = null; // a second currency beside, for later
    ratesPerEuro = _data.rates;
    if (alsoCode != null) loadRates(_ui, done: _groupChanged);

    final web.HTMLElement page;
    if (trip != null) {
      page = _tripPage(trip, place);
    } else if (place.page == 'novo' && _data.meId != null) {
      page = tripForm(_ui);
    } else if (place.page == 'grupa' && _data.meId != null) {
      page = groupScreen(_ui);
    } else {
      page = homeScreen(_ui);
    }

    final isPhoto = place.section == 'foto';
    final isForm = place.page == 'novo' || place.section == 'uredi';
    final isWatch = place.section == 'gledaj';
    if (!isWatch) leaveWholeScreen();
    final hasMenu = !isPhoto && !isForm && !isWatch && _data.meId != null;
    final hasBack = trip != null || place.page == 'novo';
    final frameClass = isPhoto
        ? 'frame with-composer'
        : hasMenu
            ? 'frame'
            : 'frame no-nav';
    // Something taken out of a list on the same screen: the page keeps enough
    // height to stay where it was scrolled, so what is above stands still and
    // what is below moves up. A new screen starts with no such height.
    final hash = web.window.location.hash;
    final sameScreen = hash == _drawnHash;
    final scrolled = web.window.scrollY;
    final keep = sameScreen ? scrolled + web.window.innerHeight : 0;
    _drawnHash = hash;
    final frame = el('div', cls: frameClass, children: [
        page,
        if (hasBack) _backButton(),
        if (trip == null && place.page != 'uspomene' && place.page != 'novo')
          ..._languageCorner(),
        // The settings stand above the speaker.
        if (trip != null && trip.anthemClipId != null)
          _speaker(trip, below: _mainTabs.contains(place.section)),
        if (trip != null && _mainTabs.contains(place.section))
          button(
            cls: 'round right',
            ariaLabel: tr('Postavke'),
            onTap: () => _go('#/p/${trip.id}/uredi'),
            children: [icon('tool', size: 22)],
          ),
        // Under the speaker: the way to the reserved stay, on foot.
        if (trip != null && _mainTabs.contains(place.section))
          if (trip.reservedOffer case final stay?)
            // A plain link: opening a window from code leaves an iPhone's home
            // screen app white when it comes back from Google Maps.
            _walkLink(trip, stay),
        if (hasMenu) _menu(place.page),
      ]);
    if (keep > 0) frame.style.minHeight = '${keep.round()}px';
    show(_root, frame);
    // A redraw of the same screen leaves the page exactly where it was: an
    // iPhone may move it while the old screen is swapped for the new one,
    // which looked like a jump to the top.
    if (sameScreen) _stayAt(scrolled);
    scheduleMicrotask(markEdges);
  }

  void _stayAt(double y) {
    web.document.documentElement?.scrollHeight; // lays the new screen out first
    if ((web.window.scrollY - y).abs() > 1) web.window.scrollTo(0.toJS, y);
    web.window.requestAnimationFrame(((double _) {
      if ((web.window.scrollY - y).abs() > 1) web.window.scrollTo(0.toJS, y);
    }).toJS);
  }

  void _offerUndo(String message, void Function() undo) {
    _undoTimer?.cancel();
    _undoBar
      ..textContent = ''
      ..append(el('span', text: message))
      ..append(button(
        text: tr('Poništi'),
        onTap: () {
          _undoTimer?.cancel();
          _undoBar.classList.remove('show');
          undo();
        },
      ))
      ..classList.add('show');
    _undoTimer = Timer(_undoTime, () => _undoBar.classList.remove('show'));
  }

  void _showToast(String message, {bool short = false, bool long = false}) {
    _toast.textContent = message;
    _toast.classList.add('show');
    _toastTimer?.cancel();
    _toastTimer = Timer(
      Duration(milliseconds: short ? 1300 : long ? 4000 : 2600),
      () => _toast.classList.remove('show'),
    );
  }
}
