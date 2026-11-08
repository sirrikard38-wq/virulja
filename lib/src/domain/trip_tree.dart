import 'models.dart';
import 'tree.dart';

/// A trip as it arrives from the cloud, with the names of its group.
class CloudTrip {
  const CloudTrip(
    this.trip,
    this.names, [
    this.phones = const {},
    this.photos = const {},
  ]);

  final Trip trip;

  /// Person id -> name.
  final Map<String, String> names;

  /// Person id -> mobile number.
  final Map<String, String> phones;

  /// Person id -> profile photo.
  final Map<String, String> photos;
}

Json _withoutId(Json json) => Map.of(json)..remove('id');

/// What a member is found by when they come back on another phone: the name in
/// small letters and the last eight digits of the number, so +385 91 and 091
/// match. Null without a number. A database key cannot have . # $ [ ] or /.
String? memberKey(String name, String? phone) {
  final all = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  final digits = all.length > 8 ? all.substring(all.length - 8) : all;
  if (digits.length < 6) return null;
  final clean = name.trim().toLowerCase().replaceAll(RegExp(r'[.#$\[\]/\x00-\x1f\x7f]'), '_');
  return '${clean}_$digits';
}

Map<String, bool> _set(Iterable<String> ids) => {for (final id in ids) id: true};

/// The shape a trip has in the cloud. Lists become maps keyed by id, so that
/// adding to a list on two phones at once keeps both.
Tree tripToTree(
  Trip trip,
  String Function(String id) nameOf, [
  String? Function(String id)? phoneOf,
  String? Function(String id)? photoOf,
]) =>
    {
      'code': trip.code,
      'polls': {
        for (final poll in trip.polls)
          poll.id: {
            'title': poll.title,
            'dayIndex': poll.dayIndex,
            'active': poll.active,
            'single': poll.single,
            'addedBy': poll.addedBy,
            'activeBy': poll.activeBy,
            'activeAt': poll.activeAt,
            'autoAdded': poll.autoAdded,
            'dayVotes': {
              for (final entry in poll.dayVotes.entries)
                'd${entry.key}': _set(entry.value),
            },
            'options': {
              for (final option in poll.options)
                option.id: {'time': option.time, 'votes': _set(option.votes)},
            },
          },
      },
      'country': trip.country,
      'city': trip.city,
      'start': dayKey(trip.start),
      'end': dayKey(trip.end),
      'coverId': trip.coverId,
      'chosenOfferId': trip.chosenOfferId,
      'anthemTitle': trip.anthemTitle,
      'anthemClipId': trip.anthemClipId,
      'drive': trip.drive.toJson(),
      'people': {
        for (var i = 0; i < trip.memberIds.length; i++)
          trip.memberIds[i]: {
            'name': nameOf(trip.memberIds[i]),
            'order': i,
            'phone': phoneOf?.call(trip.memberIds[i]),
            'photo': photoOf?.call(trip.memberIds[i]),
            'uid': trip.uids[trip.memberIds[i]],
          },
      },
      'offers': {
        for (final offer in trip.offers)
          offer.id: {..._withoutId(offer.toJson()), 'votes': _set(offer.votes)},
      },
      'places': {
        for (final place in trip.places) place.id: _withoutId(place.toJson()),
      },
      'dishes': {
        for (final dish in trip.dishes) dish.id: _withoutId(dish.toJson()),
      },
      'stops': {
        for (final stop in trip.stops) stop.id: _withoutId(stop.toJson()),
      },
      'legs': {
        for (final leg in trip.legs) leg.id: _withoutId(leg.toJson()),
      },
      'kickVotes': {
        for (final entry in trip.kickVotes.entries) entry.key: _set(entry.value),
      },
      'gone': trip.gone,
      'customKinds': {
        for (final kind in trip.customKinds) kind.id: _withoutId(kind.toJson()),
      },
      'requests': {
        for (final request in trip.requests)
          request.id: {
            'name': request.name,
            'phone': request.phone,
            'person': request.personId,
            'approvals': _set(request.approvals),
          },
      },
      'expenses': {
        for (final expense in trip.expenses)
          expense.id: {
            ..._withoutId(expense.toJson()),
            'sharedBy': _set(expense.sharedBy),
          },
      },
      'payments': {
        for (final payment in trip.payments)
          payment.id: _withoutId(payment.toJson()),
      },
      'photos': {
        for (final photo in trip.photos)
          photo.id: {
            ..._withoutId(photo.toJson()),
            'comments': {
              for (final comment in photo.comments)
                comment.id: _withoutId(comment.toJson()),
            },
          },
      },
      'songs': {
        for (final song in trip.songs) song.id: _withoutId(song.toJson()),
      },
      'shopLists': {
        for (final list in trip.shopLists)
          list.id: {
            'name': list.name,
            'expenseId': list.expenseId,
            'boughtAt': list.boughtAt,
            'items': {for (final item in list.items) item.id: _withoutId(item.toJson())},
            'removed': list.removedJson,
          },
      },
      'shows': {
        for (final show in trip.shows) show.id: _withoutId(show.toJson()),
      },
      'showPicks': trip.showPicks,
      'dayShowId': trip.dayShowId,
      'budgets': trip.budgets,
      'ticked': tickedJson(trip.ticked),
      'access': trip.access,
      // One value, so that two phones choosing at once do not mix their choices.
      'currencies': trip.currencies.join(','),
      // Read one at a time by whoever knows a member's name and number.
      'keys': {
        for (final id in trip.memberIds)
          if (memberKey(nameOf(id), phoneOf?.call(id)) case final key?) key: id,
      },
    };

Tree _branch(Tree tree, String key) =>
    (tree[key] as Map<dynamic, dynamic>?)?.cast<String, dynamic>() ?? {};

/// Items of one branch, oldest id first. An item that is not whole (say, one
/// phone removed it while another changed it) is skipped, never fatal.
List<T> _items<T>(Tree tree, String key, T Function(Json) read) {
  final branch = _branch(tree, key);
  final ids = branch.keys.toList()..sort();
  final items = <T>[];
  for (final id in ids) {
    try {
      items.add(read({...(branch[id] as Map).cast<String, dynamic>(), 'id': id}));
    } on Object {
      // Not a whole item.
    }
  }
  return items;
}

List<String> _keys(Object? set) =>
    (set as Map<dynamic, dynamic>?)?.keys.cast<String>().toList() ?? [];

/// Reads a trip from the cloud. Null when it is not a whole trip.
CloudTrip? tripFromTree(String id, Tree tree) {
  try {
    final people = _branch(tree, 'people');
    final order = people.keys.toList()
      ..sort((a, b) {
        final byOrder = ((people[a] as Map)['order'] as num? ?? 0)
            .compareTo((people[b] as Map)['order'] as num? ?? 0);
        return byOrder != 0 ? byOrder : a.compareTo(b);
      });
    final photos = {
      for (final person in order)
        if ((people[person] as Map)['photo'] != null)
          person: (people[person] as Map)['photo'] as String,
    };
    final trip = Trip(
      id: id,
      memberPhotos: photos,
      country: tree['country'] as String,
      city: tree['city'] as String,
      start: parseDay(tree['start'] as String),
      end: parseDay(tree['end'] as String),
      memberIds: order,
      code: tree['code'] as String?,
      uids: {
        for (final person in order)
          if ((people[person] as Map)['uid'] != null)
            person: (people[person] as Map)['uid'] as String,
      },
      polls: _items(tree, 'polls', (json) {
        final options = _items(
            json,
            'options',
            (option) => PollOption.fromJson(
                {...option, 'votes': _keys(option['votes'])}));
        return Poll(
            id: json['id'] as String,
            title: json['title'] as String,
            options: options,
            dayIndex: json['dayIndex'] as int? ?? 0,
            active: json['active'] as bool? ?? false,
            single: json['single'] as bool? ?? false,
            addedBy: json['addedBy'] as String?,
            activeBy: json['activeBy'] as String?,
            activeAt: (json['activeAt'] as num?)?.toInt(),
            autoAdded: json['autoAdded'] as bool? ?? false,
            dayVotes: dayVotesFrom(json['dayVotes']));
      }),
      coverId: tree['coverId'] as String?,
      chosenOfferId: tree['chosenOfferId'] as String?,
      anthemTitle: tree['anthemTitle'] as String?,
      anthemClipId: tree['anthemClipId'] as String?,
      drive: tree['drive'] == null ? null : Drive.fromJson(_branch(tree, 'drive')),
      offers: _items(tree, 'offers',
          (json) => Offer.fromJson({...json, 'votes': _keys(json['votes'])})),
      places: _items(tree, 'places', Place.fromJson),
      dishes: _items(tree, 'dishes', Dish.fromJson),
      stops: _items(tree, 'stops', Stop.fromJson),
      legs: _items(tree, 'legs', Leg.fromJson),
      customKinds: _items(tree, 'customKinds', CustomKind.fromJson),
      kickVotes: {
        for (final entry in _branch(tree, 'kickVotes').entries)
          entry.key: _keys(entry.value).toSet(),
      },
      gone: _branch(tree, 'gone').cast<String, String>(),
      requests: _items(
          tree,
          'requests',
          (json) => JoinRequest.fromJson(
              {...json, 'approvals': _keys(json['approvals'])})),
      expenses: _items(tree, 'expenses', (json) {
        final sharers = _keys(json['sharedBy'])
          ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
        return Expense.fromJson({...json, 'sharedBy': sharers});
      }),
      payments: _items(tree, 'payments', Payment.fromJson),
      photos: _items(tree, 'photos', (json) {
        final comments = _items(json, 'comments', (comment) => comment);
        comments.sort((a, b) => (a['at'] as String).compareTo(b['at'] as String));
        return Photo.fromJson({...json, 'comments': comments});
      }),
      songs: _items(tree, 'songs', Song.fromJson),
      shopLists: _items(
          tree,
          'shopLists',
          (json) => ShopList(
                id: json['id'] as String,
                name: json['name'] as String,
                expenseId: json['expenseId'] as String?,
                boughtAt: (json['boughtAt'] as num?)?.toInt(),
                items: _items(json, 'items', ShopItem.fromJson),
                removed: ShopList.removedFrom(json['removed']),
              )),
      shows: _items(tree, 'shows', Show.fromJson),
      showPicks: _branch(tree, 'showPicks').cast<String, String>(),
      dayShowId: tree['dayShowId'] as String?,
      currencies: (tree['currencies'] as String? ?? '').split(','),
      access: _branch(tree, 'access').map((uid, person) => MapEntry(uid, person as String)),
      ticked: tickedFrom(tree['ticked']),
      budgets: _branch(tree, 'budgets').map((kind, cents) => MapEntry(kind, (cents as num).toInt())),
    );
    return CloudTrip(trip, {
      for (final person in order)
        person: (people[person] as Map)['name'] as String? ?? 'Netko',
    }, {
      for (final person in order)
        if ((people[person] as Map)['phone'] != null)
          person: (people[person] as Map)['phone'] as String,
    }, photos);
  } on Object {
    return null;
  }
}

/// The database rules refuse a longer text.
const int maxBlobText = 3000000;

/// How many pieces a file of [bytes] takes in the cloud, as base64 text.
int piecesFor(int bytes) => (((bytes + 2) ~/ 3) * 4 + maxBlobText - 1) ~/ maxBlobText;

/// What piece [index] of file [id] is called in the cloud.
String pieceId(String id, int index) => index == 0 ? id : '$id.$index';

/// Every picture and sound of a trip.
Iterable<String> blobIds(Trip trip) sync* {
  for (final photo in trip.photos) {
    yield photo.id;
    yield thumbId(photo.id);
  }
  final cover = trip.coverId;
  if (cover != null) {
    yield cover;
    yield thumbId(cover);
  }
  final clip = trip.anthemClipId;
  if (clip != null) yield clip;
}
