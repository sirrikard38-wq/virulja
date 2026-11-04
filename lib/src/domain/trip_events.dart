import 'attack.dart';
import 'format.dart';
import 'i18n.dart';
import 'models.dart';

/// The kinds of notification, each of which a phone can turn off for every trip
/// or for one.
enum Notice {
  reminders('Podsjetnici prije putovanja'),
  polls('Nove ankete'),
  plan('Novo u Planu napada'),
  agreed('Izglasane ankete i dogovoreni dani'),
  photos('Nove uspomene'),
  reactions('Reakcije na tvoje uspomene i komentare'),
  comments('Komentari i odgovori'),
  joins('Novi članovi i zahtjevi za ulazak'),
  leaves('Izbacivanje iz grupe'),
  shop('Promjene na listama za dućan');

  const Notice(this._label);

  final String _label;

  String get label => tr(_label);
}

/// Something in a trip people get a notification about.
class TripEvent {
  const TripEvent(this.key, this.notice, this.text, this.route,
      {this.from, this.to});

  /// Stays the same for as long as the thing exists: how it is known as seen.
  final String key;
  final Notice notice;
  final String text;

  /// Where a tap on the notification leads, after `#/p/<trip>/`.
  final String route;

  /// The person who did it, who is not told about it. Null when not known.
  final String? from;

  /// The one person it concerns. Null means the whole group.
  final String? to;
}

/// Everything in [trip] that makes a notification. [names] gives person id ->
/// name. The wording avoids he or she: names say nothing about that.
List<TripEvent> tripEvents(Trip trip, Map<String, String> names) {
  String name(String id) => names[id] ?? tr('Netko');
  // A place voted into Plan napada is told about once, as voted.
  final agreed = {
    for (final poll in trip.polls)
      if (agreedOption(trip, poll) != null) poll.title,
  };
  final events = <TripEvent>[
    for (final poll in trip.polls) ...[
      TripEvent('poll:${poll.id}', Notice.polls,
          tr('Nova anketa: {0}', [poll.title]), 'ankete',
          from: poll.addedBy),
      if (agreedOption(trip, poll) != null)
        TripEvent(
            'passed:${poll.id}',
            Notice.agreed,
            tr('Izglasano: {0}', [poll.title]),
            pollInAttack(trip, poll) ? 'napad' : 'ankete')
      else if (poll.active)
        TripEvent('attack:${poll.id}', Notice.plan,
            tr('U Planu napada: {0}', [poll.title]), 'napad',
            from: poll.activeBy),
    ],
    for (final place in trip.places)
      if (place.planned && !agreed.contains(place.name))
        TripEvent('place:${place.id}', Notice.plan,
            tr('Novo u Planu napada: {0}', [place.name]), 'napad',
            from: place.plannedBy),
    for (final stop in trip.stops)
      TripEvent('stop:${stop.id}', Notice.plan,
          tr('Novo u Planu napada: {0}', [stop.title]), 'napad',
          from: stop.addedBy),
    // A day the group agreed on, for each thing in Plan napada.
    for (final item in planOfAttack(trip, DateTime.now()))
      for (final day in agreedDays(trip, item.dayVotes))
        TripEvent(
            'day:${item.id}:$day',
            Notice.agreed,
            tr('Dogovoreno: {0}, {1}',
                [item.title, weekdayAndDate(trip.dayAt(day))]),
            'napad'),
    for (final photo in trip.photos)
      TripEvent('photo:${photo.id}', Notice.photos,
          tr('{0} dodaje novu uspomenu', [name(photo.addedBy)]), 'slike',
          from: photo.addedBy),
    // Everyone may need to vote, except the person it is about.
    for (final person in trip.kickVotes.keys)
      TripEvent('kick:$person', Notice.leaves,
          tr('Glasanje za izbacivanje: {0}', [name(person)]), 'plan',
          from: person),
    for (final list in trip.shopLists) ...[
      for (final item in list.items)
        TripEvent('shop:${item.id}', Notice.shop,
            tr('{0} dodaje na listu {1}: {2}', [name(item.addedBy ?? ''), list.name, item.text]),
            'ducan', from: item.addedBy),
      for (final entry in list.removed.entries)
        TripEvent('shopgone:${entry.key}', Notice.shop,
            tr('{0} miče s liste {1}: {2}', [name(entry.value.by ?? ''), list.name, entry.value.text]),
            'ducan', from: entry.value.by),
    ],
    for (final entry in trip.gone.entries)
      TripEvent('left:${entry.key}', Notice.leaves,
          tr('{0} više nije na putovanju', [entry.value]), 'plan',
          from: entry.key),
    for (final request in trip.requests)
      TripEvent('request:${request.id}', Notice.joins,
          tr('{0} želi na putovanje', [request.name]), 'plan'),
    for (final person in trip.memberIds)
      TripEvent('member:$person', Notice.joins,
          tr('{0} je sada na putovanju', [name(person)]), 'plan',
          from: person),
  ];

  void reactions(Map<String, Set<Reaction>> given, String id, String owner,
      String text, String route) {
    for (final entry in given.entries) {
      for (final reaction in entry.value) {
        events.add(TripEvent('react:$id:${entry.key}:${reaction.name}',
            Notice.reactions, tr(text, [name(entry.key)]), route,
            from: entry.key, to: owner));
      }
    }
  }

  for (final photo in trip.photos) {
    final route = 'foto/${photo.id}';
    reactions(photo.reactions, photo.id, photo.addedBy,
        '{0} reagira na tvoju fotografiju', route);
    for (final comment in photo.comments) {
      String? parentAuthor;
      for (final other in photo.comments) {
        if (other.id == comment.replyTo) parentAuthor = other.authorId;
      }
      events.add(TripEvent(
        'comment:${comment.id}',
        Notice.comments,
        parentAuthor == null
            ? tr('{0} komentira tvoju fotografiju', [name(comment.authorId)])
            : tr('{0} odgovara na tvoj komentar', [name(comment.authorId)]),
        route,
        from: comment.authorId,
        to: parentAuthor ?? photo.addedBy,
      ));
      reactions(comment.reactions, comment.id, comment.authorId,
          '{0} reagira na tvoj komentar', route);
    }
  }
  return [
    for (final event in events)
      if (event.from == null || event.from != event.to) event,
  ];
}

/// Kinds of news that came with versions of the news. A trip whose seen list
/// does not have this mark yet takes them as already told, so that its past is
/// not news. A kind added later goes in here, with a new mark.
const String newsVersion = '#3';
const Set<String> _newInVersion2 = {
  'passed',
  'place',
  'day',
  'photo',
  'left',
  'member',
  'shop',
  'shopgone',
};

/// Whether the phone [device], as stored under `/push`, wants [notice] from the
/// trip [tripId].
bool wantsNotice(Map<dynamic, dynamic> device, String tripId, Notice notice) {
  bool off(Object? kinds) => (kinds as Map?)?.containsKey(notice.name) ?? false;
  final trip = ((device['trips'] as Map?) ?? const {})[tripId] as Map?;
  return !off(device['off']) && !off(trip?['off']);
}

/// What the phone of [uid] is told about [trip]: what is new since [told], what
/// it wants, not what that person did. New photos of one person make one message.
List<({String body, String route})> newsFor(
  String uid,
  String tripId,
  Trip trip,
  Map<String, String> names,
  Set<Object?> told,
  Map<dynamic, dynamic> device,
) {
  final versioned = told.contains(newsVersion);
  final news = <({String body, String route})>[];
  final photos = <String?, int>{};
  for (final event in tripEvents(trip, names)) {
    final isOld = told.contains(event.key) ||
        !versioned && _newInVersion2.contains(event.key.split(':').first);
    final isSender = event.from != null && trip.uids[event.from] == uid;
    final isForThem = event.to == null || trip.uids[event.to] == uid;
    if (isOld || isSender || !isForThem || !wantsNotice(device, tripId, event.notice)) {
      continue;
    }
    if (event.notice == Notice.photos) {
      photos[event.from] = (photos[event.from] ?? 0) + 1;
    } else {
      news.add((body: event.text, route: event.route));
    }
  }
  for (final entry in photos.entries) {
    final who = names[entry.key] ?? tr('Netko');
    news.add((
      body: entry.value == 1
          ? tr('{0} dodaje novu uspomenu', [who])
          : tr('{0} dodaje nove uspomene ({1})', [who, entry.value]),
      route: 'slike',
    ));
  }
  return news;
}
