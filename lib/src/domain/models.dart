/// What the app stores: people, trips and everything inside a trip.
///
/// Money is always in whole cents, so sums never drift. Days are UTC midnights,
/// so counting days never trips over a clock change.
library;

typedef Json = Map<String, dynamic>;

List<T> _list<T>(Object? raw, T Function(Json) read) => [
      for (final item in (raw as List<dynamic>? ?? const <dynamic>[]))
        read(item as Json)
    ];

List<String> _strings(Object? raw) => [
      for (final item in (raw as List<dynamic>? ?? const <dynamic>[]))
        item as String
    ];

/// A calendar day as a UTC midnight.
DateTime dayOf(int year, int month, int day) => DateTime.utc(year, month, day);

/// Today on this device.
DateTime today([DateTime? now]) {
  final clock = now ?? DateTime.now();
  return dayOf(clock.year, clock.month, clock.day);
}

/// `2027-06-12`
String dayKey(DateTime day) => '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

DateTime parseDay(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return dayOf(parts[0], parts[1], parts[2]);
}

class Person {
  Person({required this.id, required this.name, this.phone});

  factory Person.fromJson(Json json) => Person(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
      );

  final String id;
  String name;
  String? phone;

  Json toJson() => {'id': id, 'name': name, 'phone': phone};
}

/// One time people can vote for.
class PollOption {
  PollOption({required this.id, required this.time, Set<String>? votes})
      : votes = votes ?? {};

  factory PollOption.fromJson(Json json) => PollOption(
        id: json['id'] as String,
        time: json['time'] as String,
        votes: _strings(json['votes']).toSet(),
      );

  final String id;
  final String time;
  Set<String> votes;

  Json toJson() => {'id': id, 'time': time, 'votes': votes.toList()};
}

/// A vote on when to do something.
class Poll {
  Poll({
    required this.id,
    required this.title,
    required this.options,
    this.dayIndex = 0,
    this.active = false,
    this.single = false,
    this.addedBy,
    this.activeBy,
  });

  factory Poll.fromJson(Json json) => Poll(
        id: json['id'] as String,
        title: json['title'] as String,
        options: _list(json['options'], PollOption.fromJson),
        dayIndex: json['dayIndex'] as int? ?? 0,
        active: json['active'] as bool? ?? false,
        single: json['single'] as bool? ?? false,
        addedBy: json['addedBy'] as String?,
        activeBy: json['activeBy'] as String?,
      );

  final String id;
  final String title;
  final List<PollOption> options;
  int dayIndex;

  /// Whether its result shows in the plan of attack.
  bool active;

  /// Whether each person may pick only one option.
  final bool single;
  final String? addedBy;

  /// Who put it in the plan of attack.
  String? activeBy;

  Json toJson() => {
        'id': id,
        'title': title,
        'dayIndex': dayIndex,
        'active': active,
        'single': single,
        'addedBy': addedBy,
        'activeBy': activeBy,
        'options': [for (final option in options) option.toJson()],
      };
}

/// A place to stay the group is comparing.
class Offer {
  Offer({
    required this.id,
    required this.name,
    required this.pricePerNight,
    this.rating,
    this.beachMeters,
    this.source = 'Ručno',
    this.link,
    Set<String>? votes,
  }) : votes = votes ?? {};

  factory Offer.fromJson(Json json) => Offer(
        id: json['id'] as String,
        name: json['name'] as String,
        pricePerNight: json['pricePerNight'] as int,
        rating: (json['rating'] as num?)?.toDouble(),
        beachMeters: json['beachMeters'] as int?,
        source: json['source'] as String? ?? 'Ručno',
        link: json['link'] as String?,
        votes: _strings(json['votes']).toSet(),
      );

  final String id;
  String name;
  int pricePerNight;
  double? rating;
  int? beachMeters;
  String source;
  String? link;
  Set<String> votes;

  Json toJson() => {
        'id': id,
        'name': name,
        'pricePerNight': pricePerNight,
        'rating': rating,
        'beachMeters': beachMeters,
        'source': source,
        'link': link,
        'votes': votes.toList(),
      };
}

enum PlaceKind {
  restaurant('Restorani', 'restorani'),
  cafe('Kafići', 'kafići'),
  beachBar('Beach barovi', 'beach bar'),
  wineShop('Vinoteke', 'vinoteka'),
  winery('Vinarije', 'vinarija');

  const PlaceKind(this.label, this.searchWord);

  final String label;

  /// What to look for on Google Maps.
  final String searchWord;
}

/// A restaurant, cafe, beach bar, wine shop or winery.
class Place {
  Place({
    required this.id,
    required this.kind,
    required this.name,
    this.rating,
    this.pricePerPerson,
    this.note,
    this.link,
    this.planned = false,
  });

  factory Place.fromJson(Json json) => Place(
        id: json['id'] as String,
        kind: PlaceKind.values.byName(json['kind'] as String),
        name: json['name'] as String,
        rating: (json['rating'] as num?)?.toDouble(),
        pricePerPerson: json['pricePerPerson'] as int?,
        note: json['note'] as String?,
        link: json['link'] as String?,
        planned: json['planned'] as bool? ?? false,
      );

  final String id;
  PlaceKind kind;
  String name;
  double? rating;
  int? pricePerPerson;
  String? note;
  String? link;
  bool planned;

  Json toJson() => {
        'id': id,
        'kind': kind.name,
        'name': name,
        'rating': rating,
        'pricePerPerson': pricePerPerson,
        'note': note,
        'link': link,
        'planned': planned,
      };
}

/// A dish the group wants to try, with its price from the menu.
class Dish {
  Dish({
    required this.id,
    required this.name,
    required this.price,
    this.placeName,
    this.servings = 1,
  });

  factory Dish.fromJson(Json json) => Dish(
        id: json['id'] as String,
        name: json['name'] as String,
        price: json['price'] as int,
        placeName: json['placeName'] as String?,
        servings: json['servings'] as int? ?? 1,
      );

  final String id;
  String name;
  int price;
  String? placeName;
  int servings;

  Json toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'placeName': placeName,
        'servings': servings,
      };
}

/// One thing on one day of the plan.
class Stop {
  Stop({
    required this.id,
    required this.dayIndex,
    required this.title,
    this.time = '',
    this.cost = 0,
    this.addedBy,
  });

  factory Stop.fromJson(Json json) => Stop(
        id: json['id'] as String,
        dayIndex: json['dayIndex'] as int,
        title: json['title'] as String,
        time: json['time'] as String? ?? '',
        cost: json['cost'] as int? ?? 0,
        addedBy: json['addedBy'] as String?,
      );

  final String id;
  int dayIndex;
  String title;

  /// `08:30`, or empty when the time does not matter.
  String time;
  int cost;
  final String? addedBy;

  Json toJson() => {
        'id': id,
        'dayIndex': dayIndex,
        'title': title,
        'time': time,
        'cost': cost,
        'addedBy': addedBy,
      };
}

/// One piece of the journey by any means: a flight, a train, a ferry.
class Leg {
  Leg({required this.id, required this.title, this.cost = 0});

  factory Leg.fromJson(Json json) => Leg(
        id: json['id'] as String,
        title: json['title'] as String,
        cost: json['cost'] as int? ?? 0,
      );

  final String id;
  String title;
  int cost;

  Json toJson() => {'id': id, 'title': title, 'cost': cost};
}

/// The drive there: the part of the transport estimate worked out from fuel.
class Drive {
  Drive({
    this.route = '',
    this.kilometres = 0,
    this.roundTrip = true,
    this.litresPer100 = 7,
    this.fuelPrice = 150,
    this.cars = 1,
    this.tolls = 0,
    this.ferry = 0,
  });

  factory Drive.fromJson(Json json) => Drive(
        route: json['route'] as String? ?? '',
        kilometres: (json['kilometres'] as num?)?.toDouble() ?? 0,
        roundTrip: json['roundTrip'] as bool? ?? true,
        litresPer100: (json['litresPer100'] as num?)?.toDouble() ?? 7,
        fuelPrice: json['fuelPrice'] as int? ?? 150,
        cars: json['cars'] as int? ?? 1,
        tolls: json['tolls'] as int? ?? 0,
        ferry: json['ferry'] as int? ?? 0,
      );

  String route;

  /// One way.
  double kilometres;
  bool roundTrip;
  double litresPer100;

  /// Cents per litre.
  int fuelPrice;
  int cars;

  /// All cars, both ways.
  int tolls;

  /// All cars, both ways.
  int ferry;

  int get fuelCost {
    final distance = kilometres * (roundTrip ? 2 : 1);
    return (distance / 100 * litresPer100 * fuelPrice * cars).round();
  }

  int get totalCost => fuelCost + tolls + ferry;

  Json toJson() => {
        'route': route,
        'kilometres': kilometres,
        'roundTrip': roundTrip,
        'litresPer100': litresPer100,
        'fuelPrice': fuelPrice,
        'cars': cars,
        'tolls': tolls,
        'ferry': ferry,
      };
}

enum CostCategory {
  stay('Smještaj'),
  food('Hrana i piće'),
  transport('Prijevoz'),
  activities('Izleti i vino'),
  other('Ostalo');

  const CostCategory(this.label);

  final String label;
}

/// Money someone really spent on the trip.
class Expense {
  Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.payerId,
    required this.sharedBy,
    this.category = CostCategory.other,
  });

  factory Expense.fromJson(Json json) => Expense(
        id: json['id'] as String,
        title: json['title'] as String,
        amount: json['amount'] as int,
        payerId: json['payerId'] as String,
        sharedBy: _strings(json['sharedBy']),
        category: CostCategory.values.byName(json['category'] as String),
      );

  final String id;
  String title;
  int amount;
  String payerId;

  /// Everyone who shares this cost, in the order of the group.
  List<String> sharedBy;
  CostCategory category;

  Json toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'payerId': payerId,
        'sharedBy': sharedBy,
        'category': category.name,
      };
}

/// One person paying another back.
class Payment {
  Payment({
    String? id,
    required this.fromId,
    required this.toId,
    required this.amount,
  }) : id = id ?? '$fromId-$toId-$amount';

  factory Payment.fromJson(Json json) => Payment(
        id: json['id'] as String?,
        fromId: json['fromId'] as String,
        toId: json['toId'] as String,
        amount: json['amount'] as int,
      );

  final String id;
  final String fromId;
  final String toId;
  final int amount;

  Json toJson() =>
      {'id': id, 'fromId': fromId, 'toId': toId, 'amount': amount};
}

enum Reaction {
  heart('Srce'),
  laugh('Smijeh'),
  cheers('Živjeli'),
  sun('Sunce'),
  star('Zvijezda');

  const Reaction(this.label);

  final String label;
}

/// Person -> their reactions. Older saves hold one reaction name per person.
Map<String, Set<Reaction>> _reactionsFrom(Object? raw) {
  final reactions = <String, Set<Reaction>>{};
  (raw as Json? ?? const <String, dynamic>{}).forEach((person, value) {
    final names = value is String ? [value] : (value as Map).keys.cast<String>();
    reactions[person] = {for (final name in names) Reaction.values.byName(name)};
  });
  return reactions;
}

Json _reactionsToJson(Map<String, Set<Reaction>> reactions) => {
      for (final entry in reactions.entries)
        entry.key: {for (final reaction in entry.value) reaction.name: true},
    };

/// How many people gave [reaction].
int reactionCount(Map<String, Set<Reaction>> reactions, Reaction reaction) =>
    reactions.values.where((given) => given.contains(reaction)).length;

/// Adds [reaction] of [person], or takes it away if it is already there.
void toggleReaction(
  Map<String, Set<Reaction>> reactions,
  String person,
  Reaction reaction,
) {
  final given = reactions[person] ??= {};
  if (!given.remove(reaction)) given.add(reaction);
  if (given.isEmpty) reactions.remove(person);
}

class Comment {
  Comment({
    required this.id,
    required this.authorId,
    required this.text,
    required this.at,
    this.replyTo,
    Map<String, Set<Reaction>>? reactions,
  }) : reactions = reactions ?? {};

  factory Comment.fromJson(Json json) => Comment(
        id: json['id'] as String,
        authorId: json['authorId'] as String,
        text: json['text'] as String,
        at: DateTime.parse(json['at'] as String),
        replyTo: json['replyTo'] as String?,
        reactions: _reactionsFrom(json['reactions']),
      );

  final String id;
  final String authorId;
  final String text;
  final DateTime at;

  /// The comment this one answers.
  final String? replyTo;
  Map<String, Set<Reaction>> reactions;

  Json toJson() => {
        'id': id,
        'authorId': authorId,
        'text': text,
        'at': at.toIso8601String(),
        'replyTo': replyTo,
        'reactions': _reactionsToJson(reactions),
      };
}

/// The small picture of photo [id] for lists and grids.
String thumbId(String id) => '$id.t';

/// A photo of the trip. The picture itself is kept apart, under its [id].
class Photo {
  Photo({
    required this.id,
    required this.takenAt,
    required this.addedBy,
    this.latitude,
    this.longitude,
    this.stored = false,
    Map<String, Set<Reaction>>? reactions,
    List<Comment>? comments,
  })  : reactions = reactions ?? {},
        comments = comments ?? [];

  factory Photo.fromJson(Json json) => Photo(
        id: json['id'] as String,
        takenAt: DateTime.parse(json['takenAt'] as String),
        addedBy: json['addedBy'] as String,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        stored: json['stored'] as bool? ?? false,
        reactions: _reactionsFrom(json['reactions']),
        comments: _list(json['comments'], Comment.fromJson),
      );

  final String id;

  /// When the photo was taken, as the phone's clock showed it.
  final DateTime takenAt;
  final String addedBy;
  final double? latitude;
  final double? longitude;

  /// True once the picture is in the cloud, for the rest of the group to see.
  bool stored;

  /// Anyone can give several reactions.
  Map<String, Set<Reaction>> reactions;
  List<Comment> comments;

  DateTime get day => dayOf(takenAt.year, takenAt.month, takenAt.day);

  Json toJson() => {
        'id': id,
        'takenAt': takenAt.toIso8601String(),
        'addedBy': addedBy,
        'latitude': latitude,
        'longitude': longitude,
        'stored': stored,
        'reactions': _reactionsToJson(reactions),
        'comments': [for (final comment in comments) comment.toJson()],
      };
}

/// A song on the playlist, linked from Spotify, YouTube or Apple Music.
class Song {
  Song({
    required this.id,
    required this.title,
    required this.link,
    required this.addedBy,
  });

  factory Song.fromJson(Json json) => Song(
        id: json['id'] as String,
        title: json['title'] as String,
        link: json['link'] as String,
        addedBy: json['addedBy'] as String,
      );

  final String id;
  String title;
  String link;
  final String addedBy;

  Json toJson() => {
        'id': id,
        'title': title,
        'link': link,
        'addedBy': addedBy,
      };
}

enum TripPhase { upcoming, active, past }

class Trip {
  Trip({
    required this.id,
    required this.country,
    required this.city,
    required this.start,
    required this.end,
    required this.memberIds,
    this.coverId,
    this.chosenOfferId,
    this.anthemTitle,
    this.anthemClipId,
    this.code,
    List<String>? adminIds,
    Map<String, String>? uids,
    List<Poll>? polls,
    List<Offer>? offers,
    List<Place>? places,
    List<Dish>? dishes,
    List<Stop>? stops,
    List<Leg>? legs,
    List<JoinRequest>? requests,
    Drive? drive,
    List<Expense>? expenses,
    List<Payment>? payments,
    List<Photo>? photos,
    List<Song>? songs,
  })  : adminIds = adminIds ?? [],
        uids = uids ?? {},
        polls = polls ?? [],
        offers = offers ?? [],
        places = places ?? [],
        dishes = dishes ?? [],
        stops = stops ?? [],
        legs = legs ?? [],
        requests = requests ?? [],
        drive = drive ?? Drive(),
        expenses = expenses ?? [],
        payments = payments ?? [],
        photos = photos ?? [],
        songs = songs ?? [];

  factory Trip.fromJson(Json json) => Trip(
        id: json['id'] as String,
        country: json['country'] as String,
        city: json['city'] as String,
        start: parseDay(json['start'] as String),
        end: parseDay(json['end'] as String),
        memberIds: _strings(json['memberIds']),
        coverId: json['coverId'] as String?,
        chosenOfferId: json['chosenOfferId'] as String?,
        anthemTitle: json['anthemTitle'] as String?,
        anthemClipId: json['anthemClipId'] as String?,
        code: json['code'] as String?,
        adminIds: _strings(json['adminIds']),
        uids: (json['uids'] as Json? ?? const <String, dynamic>{})
            .cast<String, String>(),
        polls: _list(json['polls'], Poll.fromJson),
        offers: _list(json['offers'], Offer.fromJson),
        places: _list(json['places'], Place.fromJson),
        dishes: _list(json['dishes'], Dish.fromJson),
        stops: _list(json['stops'], Stop.fromJson),
        legs: _list(json['legs'], Leg.fromJson),
        requests: _list(json['requests'], JoinRequest.fromJson),
        drive: json['drive'] == null
            ? null
            : Drive.fromJson(json['drive'] as Json),
        expenses: _list(json['expenses'], Expense.fromJson),
        payments: _list(json['payments'], Payment.fromJson),
        photos: _list(json['photos'], Photo.fromJson),
        songs: _list(json['songs'], Song.fromJson),
      );

  final String id;
  String country;
  String city;
  DateTime start;
  DateTime end;

  /// The group of this trip, in a fixed order.
  List<String> memberIds;

  /// The photo on the postcard.
  String? coverId;
  String? chosenOfferId;

  /// The song that opens the trip, and its stored first 10 seconds.
  String? anthemTitle;
  String? anthemClipId;

  /// The 10 digits that let someone into the trip.
  String? code;

  /// Who can remove people and make others admins.
  List<String> adminIds;

  /// Person id -> their sign-in id, needed to lock someone out.
  Map<String, String> uids;
  List<Poll> polls;

  List<Offer> offers;
  List<Place> places;
  List<Dish> dishes;
  List<Stop> stops;
  List<Leg> legs;
  List<JoinRequest> requests;
  Drive drive;
  List<Expense> expenses;
  List<Payment> payments;
  List<Photo> photos;
  List<Song> songs;

  int get nights => end.difference(start).inDays;

  /// Calendar days from the first to the last, both included.
  int get dayCount => nights + 1;

  int get people => memberIds.length;

  /// How many members must let a newcomer in. Someone alone on a trip is not
  /// asked; a group of two must both agree.
  int get approvalsNeeded => memberIds.length <= 1 ? 0 : 2;

  DateTime dayAt(int index) => start.add(Duration(days: index));

  /// Offers are compared here; this is the one the group picked, if any.
  Offer? get chosenOffer {
    for (final offer in offers) {
      if (offer.id == chosenOfferId) return offer;
    }
    return null;
  }

  TripPhase phaseOn(DateTime day) {
    if (day.isBefore(start)) return TripPhase.upcoming;
    if (day.isAfter(end)) return TripPhase.past;
    return TripPhase.active;
  }

  /// Takes over everything from [other], keeping this same object, so a screen
  /// that is open on this trip keeps working on the real thing.
  void copyFrom(Trip other) {
    country = other.country;
    city = other.city;
    start = other.start;
    end = other.end;
    memberIds = other.memberIds;
    coverId = other.coverId;
    chosenOfferId = other.chosenOfferId;
    anthemTitle = other.anthemTitle;
    anthemClipId = other.anthemClipId;
    code = other.code;
    adminIds = other.adminIds;
    uids = other.uids;
    polls = other.polls;
    offers = other.offers;
    places = other.places;
    dishes = other.dishes;
    stops = other.stops;
    legs = other.legs;
    requests = other.requests;
    drive = other.drive;
    expenses = other.expenses;
    payments = other.payments;
    photos = other.photos;
    songs = other.songs;
  }

  Json toJson() => {
        'id': id,
        'country': country,
        'city': city,
        'start': dayKey(start),
        'end': dayKey(end),
        'memberIds': memberIds,
        'coverId': coverId,
        'chosenOfferId': chosenOfferId,
        'anthemTitle': anthemTitle,
        'anthemClipId': anthemClipId,
        'code': code,
        'adminIds': adminIds,
        'uids': uids,
        'polls': [for (final item in polls) item.toJson()],
        'offers': [for (final item in offers) item.toJson()],
        'places': [for (final item in places) item.toJson()],
        'dishes': [for (final item in dishes) item.toJson()],
        'stops': [for (final item in stops) item.toJson()],
        'legs': [for (final item in legs) item.toJson()],
        'requests': [for (final item in requests) item.toJson()],
        'drive': drive.toJson(),
        'expenses': [for (final item in expenses) item.toJson()],
        'payments': [for (final item in payments) item.toJson()],
        'photos': [for (final item in photos) item.toJson()],
        'songs': [for (final item in songs) item.toJson()],
      };
}

enum ThemeChoice {
  system('Kao mobitel'),
  light('Svijetlo'),
  dark('Tamno');

  const ThemeChoice(this.label);

  final String label;
}

/// Someone who entered the right code and waits for the group to let them in.
class JoinRequest {
  JoinRequest({
    required this.id,
    required this.name,
    this.phone,
    Set<String>? approvals,
  }) : approvals = approvals ?? {};

  factory JoinRequest.fromJson(Json json) => JoinRequest(
        id: json['id'] as String,
        name: json['name'] as String,
        phone: json['phone'] as String?,
        approvals: _strings(json['approvals']).toSet(),
      );

  /// The sign-in id of the phone that asks.
  final String id;
  final String name;
  final String? phone;

  /// The members who said yes.
  final Set<String> approvals;

  Json toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'approvals': approvals.toList(),
      };
}

/// Everything saved on the device.
class AppData {
  AppData({
    List<Person>? people,
    this.meId,
    List<Trip>? trips,
    this.theme = ThemeChoice.system,
    this.anthemMuted = false,
    Map<String, String>? identities,
    Map<String, String>? waiting,
  })  : people = people ?? [],
        trips = trips ?? [],
        identities = identities ?? {},
        waiting = waiting ?? {};

  factory AppData.fromJson(Json json) => AppData(
        people: _list(json['people'], Person.fromJson),
        meId: json['meId'] as String?,
        trips: _list(json['trips'], Trip.fromJson),
        identities: (json['identities'] as Json? ?? const <String, dynamic>{})
            .cast<String, String>(),
        waiting: (json['waiting'] as Json? ?? const <String, dynamic>{})
            .cast<String, String>(),
        theme: ThemeChoice.values
            .byName(json['theme'] as String? ?? ThemeChoice.system.name),
        anthemMuted: json['anthemMuted'] as bool? ?? false,
      );

  List<Person> people;

  /// Who is using this phone.
  String? meId;
  List<Trip> trips;
  ThemeChoice theme;

  /// Stays on until the speaker is tapped again.
  bool anthemMuted;

  /// Trip id -> who this phone is on that trip, when someone joined as a name
  /// that was already on the list.
  Map<String, String> identities;

  /// Trip id -> place, for trips this phone has asked to enter.
  Map<String, String> waiting;

  Person? personById(String id) {
    for (final person in people) {
      if (person.id == id) return person;
    }
    return null;
  }

  Trip? tripById(String id) {
    for (final trip in trips) {
      if (trip.id == id) return trip;
    }
    return null;
  }

  Json toJson() => {
        'people': [for (final item in people) item.toJson()],
        'meId': meId,
        'trips': [for (final item in trips) item.toJson()],
        'theme': theme.name,
        'anthemMuted': anthemMuted,
        'identities': identities,
        'waiting': waiting,
      };
}
