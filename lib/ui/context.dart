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
  final void Function(String message) toast;

  /// A short message with a way to take back what was just done.
  final void Function(String message, void Function() undo) offerUndo;

  // What the screens remember while the app is open.
  OfferSort offerSort = OfferSort.price;
  PlaceKind placeKind = PlaceKind.restaurant;

  /// The group's own category that is open, instead of [placeKind].
  String? customKindId;
  bool addingKind = false;
  int routeDay = 0;
  String? playingSongId;
  String? queueAddress;
  String? replyingTo;
  bool showPeople = false;
  PeopleFold? peopleFold;

  AppData get data => store.data;

  String get meId => data.meId!;

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
