import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'anthem.dart';
import 'cloud.dart';
import 'context.dart';
import 'costs_screen.dart';
import 'dom.dart';
import 'food_screen.dart';
import 'group_screen.dart';
import 'home_screen.dart';
import 'icons.dart';
import 'install.dart';
import 'memories_screen.dart';
import 'playlist_screen.dart';
import 'polls_section.dart';
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
      rerender: render,
      toast: _showToast,
    );
    _anthem.onProgress = _showProgress;
    _toast = el('div', cls: 'toast', attrs: {'role': 'status', 'aria-live': 'polite'});
    web.document.body!.appendChild(_toast);
    web.window.addEventListener(
      'hashchange',
      ((web.Event event) {
        if (_trail.isNotEmpty && _trail.last == web.window.location.hash) {
          _trail.removeLast(); // the phone's back button
        }
        web.window.scrollTo(0.toJS, 0);
        render();
      }).toJS,
    );
    watchForInstall(render);
    _cloud?.onChange = _groupChanged;
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
  final List<String> _trail = [];
  web.Element? _ring;
  Timer? _toastTimer;
  bool _redrawWaiting = false;

  /// Ring length of the speaker: the circumference of its circle.
  static const double _ringLength = 125.7;
  static const Duration _redrawCheck = Duration(seconds: 2);

  /// True while a redraw would get in the way: someone is typing, a form is
  /// open, or a song is playing in its player.
  bool get _busy {
    final active = web.document.activeElement?.tagName;
    return active == 'INPUT' ||
        active == 'TEXTAREA' ||
        active == 'SELECT' ||
        web.document.querySelector('details[open]') != null ||
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
    web.window.location.hash = route;
  }

  void _back() {
    if (_trail.isNotEmpty) {
      _trail.removeLast();
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
    const mainTabs = {null, 'plan', 'naputu', 'slike'};
    if (place.tripId != null &&
        mainTabs.contains(place.section) &&
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

  void _tapSpeaker(Trip trip) {
    _anthem.wake();
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

  web.HTMLElement _speaker(Trip trip) {
    final ring = svg('circle', attrs: {
      'cx': '22',
      'cy': '22',
      'r': '20',
      'stroke-dasharray': '0 $_ringLength',
    });
    _ring = ring;
    return button(
      cls: 'round right',
      ariaLabel: _data.anthemMuted ? 'Uključi himnu' : 'Utišaj himnu',
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

  web.HTMLElement _backButton() => button(
        cls: 'round left',
        ariaLabel: 'Natrag',
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
      item('#/', 'compass', 'Putovanja', page != 'uspomene' && page != 'grupa'),
      item('#/uspomene', 'photo', 'Uspomene', page == 'uspomene'),
      item('#/grupa', 'group', 'Postavke', page == 'grupa'),
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
      case 'anketa':
        return newPollScreen(_ui, trip);
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
    _redrawWaiting = false;
    _applyTheme();
    final place = _Place(web.window.location.hash);
    final tripId = place.tripId;
    final trip = tripId == null ? null : _data.tripById(tripId);
    if (trip == null && _anthem.isPlaying) _anthem.stop();
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
    final isForm = place.page == 'novo' ||
        place.section == 'uredi' ||
        place.section == 'anketa';
    final hasMenu = !isPhoto && !isForm && _data.meId != null;
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
        if (trip != null && trip.anthemClipId != null) _speaker(trip),
        if (hasMenu) _menu(place.page),
      ]),
    );
  }

  void _showToast(String message) {
    _toast.textContent = message;
    _toast.classList.add('show');
    _toastTimer?.cancel();
    _toastTimer = Timer(
      const Duration(milliseconds: 2600),
      () => _toast.classList.remove('show'),
    );
  }
}
