import 'models.dart';
import 'tree.dart';

/// A trip as it arrives from the cloud, with the names of its group.
class CloudTrip {
  const CloudTrip(this.trip, this.names, [this.phones = const {}]);

  final Trip trip;

  /// Person id -> name.
  final Map<String, String> names;

  /// Person id -> mobile number.
  final Map<String, String> phones;
}

Json _withoutId(Json json) => Map.of(json)..remove('id');

Map<String, bool> _set(Iterable<String> ids) => {for (final id in ids) id: true};

/// The shape a trip has in the cloud. Lists become maps keyed by id, so that
/// adding to a list on two phones at once keeps both.
Tree tripToTree(
  Trip trip,
  String Function(String id) nameOf, [
  String? Function(String id)? phoneOf,
]) =>
    {
      'code': trip.code,
      'admins': _set(trip.adminIds),
      // The database rules read this to let admins lock someone out.
      'adminUids': _set([
        for (final id in trip.adminIds)
          if (trip.uids[id] != null) trip.uids[id]!,
      ]),
      'polls': {
        for (final poll in trip.polls)
          poll.id: {
            'title': poll.title,
            'dayIndex': poll.dayIndex,
            'active': poll.active,
            'single': poll.single,
            'addedBy': poll.addedBy,
            'activeBy': poll.activeBy,
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
      'requests': {
        for (final request in trip.requests)
          request.id: {
            'name': request.name,
            'phone': request.phone,
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
    final trip = Trip(
      id: id,
      country: tree['country'] as String,
      city: tree['city'] as String,
      start: parseDay(tree['start'] as String),
      end: parseDay(tree['end'] as String),
      memberIds: order,
      code: tree['code'] as String?,
      adminIds: _keys(tree['admins'])..sort(),
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
    );
    return CloudTrip(trip, {
      for (final person in order)
        person: (people[person] as Map)['name'] as String? ?? 'Netko',
    }, {
      for (final person in order)
        if ((people[person] as Map)['phone'] != null)
          person: (people[person] as Map)['phone'] as String,
    });
  } on Object {
    return null;
  }
}

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
