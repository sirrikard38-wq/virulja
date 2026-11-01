import 'models.dart';

/// Something in a trip people get a notification about.
class TripEvent {
  const TripEvent(this.key, this.text, this.route, {this.from, this.to});

  /// Stays the same for as long as the thing exists: how it is known as seen.
  final String key;
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
  String name(String id) => names[id] ?? 'Netko';
  final events = <TripEvent>[
    for (final poll in trip.polls) ...[
      TripEvent('poll:${poll.id}', 'Nova anketa: ${poll.title}', 'ankete',
          from: poll.addedBy),
      if (poll.active)
        TripEvent('attack:${poll.id}', 'U Planu napada: ${poll.title}', 'napad',
            from: poll.activeBy),
    ],
    for (final stop in trip.stops)
      TripEvent('stop:${stop.id}', 'Novo u Planu napada: ${stop.title}', 'napad',
          from: stop.addedBy),
  ];

  void reactions(Map<String, Set<Reaction>> given, String id, String owner,
      String text, String route) {
    for (final entry in given.entries) {
      for (final reaction in entry.value) {
        events.add(TripEvent('react:$id:${entry.key}:${reaction.name}',
            '${name(entry.key)} $text', route, from: entry.key, to: owner));
      }
    }
  }

  for (final photo in trip.photos) {
    final route = 'foto/${photo.id}';
    reactions(photo.reactions, photo.id, photo.addedBy,
        'reagira na tvoju fotografiju', route);
    for (final comment in photo.comments) {
      String? parentAuthor;
      for (final other in photo.comments) {
        if (other.id == comment.replyTo) parentAuthor = other.authorId;
      }
      events.add(TripEvent(
        'comment:${comment.id}',
        parentAuthor == null
            ? '${name(comment.authorId)} komentira tvoju fotografiju'
            : '${name(comment.authorId)} odgovara na tvoj komentar',
        route,
        from: comment.authorId,
        to: parentAuthor ?? photo.addedBy,
      ));
      reactions(comment.reactions, comment.id, comment.authorId,
          'reagira na tvoj komentar', route);
    }
  }
  return [
    for (final event in events)
      if (event.from == null || event.from != event.to) event,
  ];
}
