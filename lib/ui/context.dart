import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import '../src/domain/offers.dart';
import 'anthem.dart';
import 'cloud.dart';
import 'store.dart';

/// What every screen needs from the app.
class Ui {
  Ui({
    required this.store,
    required this.cloud,
    required this.anthem,
    required this.go,
    required this.back,
    required this.openTrip,
    required this.rerender,
    required this.toast,
  });

  final AppStore store;

  /// Null when the app runs without the cloud.
  final CloudSync? cloud;
  final AnthemPlayer anthem;

  /// Moves to a route such as `#/p/<trip>/smjestaj`.
  final void Function(String route) go;

  /// One screen back, like the phone's back button.
  final void Function() back;

  /// Opens a trip from a list; this is what starts its anthem.
  final void Function(Trip trip) openTrip;

  final void Function() rerender;

  /// A short message that disappears by itself.
  final void Function(String message) toast;

  // What the screens remember while the app is open.
  OfferSort offerSort = OfferSort.price;
  PlaceKind placeKind = PlaceKind.restaurant;
  int routeDay = 0;
  String? playingSongId;
  String? replyingTo;

  AppData get data => store.data;

  String get meId => data.meId!;

  /// Who this phone is on [trip].
  String meIn(Trip trip) => data.identities[trip.id] ?? meId;

  String nameOf(String id) => data.personById(id)?.name ?? 'Netko';

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
