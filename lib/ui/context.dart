import '../src/domain/models.dart';
import '../src/domain/offers.dart';
import 'anthem.dart';
import 'store.dart';

/// What every screen needs from the app.
class Ui {
  Ui({
    required this.store,
    required this.anthem,
    required this.go,
    required this.back,
    required this.openTrip,
    required this.rerender,
    required this.toast,
  });

  final AppStore store;
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

  AppData get data => store.data;

  String get meId => data.meId!;

  String nameOf(String id) => data.personById(id)?.name ?? 'Netko';

  /// Saves and redraws after a change.
  void changed() {
    store.save();
    rerender();
  }

  String tripRoute(Trip trip, [String? section]) =>
      section == null ? '#/p/${trip.id}' : '#/p/${trip.id}/$section';
}
