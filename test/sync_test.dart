import 'dart:convert';

import 'package:test/test.dart';
import 'package:virulja/src/domain/models.dart';
import 'package:virulja/src/domain/session.dart';
import 'package:virulja/src/domain/tree.dart';
import 'package:virulja/src/domain/trip_tree.dart';

Trip visTrip() => Trip(
      id: 't1',
      country: 'Hrvatska',
      city: 'Vis',
      start: dayOf(2027, 6, 12),
      end: dayOf(2027, 6, 16),
      memberIds: ['ana', 'marko'],
    );

String nameOf(String id) => {'ana': 'Ana', 'marko': 'Marko'}[id] ?? 'Netko';

Flat flatOf(Trip trip) => flatten(tripToTree(trip, nameOf));

/// A stand-in for the database, as the phones see it over the web.
class FakeCloud {
  Flat data = {};

  void send(Map<String, Object?> changes) {
    data = applyChanges(data, changes);
  }
}

/// One phone: its trip, and what it last saw of the cloud.
class Phone {
  Phone(this.trip) : mirror = TripMirror();

  Trip trip;
  final TripMirror mirror;

  void push(FakeCloud cloud) {
    final pending = mirror.pending(flatOf(trip));
    cloud.send(pending);
    mirror.confirm(pending);
  }

  void pull(FakeCloud cloud) {
    final merged = mirror.receive(flatOf(trip), 'put', '/', unflatten(cloud.data));
    trip.copyFrom(tripFromTree(trip.id, unflatten(merged))!.trip);
  }
}

class FakeHttp implements JsonHttp {
  final List<String> calls = [];
  final List<HttpReply> replies = [];

  @override
  Future<HttpReply> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
  }) async {
    calls.add('$method ${url.path}');
    return replies.removeAt(0);
  }
}

class FakeStore implements KeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> readValue(String key) async => values[key];

  @override
  Future<void> writeValue(String key, String value) async => values[key] = value;
}

void main() {
  group('flat trees', () {
    test('flatten and unflatten are opposites', () {
      final tree = {
        'city': 'Vis',
        'offers': {
          'a': {'name': 'Kuća', 'price': 100, 'votes': {'ana': true}},
        },
      };
      expect(flatten(tree), {
        'city': 'Vis',
        'offers/a/name': 'Kuća',
        'offers/a/price': 100,
        'offers/a/votes/ana': true,
      });
      expect(unflatten(flatten(tree)), tree);
    });

    test('nulls and empty maps are simply not there', () {
      expect(flatten({'a': null, 'b': {}, 'c': {'d': null}}), isEmpty);
    });

    test('changes name what is new and what is gone', () {
      final changes = changesBetween({'a': 1, 'b': 2}, {'b': 3, 'c': 4});
      expect(changes, {'a': null, 'b': 3, 'c': 4});
      expect(applyChanges({'a': 1, 'b': 2}, changes), {'b': 3, 'c': 4});
    });

    test('whole numbers match however they are written', () {
      expect(changesBetween({'a': 7}, {'a': 7.0}), isEmpty);
    });
  });

  group('live events', () {
    final flat = <String, Object>{'city': 'Vis', 'offers/a/name': 'Kuća', 'offers/a/price': 1};

    test('put at the top replaces everything', () {
      expect(applyServerEvent(flat, 'put', '/', {'city': 'Hvar'}), {'city': 'Hvar'});
    });

    test('put null at the top empties it', () {
      expect(applyServerEvent(flat, 'put', '/', null), isEmpty);
    });

    test('put on a branch replaces only that branch', () {
      expect(applyServerEvent(flat, 'put', '/offers/a', {'name': 'Vila'}),
          {'city': 'Vis', 'offers/a/name': 'Vila'});
    });

    test('put on a value changes that value', () {
      expect(applyServerEvent(flat, 'put', '/offers/a/price', 2)['offers/a/price'], 2);
    });

    test('put null on a branch removes it', () {
      expect(applyServerEvent(flat, 'put', '/offers/a', null), {'city': 'Vis'});
    });

    test('a similar name is left alone', () {
      final result = applyServerEvent({'offers/a': 1, 'offers/ab': 2}, 'put', '/offers/a', null);
      expect(result, {'offers/ab': 2});
    });

    test('patch changes each child it names', () {
      expect(applyServerEvent(flat, 'patch', '/offers/a', {'price': 5, 'name': null}),
          {'city': 'Vis', 'offers/a/price': 5});
    });

    test('patch from a change in many places', () {
      final result = applyServerEvent(flat, 'patch', '/', {'offers/a/price': 9, 'city': 'Hvar'});
      expect(result['offers/a/price'], 9);
      expect(result['city'], 'Hvar');
      expect(result['offers/a/name'], 'Kuća');
    });
  });

  group('a trip in the cloud', () {
    test('a full trip survives the trip there and back', () {
      final trip = visTrip()
        ..coverId = 'f1'
        ..offers.add(Offer(id: 'o1', name: 'Kuća', pricePerNight: 18600, rating: 4.8, votes: {'ana', 'marko'}))
        ..chosenOfferId = 'o1'
        ..places.add(Place(id: 'p1', kind: PlaceKind.winery, name: 'Vinarija', planned: true))
        ..dishes.add(Dish(id: 'd1', name: 'Peka', price: 2800))
        ..stops.add(Stop(id: 's1', dayIndex: 1, title: 'Izlet', time: '09:30', cost: 5000))
        ..drive = Drive(kilometres: 410, cars: 2)
        ..expenses.add(Expense(id: 'e1', title: 'Večera', amount: 9000, payerId: 'ana', sharedBy: ['ana', 'marko']))
        ..payments.add(Payment(fromId: 'marko', toId: 'ana', amount: 4500))
        ..photos.add(Photo(
          id: 'f1',
          takenAt: DateTime.utc(2027, 6, 12, 20, 41),
          addedBy: 'ana',
          stored: true,
          reactions: {'marko': {Reaction.heart, Reaction.sun}},
          comments: [
            Comment(id: 'c2', authorId: 'ana', text: 'Drugi', at: DateTime.utc(2027, 6, 13, 2)),
            Comment(id: 'c1', authorId: 'marko', text: 'Prvi', at: DateTime.utc(2027, 6, 13, 1)),
          ],
        ))
        ..songs.add(Song(id: 'n1', title: 'Pjesma', link: 'https://youtu.be/a', addedBy: 'ana'));

      // Through text, as the database hands it back.
      final json = jsonDecode(jsonEncode(unflatten(flatOf(trip)))) as Tree;
      final cloud = tripFromTree('t1', json)!;

      expect(cloud.names, {'ana': 'Ana', 'marko': 'Marko'});
      final back = cloud.trip;
      expect(back.memberIds, ['ana', 'marko']);
      expect(back.offers.single.votes, {'ana', 'marko'});
      expect(back.chosenOffer?.name, 'Kuća');
      expect(back.places.single.kind, PlaceKind.winery);
      expect(back.drive.cars, 2);
      expect(back.polls.every((poll) => !poll.single), isTrue);
      expect(back.expenses.single.sharedBy, ['ana', 'marko']);
      expect(back.payments.single.amount, 4500);
      expect(back.photos.single.reactions['marko'], {Reaction.heart, Reaction.sun});
      expect(back.photos.single.comments.map((c) => c.text), ['Prvi', 'Drugi']);
      expect(back.photos.single.stored, isTrue);
      expect(flatOf(back), flatOf(trip));
    });

    test('a trip that is not whole is refused, not a crash', () {
      expect(tripFromTree('t1', {'city': 'Vis'}), isNull);
      expect(tripFromTree('t1', {}), isNull);
    });

    test('an item that is not whole is skipped', () {
      final flat = flatOf(visTrip());
      flat['offers/o1/name'] = 'Bez cijene';
      expect(tripFromTree('t1', unflatten(flat))!.trip.offers, isEmpty);
    });

    test('lists every picture and sound', () {
      final trip = visTrip()
        ..coverId = 'c'
        ..anthemClipId = 'h'
        ..photos.add(Photo(id: 'f', takenAt: DateTime.utc(2027), addedBy: 'ana'));
      expect(blobIds(trip), ['f', 'f.t', 'c', 'c.t', 'h']);
    });
  });

  group('two phones', () {
    late FakeCloud cloud;
    late Phone ana, marko;

    setUp(() {
      cloud = FakeCloud();
      ana = Phone(visTrip())..push(cloud);
      marko = Phone(visTrip())..pull(cloud);
    });

    test('what one adds, the other sees', () {
      ana.trip.offers.add(Offer(id: 'o1', name: 'Kuća', pricePerNight: 100));
      ana.push(cloud);
      marko.pull(cloud);
      expect(marko.trip.offers.single.name, 'Kuća');
    });

    test('changes at the same moment both stay', () {
      ana.trip.offers.add(Offer(id: 'o1', name: 'Kuća', pricePerNight: 100));
      marko.trip.songs.add(Song(id: 'n1', title: 'Pjesma', link: 'x', addedBy: 'marko'));
      ana.push(cloud);
      marko.push(cloud);
      ana.pull(cloud);
      marko.pull(cloud);
      expect(ana.trip.songs, hasLength(1));
      expect(marko.trip.offers, hasLength(1));
    });

    test('two votes on one offer both count', () {
      ana.trip.offers.add(Offer(id: 'o1', name: 'Kuća', pricePerNight: 100));
      ana.push(cloud);
      marko.pull(cloud);
      ana.trip.offers.single.votes.add('ana');
      marko.trip.offers.single.votes.add('marko');
      ana.push(cloud);
      marko.push(cloud);
      ana.pull(cloud);
      expect(ana.trip.offers.single.votes, {'ana', 'marko'});
    });

    test('two comments and reactions on one photo all stay', () {
      ana.trip.photos.add(Photo(id: 'f', takenAt: DateTime.utc(2027), addedBy: 'ana'));
      ana.push(cloud);
      marko.pull(cloud);
      ana.trip.photos.single
        ..reactions['ana'] = {Reaction.heart}
        ..comments.add(Comment(id: 'c1', authorId: 'ana', text: 'A', at: DateTime.utc(2027, 1, 2)));
      marko.trip.photos.single
        ..reactions['marko'] = {Reaction.sun}
        ..comments.add(Comment(id: 'c2', authorId: 'marko', text: 'M', replyTo: 'c1', at: DateTime.utc(2027, 1, 3), reactions: {'ana': {Reaction.star}}));
      ana.push(cloud);
      marko.push(cloud);
      ana.pull(cloud);
      final photo = ana.trip.photos.single;
      expect(photo.reactions, {'ana': {Reaction.heart}, 'marko': {Reaction.sun}});
      expect(photo.comments.last.replyTo, 'c1');
      expect(photo.comments.last.reactions['ana'], {Reaction.star});
      expect(photo.comments.map((c) => c.text), ['A', 'M']);
    });

    test('changes made with no connection wait and arrive later', () {
      marko.trip.offers.add(Offer(id: 'o2', name: 'Vila', pricePerNight: 200));
      ana.trip.expenses.add(Expense(id: 'e1', title: 'Trajekt', amount: 100, payerId: 'ana', sharedBy: ['ana']));
      ana.push(cloud);
      // Marko has been offline: news arrives, his own change stays.
      marko.pull(cloud);
      expect(marko.trip.offers, hasLength(1));
      expect(marko.trip.expenses, hasLength(1));
      marko.push(cloud);
      ana.pull(cloud);
      expect(ana.trip.offers.single.name, 'Vila');
    });

    test('something removed disappears everywhere', () {
      ana.trip.offers.add(Offer(id: 'o1', name: 'Kuća', pricePerNight: 100));
      ana.push(cloud);
      marko.pull(cloud);
      marko.trip.offers.clear();
      marko.push(cloud);
      ana.pull(cloud);
      expect(ana.trip.offers, isEmpty);
    });

    test('after a sync nothing is left to send', () {
      ana.trip.offers.add(Offer(id: 'o1', name: 'Kuća', pricePerNight: 100, rating: 4.0));
      ana.trip.drive = Drive(litresPer100: 7);
      ana.push(cloud);
      marko.pull(cloud);
      expect(marko.mirror.pending(flatOf(marko.trip)), isEmpty);
      expect(ana.mirror.pending(flatOf(ana.trip)), isEmpty);
    });

    test('the mirror survives saving and loading', () {
      ana.mirror.uploaded.add('f');
      final json = jsonDecode(jsonEncode(ana.mirror.toJson())) as Tree;
      final back = TripMirror.fromJson(json);
      expect(back.server, ana.mirror.server);
      expect(back.uploaded, {'f'});
    });
  });

  group('sign-in', () {
    const config = OnlineConfig(databaseUrl: 'https://db', apiKey: 'k');
    HttpReply signUp([String token = 'tok']) => HttpReply(200, jsonEncode({
          'localId': 'u1',
          'idToken': token,
          'refreshToken': 'r1',
          'expiresIn': '3600',
        }));

    test('reads the settings file', () {
      expect(OnlineConfig.tryParse('{"databaseUrl":"https://db/","apiKey":"k"}')?.databaseUrl, 'https://db');
      expect(OnlineConfig.tryParse('{"databaseUrl":"","apiKey":""}'), isNull);
      expect(OnlineConfig.tryParse('{"databaseUrl":"http://db","apiKey":"k"}'), isNull);
      expect(OnlineConfig.tryParse('nije json'), isNull);
    });

    test('signs in once and keeps the token', () async {
      final http = FakeHttp()..replies.add(signUp());
      final session = FirebaseSession(config, http, FakeStore());
      expect(await session.token(), 'tok');
      expect(await session.token(), 'tok');
      expect(http.calls, hasLength(1));
    });

    test('requests at the same moment sign in only once', () async {
      final http = FakeHttp()..replies.add(signUp());
      final session = FirebaseSession(config, http, FakeStore());
      final tokens = await Future.wait([session.token(), session.token(), session.token()]);
      expect(tokens, ['tok', 'tok', 'tok']);
      expect(http.calls, hasLength(1));
    });

    test('renews a token that has run out, as the same person', () async {
      var now = DateTime.utc(2027);
      final store = FakeStore();
      final http = FakeHttp()
        ..replies.add(signUp())
        ..replies.add(HttpReply(200, jsonEncode({
          'user_id': 'u1',
          'id_token': 'novi',
          'refresh_token': 'r2',
          'expires_in': '3600',
        })));
      final session = FirebaseSession(config, http, store, now: () => now);
      await session.token();
      now = now.add(const Duration(hours: 2));
      expect(await session.token(), 'novi');
      expect(http.calls.last, contains('/v1/token'));
    });

    test('a saved sign-in works after the app is reopened', () async {
      final store = FakeStore();
      final first = FakeHttp()..replies.add(signUp());
      await FirebaseSession(config, first, store).token();
      final second = FakeHttp()
        ..replies.add(HttpReply(200, jsonEncode({
          'user_id': 'u1',
          'id_token': 'opet',
          'refresh_token': 'r1',
          'expires_in': '3600',
        })));
      expect(await FirebaseSession(config, second, store).token(), 'opet');
    });

    test('a failed connection is an error, not a new person', () async {
      final store = FakeStore();
      final first = FakeHttp()..replies.add(signUp());
      await FirebaseSession(config, first, store).token();
      final second = FakeHttp()..replies.add(const HttpReply(500, ''));
      expect(FirebaseSession(config, second, store).token(), throwsA(isA<OnlineException>()));
    });

    test('a deleted sign-in makes a new one', () async {
      final store = FakeStore();
      final first = FakeHttp()..replies.add(signUp());
      await FirebaseSession(config, first, store).token();
      final second = FakeHttp()
        ..replies.add(const HttpReply(400, ''))
        ..replies.add(signUp('nova'));
      expect(await FirebaseSession(config, second, store).token(), 'nova');
    });
  });
}
