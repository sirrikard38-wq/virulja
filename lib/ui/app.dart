import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/links.dart';
import '../src/domain/models.dart';
import 'anthem.dart';
import 'show_builder.dart';
import 'show_player.dart';
import 'shows_section.dart';
import 'cloud.dart';
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
    // Every change of screen comes through the address, as phones expect.
    web.window.addEventListener(
      'hashchange',
      ((web.Event event) {
        if (_skipping) {
          _skipping = false; // a step passed through on the way back
          return;
        }
        final hash = web.window.location.hash;
        if (_settling == hash) {
          // The step that wipes out the way forward: the screen stays as it is.
          _settling = null;
          _markStep();
          _shown = hash;
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
    // The on-screen arrow leaves the screen in place of a step back, so it
    // leaves behind a step of the same screen as the one before. The phone's
    // back button skips that step, as it shows nothing new.
    web.window.addEventListener(
      'popstate',
      ((web.Event event) {
        final step = _stepOf();
        final hash = web.window.location.hash;
        if (_placeOf(hash) == _placeOf(_shown ?? '') && step != null && step < _step) {
          _step = step;
          _skipping = hash != _shown; // its address change is still to come
          web.window.history.back();
        }
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

  /// True on the home screen, a good moment to show a new version of the app.
  bool get isIdle => _Place(web.window.location.hash).page.isEmpty;

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

  /// The address last drawn.
  String? _shown;

  /// The list of trips, Uspomene and Postavke: the screens the menu leads to.
  bool _isFirstScreen(String hash) => _Place(hash).tripId == null &&
      const {'', '~', 'uspomene', 'grupa'}.contains(_Place(hash).page);

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

  /// Set while the phone's back button passes a step that shows nothing new.
  bool _skipping = false;

  /// The address of the step being added after a step back.
  String? _settling;

  /// After the phone's own step back (its back button, or a swipe from the left
  /// edge), the screen it left stays as a step forward, which an iPhone reaches
  /// with a swipe from the right edge. A moment later, once the phone is done,
  /// one more step of the same screen is added through the address, which wipes
  /// that step forward out. The phone's back button then skips it.
  void _settleAfterBack(String landed) {
    // A first screen gets no copy: a swipe back there would show it again.
    if (_isFirstScreen(landed)) return;
    Timer(const Duration(milliseconds: 400), () {
      if (web.window.location.hash != landed) return;
      final place = _Place(landed);
      final trip = place.tripId == null ? null : _data.tripById(place.tripId!);
      final String again;
      if (landed == '#/~') {
        again = '#/';
      } else if (landed.endsWith('/~')) {
        again = landed.substring(0, landed.length - 2);
      } else if (trip != null && place.section == null) {
        again = '#/p/${trip.id}/${defaultTab(trip)}/~';
      } else if (landed.isEmpty || landed == '#' || landed == '#/') {
        again = '#/~';
      } else {
        again = '$landed/~';
      }
      _settling = again;
      _step++;
      web.window.location.hash = again;
    });
  }

  /// Where an address is: the tabs of a trip are one place.
  String _placeOf(String hash) {
    final place = _Place(hash);
    if (place.tripId != null && (place.section == null || _mainTabs.contains(place.section))) {
      return '#/p/${place.tripId}';
    }
    final plain = hash.endsWith('/~') ? hash.substring(0, hash.length - 2) : hash;
    return plain.isEmpty || plain == '#' ? '#/' : plain;
  }

  /// Which step of the phone's history the app is on, counted from its start.
  int _step = 0;

  int? _stepOf() {
    final state = web.window.history.state.dartify();
    return state is Map && state['step'] is num ? (state['step'] as num).toInt() : null;
  }

  void _markStep() => web.window.history.replaceState({'step': _step}.jsify(), '');

  /// Back to the screen before: in its place, not a step back in the phone's
  /// history, so no step forward is left that a swipe from the right edge of
  /// an iPhone would go to.
  void _back() {
    if (_trail.isNotEmpty) {
      final before = _trail.last;
      // To a first screen the arrow steps back for real: nothing is left behind
      // it, so a swipe back there has nowhere to go.
      if (_isFirstScreen(before)) {
        web.window.history.back();
        return;
      }
      _trail.removeLast();
      web.window.location.replace(before.isEmpty ? '#/' : before);
      _markStep();
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

  Future<void> _playAnthem(Trip trip) async {
    final clip = trip.anthemClipId;
    if (clip == null) return;
    final wav = await _store.getBlob(clip) ?? await _cloud?.fetchBlob(trip, clip);
    if (wav != null) await _anthem.play(wav);
  }

  void _showProgress(double progress) {
    _ring?.setAttribute(
      'stroke-dasharray',
      '${(progress * _ringLength).toStringAsFixed(1)} $_ringLength',
    );
  }

  void _startAnthem(Trip trip) {
    _anthem.wake(evenOnSilent: true);
    if (!_anthem.isPlaying) _playAnthem(trip);
    if (_data.anthemMuted) {
      _data.anthemMuted = false;
      _ui.changed();
    }
  }

  void _tapSpeaker(Trip trip) {
    _anthem.wake(evenOnSilent: true);
    if (_data.anthemMuted) {
      _data.anthemMuted = false;
      _playAnthem(trip);
    } else if (_anthem.isPlaying) {
      _anthem.stop();
      _data.anthemMuted = true;
    } else {
      _playAnthem(trip);
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
      'stroke-dasharray': '0 $_ringLength',
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
      item('#/', 'compass', tr('Putovanja'), page != 'uspomene' && page != 'grupa'),
      item('#/uspomene', 'photo', tr('Uspomene'), page == 'uspomene'),
      item('#/grupa', 'group', tr('Postavke'), page == 'grupa'),
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
    language = _data.chosenLanguage;
    web.document.documentElement?.setAttribute('lang', language.name);
    _redrawWaiting = false;
    _applyTheme();
    final place = _Place(web.window.location.hash);
    _shown = web.window.location.hash;
    final tripId = place.tripId;
    final trip = tripId == null ? null : _data.tripById(tripId);
    if (trip == null && _anthem.isPlaying) _anthem.stop();
    // Leaving Plan napada lets what was voted elsewhere move to its day.
    if (place.section != 'napad') _ui.attackKept = null;
    _cloud?.watch(trip?.id);
    _ring = null;

    final web.HTMLElement page;
    if (trip != null) {
      page = _tripPage(trip, place);
    } else if (place.page == 'novo' && _data.meId != null) {
      page = tripForm(_ui);
    } else if (place.page == 'grupa' && _data.meId != null) {
      page = groupScreen(_ui);
    } else if (place.page == 'uspomene' && _data.meId != null) {
      page = memoriesListScreen(_ui);
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
    show(
      _root,
      el('div', cls: frameClass, children: [
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
      ]),
    );
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

  void _showToast(String message, {bool short = false}) {
    _toast.textContent = message;
    _toast.classList.add('show');
    _toastTimer?.cancel();
    _toastTimer = Timer(
      Duration(milliseconds: short ? 1300 : 2600),
      () => _toast.classList.remove('show'),
    );
  }
}
