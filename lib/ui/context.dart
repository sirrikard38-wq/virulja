import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/offers.dart';
import 'anthem.dart';
import 'cloud.dart';
import 'store.dart';

/// The list of people folding open or shut.
enum PeopleFold { opening, closing }

/// What every screen needs from the app.
class Ui {
  Ui({
    required this.store,
    required this.cloud,
    required this.anthem,
    required this.go,
    required this.swap,
    required this.back,
    required this.openTrip,
    required this.startAnthem,
    required this.rerender,
    required this.toast,
    required this.offerUndo,
  });

  final AppStore store;

  /// Null when the app runs without the cloud.
  final CloudSync? cloud;
  final AnthemPlayer anthem;

  /// Moves to a route such as `#/p/<trip>/smjestaj`.
  final void Function(String route) go;

  /// Moves to a route without adding a step to the phone's back history.
  final void Function(String route) swap;

  /// One screen back, like the phone's back button.
  final void Function() back;

  /// Opens a trip from a list; this is what starts its anthem.
  final void Function(Trip trip) openTrip;

  /// Plays the anthem unless it is already playing; called inside a tap.
  final void Function(Trip trip) startAnthem;

  final void Function() rerender;

  /// A short message that disappears by itself.
  /// Shows [message] for a moment; [short] for half as long.
  final void Function(String message, {bool short}) toast;

  /// A short message with a way to take back what was just done.
  final void Function(String message, void Function() undo) offerUndo;

  // What the screens remember while the app is open.
  /// What the stays are sorted by, first to last; none keeps them as added.
  List<OfferSort> offerSorts = [];

  /// Whether the choices of Sortiraj are showing.
  bool sortOpen = false;
  PlaceKind placeKind = PlaceKind.restaurant;

  /// The category that is open instead of [placeKind]: the group's own one, or
  /// the dishes.
  String? customKindId;
  bool addingKind = false;
  int routeDay = 0;

  /// Trip id -> the day its Plan napada shows; without one, all of them.
  final Map<String, int> attackDays = {};

  /// What the open day of Plan napada showed, which stays until the day is left.
  ({String trip, int day, Set<String> ids})? attackKept;

  /// Whether the list of kinds of notification is open.
  bool noticesOpen = false;

  /// Whether the list of presentations in Uspomene is open.
  bool showsOpen = false;

  /// The poll whose answers are being changed: each has an x, and a new one
  /// can be typed.
  String? editingPoll;

  /// The stay whose details are being changed.
  String? editingOffer;
  String? playingSongId;
  String? queueAddress;
  String? replyingTo;
  bool showPeople = false;
  PeopleFold? peopleFold;

  AppData get data => store.data;

  String get meId => data.meId!;

  /// Whether this person may open every transition at once: a choice in Postavke
  /// shown only to someone whose first name is Riko. Anyone could take that
  /// name, so it is a convenience, not a lock.
  bool get mayOpenAll {
    final me = data.meId == null ? null : data.personById(data.meId!);
    return me != null && me.name.trim().split(RegExp(r'\s+')).first.toLowerCase() == 'riko';
  }

  /// Every transition open on this phone, whatever the day.
  bool get allTransitions => mayOpenAll && data.allTransitions;

  /// Who this phone is on [trip].
  String meIn(Trip trip) => data.identities[trip.id] ?? meId;

  /// The profile photo of [id] on [trip].
  String? photoIn(Trip trip, String id) => id == meIn(trip)
      ? data.tripPhotos[trip.id] ?? data.personById(meId)?.photoId
      : trip.memberPhotos[id];

  String nameOf(String id) => data.personById(id)?.name ?? tr('Netko');

  /// Saves a change and passes it on to the group.
  void saved() {
    store.save();
    cloud?.pushSoon();
  }

  /// Saves, passes on and redraws after a change.
  void changed() {
    saved();
    rerender();
  }

  String tripRoute(Trip trip, [String? section]) =>
      section == null ? '#/p/${trip.id}' : '#/p/${trip.id}/$section';

  /// An address an <img> can show a stored picture from; it comes from the
  /// cloud the first time this phone needs it.
  Future<String?> imageAddress(Trip trip, String id) async {
    final known = await store.blobAddress(id);
    if (known != null) return known;
    final blob = await cloud?.fetchBlob(trip, id);
    return blob == null ? null : store.blobAddress(id);
  }

  /// The link that lets someone into [trip].
  String inviteLink(Trip trip) {
    final page = web.window.location.href.split('#').first;
    return '$page#/pridruzi/${trip.id}';
  }
}
