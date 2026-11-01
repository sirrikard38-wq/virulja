import 'models.dart';

/// Booking.com search for the trip's place, dates and group.
Uri bookingSearch(Trip trip) =>
    Uri.https('www.booking.com', '/searchresults.html', {
      'ss': '${trip.city}, ${trip.country}',
      'checkin': dayKey(trip.start),
      'checkout': dayKey(trip.end),
      'group_adults': '${trip.people}',
      'no_rooms': '1',
    });

/// Airbnb search for the trip's place, dates and group.
Uri airbnbSearch(Trip trip) => Uri.https(
      'www.airbnb.com',
      '/s/${_slug(trip.city)}--${_slug(trip.country)}/homes',
      {
        'checkin': dayKey(trip.start),
        'checkout': dayKey(trip.end),
        'adults': '${trip.people}',
      },
    );

String _slug(String text) => text.trim().replaceAll(RegExp(r'\s+'), '-');

/// Google Maps search for places of one kind in the trip's city.
Uri mapsSearch(PlaceKind kind, Trip trip) =>
    Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': '${kind.searchWord} ${trip.city} ${trip.country}',
    });

/// How a song link plays inside the app.
class SongPlayer {
  const SongPlayer(this.service, this.address, this.height);

  /// Spotify, YouTube or Apple Music.
  final String service;

  /// The address of the service's own player.
  final String address;

  /// Height of the player on the phone, in pixels.
  final int height;
}

/// The name of a place when its link spells it out, as long Google Maps and
/// Booking links do.
String? nameFromLink(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null) return null;
  final parts = uri.pathSegments;
  final host = uri.host.toLowerCase();
  final place = parts.indexOf('place');
  if (host.contains('google.') && place >= 0 && place + 1 < parts.length) {
    final name = parts[place + 1].replaceAll('+', ' ').trim();
    return name.isEmpty ? null : name;
  }
  if (host.contains('booking.') && parts.length >= 3 && parts.first == 'hotel') {
    final words = parts[2].split('.').first.split('-');
    return words
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
  return null;
}

/// One YouTube player for all the YouTube [links], in the given order, or null
/// when there are none. Other services cannot join a queue.
String? youTubeQueue(List<String> links) {
  final ids = [
    for (final link in links)
      if (playerFor(link) case final player? when player.service == 'YouTube')
        player.address.split('/').last,
  ];
  if (ids.isEmpty) return null;
  final rest = ids.skip(1).join(',');
  return 'https://www.youtube.com/embed/${ids.first}?playlist=$rest&playsinline=1';
}

/// True for a link to a whole YouTube playlist, which opens on YouTube.
bool isYouTubePlaylist(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null) return false;
  return uri.host.toLowerCase().endsWith('youtube.com') &&
      uri.path == '/playlist' &&
      uri.queryParameters.containsKey('list');
}

/// The official player for a song link, or null if the link is not one the app
/// can play.
SongPlayer? playerFor(String link) {
  final uri = Uri.tryParse(link.trim());
  if (uri == null || !uri.hasAuthority) return null;
  final host = uri.host.toLowerCase();
  final parts = uri.pathSegments.where((part) => part.isNotEmpty).toList();

  if (host == 'open.spotify.com') {
    const kinds = {'track', 'album', 'playlist'};
    final at = parts.indexWhere(kinds.contains);
    if (at < 0 || at + 1 >= parts.length) return null;
    final isTrack = parts[at] == 'track';
    return SongPlayer(
      'Spotify',
      'https://open.spotify.com/embed/${parts[at]}/${parts[at + 1]}',
      isTrack ? 152 : 352,
    );
  }

  if (host == 'youtu.be' && parts.isNotEmpty) return _youTube(parts.first);
  if (host == 'youtube.com' ||
      host == 'www.youtube.com' ||
      host == 'm.youtube.com' ||
      host == 'music.youtube.com') {
    final id = uri.queryParameters['v'] ??
        (parts.length == 2 && parts.first == 'shorts' ? parts[1] : null);
    return id == null ? null : _youTube(id);
  }

  if (host == 'music.apple.com') {
    final song = uri.queryParameters['i'];
    final query = song == null ? '' : '?i=$song';
    return SongPlayer(
      'Apple Music',
      'https://embed.music.apple.com/${parts.join('/')}$query',
      song == null ? 450 : 152,
    );
  }
  return null;
}

SongPlayer _youTube(String id) =>
    SongPlayer('YouTube', 'https://www.youtube.com/embed/$id', 200);
