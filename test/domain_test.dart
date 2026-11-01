import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:virulja/src/domain/trip_tree.dart';
import 'package:virulja/src/domain/tree.dart';
import 'package:virulja/src/domain/attack.dart';
import 'package:virulja/src/domain/budget.dart';
import 'package:virulja/src/domain/exif.dart';
import 'package:virulja/src/domain/format.dart';
import 'package:virulja/src/domain/links.dart';
import 'package:virulja/src/domain/models.dart';
import 'package:virulja/src/domain/offers.dart';
import 'package:virulja/src/domain/seal.dart';
import 'package:virulja/src/domain/settlement.dart';
import 'package:virulja/src/domain/wav.dart';

Trip visTrip() => Trip(
      id: 't1',
      country: 'Hrvatska',
      city: 'Vis',
      start: dayOf(2027, 6, 12),
      end: dayOf(2027, 6, 16),
      memberIds: ['ana', 'marko', 'iva'],
    );

Expense spent(int amount, String payer, List<String> sharers) => Expense(
      id: 'e$amount',
      title: 'Trošak',
      amount: amount,
      payerId: payer,
      sharedBy: sharers,
    );

void main() {
  group('trip days', () {
    test('counts nights and days', () {
      final trip = visTrip();
      expect(trip.nights, 4);
      expect(trip.dayCount, 5);
      expect(trip.dayAt(4), trip.end);
    });

    test('a clock change does not lose a day', () {
      final trip = visTrip()
        ..start = dayOf(2027, 3, 27)
        ..end = dayOf(2027, 3, 29);
      expect(trip.nights, 2);
    });

    test('knows the phase of the trip', () {
      final trip = visTrip();
      expect(trip.phaseOn(dayOf(2027, 6, 11)), TripPhase.upcoming);
      expect(trip.phaseOn(dayOf(2027, 6, 12)), TripPhase.active);
      expect(trip.phaseOn(dayOf(2027, 6, 16)), TripPhase.active);
      expect(trip.phaseOn(dayOf(2027, 6, 17)), TripPhase.past);
    });
  });

  group('saving', () {
    test('a full trip survives saving and loading', () {
      final trip = visTrip()
        ..offers.add(Offer(
          id: 'o1',
          name: 'Kuća Mare',
          pricePerNight: 18600,
          rating: 4.8,
          beachMeters: 300,
          source: 'Booking',
          votes: {'ana'},
        ))
        ..chosenOfferId = 'o1'
        ..places.add(Place(
          id: 'p1',
          kind: PlaceKind.winery,
          name: 'Vinarija',
          pricePerPerson: 1800,
          planned: true,
        ))
        ..dishes.add(Dish(id: 'd1', name: 'Peka', price: 2800, servings: 2))
        ..stops.add(Stop(id: 's1', dayIndex: 1, title: 'Izlet', cost: 5000))
        ..expenses.add(spent(9000, 'ana', ['ana', 'marko', 'iva']))
        ..payments.add(Payment(fromId: 'marko', toId: 'ana', amount: 3000))
        ..photos.add(Photo(
          id: 'f1',
          takenAt: DateTime.utc(2027, 6, 12, 20, 41),
          addedBy: 'ana',
          reactions: {'marko': {Reaction.cheers}},
          comments: [
            Comment(
              id: 'c1',
              authorId: 'marko',
              text: 'Lijepo',
              at: DateTime.utc(2027, 6, 13),
            ),
          ],
        ))
        ..songs.add(Song(
          id: 'n1',
          title: 'Pjesma',
          link: 'https://youtu.be/abc',
          addedBy: 'ana',
        ));
      final data = AppData(
        people: [Person(id: 'ana', name: 'Ana')],
        meId: 'ana',
        trips: [trip],
        theme: ThemeChoice.dark,
        anthemMuted: true,
      );

      final text = jsonEncode(data.toJson());
      final back = AppData.fromJson(jsonDecode(text) as Json);

      expect(jsonEncode(back.toJson()), text);
      final photo = back.trips.single.photos.single;
      expect(photo.reactions['marko'], {Reaction.cheers});
      expect(photo.comments.single.text, 'Lijepo');
      expect(back.trips.single.chosenOffer?.name, 'Kuća Mare');
      expect(back.theme, ThemeChoice.dark);
    });
  });

  group('budget', () {
    test('adds up every part of the plan', () {
      final trip = visTrip()
        ..offers.add(Offer(id: 'o', name: 'Kuća', pricePerNight: 10000))
        ..chosenOfferId = 'o'
        ..places.add(Place(
          id: 'p',
          kind: PlaceKind.restaurant,
          name: 'Konoba',
          pricePerPerson: 3000,
          planned: true,
        ))
        ..places.add(Place(
          id: 'q',
          kind: PlaceKind.cafe,
          name: 'Nije u planu',
          pricePerPerson: 500,
        ))
        ..dishes.add(Dish(id: 'd', name: 'Peka', price: 2800, servings: 3))
        ..stops.add(Stop(id: 's', dayIndex: 0, title: 'Izlet', cost: 6000))
        ..drive = Drive(tolls: 2000, ferry: 3000);

      final budget = Budget.of(trip);

      expect(budget.line(CostCategory.stay).planned, 40000);
      expect(budget.line(CostCategory.food).planned, 9000 + 8400);
      expect(budget.line(CostCategory.transport).planned, 5000);
      expect(budget.line(CostCategory.activities).planned, 6000);
      expect(budget.plannedTotal, 68400);
      expect(budget.plannedPerPerson, 22800);
    });

    test('with no offer chosen the stay costs nothing yet', () {
      expect(plannedCost(visTrip(), CostCategory.stay), 0);
    });

    test('sorts real spending into its category', () {
      final trip = visTrip()
        ..expenses.add(spent(4000, 'ana', ['ana'])..category = CostCategory.food)
        ..expenses.add(spent(1000, 'ana', ['ana'])..category = CostCategory.food);
      expect(Budget.of(trip).line(CostCategory.food).actual, 5000);
      expect(Budget.of(trip).actualTotal, 5000);
    });

    test('a trip with no group does not divide by zero', () {
      final trip = visTrip()..memberIds = [];
      expect(Budget.of(trip).plannedPerPerson, 0);
    });
  });

  group('drive', () {
    test('fuel counts both ways and every car', () {
      final drive = Drive(
        kilometres: 400,
        litresPer100: 7,
        fuelPrice: 150,
        cars: 2,
        tolls: 6800,
        ferry: 12800,
      );
      expect(drive.fuelCost, 16800);
      expect(drive.totalCost, 36400);
    });

    test('one way drives half as far', () {
      expect(
        Drive(kilometres: 100, roundTrip: false, litresPer100: 10, fuelPrice: 200)
            .fuelCost,
        2000,
      );
    });
  });

  group('settling up', () {
    test('split cents always add up', () {
      final parts = splitEqually(1000, ['a', 'b', 'c']);
      expect(parts, {'a': 334, 'b': 333, 'c': 333});
      expect(parts.values.reduce((a, b) => a + b), 1000);
    });

    test('balances add up to zero', () {
      final trip = visTrip()
        ..expenses.add(spent(10000, 'ana', ['ana', 'marko', 'iva']))
        ..expenses.add(spent(2999, 'marko', ['marko', 'iva']));
      final result = balances(trip);
      expect(result.values.reduce((a, b) => a + b), 0);
      expect(result['ana'], 6666);
    });

    test('one person paying leaves two payments to them', () {
      final trip = visTrip()..expenses.add(spent(9000, 'ana', ['ana', 'marko', 'iva']));
      final transfers = settle(balances(trip));
      expect(transfers.map((t) => '${t.fromId}>${t.toId}:${t.amount}'),
          ['marko>ana:3000', 'iva>ana:3000']);
    });

    test('a payment that was made is no longer owed', () {
      final trip = visTrip()
        ..expenses.add(spent(9000, 'ana', ['ana', 'marko', 'iva']))
        ..payments.add(Payment(fromId: 'marko', toId: 'ana', amount: 3000));
      final transfers = settle(balances(trip));
      expect(transfers.single.fromId, 'iva');
    });

    test('settling really clears every balance', () {
      final trip = visTrip()
        ..memberIds = ['a', 'b', 'c', 'd', 'e']
        ..expenses.add(spent(12345, 'a', ['a', 'b', 'c', 'd', 'e']))
        ..expenses.add(spent(777, 'b', ['b', 'c']))
        ..expenses.add(spent(5001, 'd', ['a', 'd', 'e']));
      final left = balances(trip);
      for (final transfer in settle(left)) {
        left[transfer.fromId] = left[transfer.fromId]! + transfer.amount;
        left[transfer.toId] = left[transfer.toId]! - transfer.amount;
      }
      expect(left.values, everyElement(0));
    });

    test('nothing spent means nothing to settle', () {
      expect(settle(balances(visTrip())), isEmpty);
    });
  });

  group('offers', () {
    final cheap = Offer(id: 'c', name: 'C', pricePerNight: 100, rating: 4.0, beachMeters: 900, votes: {'a'});
    final near = Offer(id: 'n', name: 'N', pricePerNight: 300, beachMeters: 50, votes: {'a', 'b'});
    final good = Offer(id: 'g', name: 'G', pricePerNight: 200, rating: 4.9);

    test('sorts by each parameter, unknown values last', () {
      final offers = [good, near, cheap];
      expect(sortOffers(offers, OfferSort.price).map((o) => o.id), ['c', 'g', 'n']);
      expect(sortOffers(offers, OfferSort.rating).map((o) => o.id), ['g', 'c', 'n']);
      expect(sortOffers(offers, OfferSort.beach).map((o) => o.id), ['n', 'c', 'g']);
      expect(sortOffers(offers, OfferSort.votes).map((o) => o.id), ['n', 'c', 'g']);
    });

    test('facts run from 0 to 1 and the best value gets 1', () {
      final offers = [cheap, near, good];
      expect(factsFor(cheap, offers, 2).price, 1);
      expect(factsFor(near, offers, 2).price, closeTo(1 / 3, 0.001));
      expect(factsFor(near, offers, 2).beach, 1);
      expect(factsFor(good, offers, 2).beach, 0);
      expect(factsFor(near, offers, 2).votes, 1);
      expect(factsFor(near, offers, 2).rating, 0);
    });
  });

  test('plan of attack puts what passed last and shows the winning vote', () {
    final trip = Trip(
      id: 't',
      country: 'Hrvatska',
      city: 'Vis',
      start: dayOf(2026, 7, 1),
      end: dayOf(2026, 7, 3),
      memberIds: [],
      stops: [
        Stop(id: 'a', dayIndex: 0, title: 'Kava', time: '08:00'),
        Stop(id: 'b', dayIndex: 0, title: 'Brod', time: '12:00'),
      ],
      polls: [
        Poll(id: 'p', title: 'Plaža', dayIndex: 0, active: true, options: [
          PollOption(id: 'o0', time: '10:00', votes: {'x'}),
          PollOption(id: 'o1', time: '11:00', votes: {'x', 'y'}),
        ]),
        Poll(id: 'q', title: 'Skriveno', options: [PollOption(id: 'o0', time: '09:00')]),
      ],
    );
    final items = planOfAttack(trip, DateTime(2026, 7, 1, 9));
    expect(items.map((item) => item.title), ['Plaža', 'Brod', 'Kava']);
    expect(items.first.time, '11:00');
    expect(items.map((item) => item.past), [false, false, true]);
  });

  group('places in the plan of attack', () {
    Trip trip() => Trip(
          id: 't',
          country: 'Hrvatska',
          city: 'Vis',
          start: dayOf(2026, 7, 1),
          end: dayOf(2026, 7, 4),
          memberIds: [],
          stops: [Stop(id: 's', dayIndex: 0, title: 'Skok', hiddenInAttack: true)],
          polls: [
            Poll(
              id: 'p',
              title: 'Konoba',
              active: true,
              single: true,
              options: [PollOption(id: 'o0', time: 'Da', votes: {'x'})],
              dayVotes: {
                2: {'x', 'y'},
                1: {'x'},
              },
            ),
          ],
        );

    test('a yes or no shows no result and takes the day with most votes', () {
      final item = planOfAttack(trip(), DateTime(2026, 7, 1, 9)).single;
      expect(item.detail, isNull);
      expect(item.dayIndex, 2);
      expect(item.past, isFalse);
    });

    test('equal votes take the earliest day, no votes the poll own day', () {
      final even = trip()..polls.single.dayVotes[1]!.add('y');
      expect(even.polls.single.plannedDay, 1);
      final none = trip()..polls.single.dayVotes.clear();
      expect(none.polls.single.plannedDay, 0);
    });

    test('it goes grey only once its day has gone by', () {
      expect(planOfAttack(trip(), DateTime(2026, 7, 3, 23)).single.past, isFalse);
      expect(planOfAttack(trip(), DateTime(2026, 7, 4, 0, 5)).single.past, isTrue);
    });

    test('a hidden stop stays out, and only days left can be chosen', () {
      expect(planOfAttack(trip(), DateTime(2026, 7, 1)).any((i) => i.stop != null), isFalse);
      expect(remainingDays(trip(), DateTime(2026, 7, 3, 12)), [2, 3]);
    });

    test('day votes survive the cloud with their days', () {
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(trip(), (id) => id)))));
      final back = tripFromTree('t', (tree as Map).cast<String, dynamic>())!.trip;
      expect(back.polls.single.dayVotes, {
        1: {'x'},
        2: {'x', 'y'},
      });
      expect(back.stops.single.hiddenInAttack, isTrue);
    });
  });

  group('links', () {
    test('Booking search carries the place, dates and group', () {
      final uri = bookingSearch(visTrip());
      expect(uri.queryParameters['ss'], 'Vis, Hrvatska');
      expect(uri.queryParameters['checkin'], '2027-06-12');
      expect(uri.queryParameters['checkout'], '2027-06-16');
      expect(uri.queryParameters['group_adults'], '3');
    });

    test('Airbnb search handles a place with spaces', () {
      final trip = visTrip()..city = 'Stari Grad';
      expect(airbnbSearch(trip).path, '/s/Stari-Grad--Hrvatska/homes');
    });

    test('Maps search looks for the right kind of place', () {
      expect(mapsSearch(PlaceKind.winery, visTrip()).queryParameters['query'],
          'vinarija Vis Hrvatska');
    });

    test('Spotify links open the Spotify player', () {
      final player = playerFor('https://open.spotify.com/intl-hr/track/ABC?si=x')!;
      expect(player.service, 'Spotify');
      expect(player.address, 'https://open.spotify.com/embed/track/ABC');
    });

    test('every form of a YouTube link works', () {
      for (final link in [
        'https://youtu.be/ABC?t=3',
        'https://www.youtube.com/watch?v=ABC',
        'https://m.youtube.com/watch?v=ABC&list=1',
        'https://music.youtube.com/watch?v=ABC',
        'https://www.youtube.com/shorts/ABC',
      ]) {
        expect(playerFor(link)?.address, 'https://www.youtube.com/embed/ABC', reason: link);
      }
    });

    test('Apple Music keeps the chosen song', () {
      expect(
        playerFor('https://music.apple.com/hr/album/pjesma/123?i=456')?.address,
        'https://embed.music.apple.com/hr/album/pjesma/123?i=456',
      );
    });

    test('a name is read from Google Maps and Booking links', () {
      expect(
        nameFromLink('https://www.google.com/maps/place/Konoba+Stara+Uvala/@43.5,16.4,17z'),
        'Konoba Stara Uvala',
      );
      expect(
        nameFromLink('https://www.booking.com/hotel/hr/vila-mare.hr.html?aid=1'),
        'Vila Mare',
      );
      expect(nameFromLink('https://maps.app.goo.gl/abc'), isNull);
      expect(nameFromLink('https://www.airbnb.com/rooms/123'), isNull);
    });

    test('a queue holds only the YouTube songs, in order', () {
      expect(
        youTubeQueue([
          'https://youtu.be/aaa',
          'https://open.spotify.com/track/x',
          'https://www.youtube.com/watch?v=bbb',
        ]),
        'https://www.youtube.com/embed/aaa?playlist=bbb&playsinline=1',
      );
      expect(youTubeQueue(['https://open.spotify.com/track/x']), isNull);
    });

    test('a YouTube playlist link is recognised', () {
      expect(isYouTubePlaylist('https://www.youtube.com/playlist?list=PL1'), isTrue);
      expect(isYouTubePlaylist('https://youtu.be/aaa'), isFalse);
    });

    test('other links are refused', () {
      expect(playerFor('https://example.com/song'), isNull);
      expect(playerFor('nije link'), isNull);
      expect(playerFor('https://open.spotify.com/user/ana'), isNull);
    });
  });

  group('Croatian text', () {
    test('date ranges', () {
      expect(dateRange(dayOf(2027, 6, 12), dayOf(2027, 6, 16)), '12.–16. lipnja');
      expect(dateRange(dayOf(2027, 6, 28), dayOf(2027, 7, 3)), '28. lipnja – 3. srpnja');
      expect(dateRange(dayOf(2027, 6, 12), dayOf(2027, 6, 12)), '12. lipnja');
      expect(dateRange(dayOf(2026, 12, 30), dayOf(2027, 1, 2)),
          '30. prosinca 2026. – 2. siječnja 2027.');
    });

    test('weekdays', () {
      expect(weekdayAndDate(dayOf(2027, 6, 12)), 'subota, 12. lipnja');
    });

    test('counts take the right word', () {
      expect(photosCount(1), '1 fotografija');
      expect(photosCount(2), '2 fotografije');
      expect(photosCount(5), '5 fotografija');
      expect(photosCount(12), '12 fotografija');
      expect(photosCount(22), '22 fotografije');
      expect(photosCount(101), '101 fotografija');
      expect(peopleCount(6), '6 osoba');
      expect(peopleCount(3), '3 osobe');
      expect(songsCount(8), '8 pjesama');
      expect(nightsCount(4), '4 noći');
      expect(nightsCount(1), '1 noć');
    });

    test('days until a trip', () {
      final day = dayOf(2026, 10, 31);
      expect(daysUntil(day, dayOf(2027, 6, 12)), 'za 224 dana');
      expect(daysUntil(day, dayOf(2026, 11, 21)), 'za 21 dan');
      expect(daysUntil(day, dayOf(2026, 11, 11)), 'za 11 dana');
      expect(daysUntil(day, dayOf(2026, 11, 1)), 'sutra');
      expect(daysUntil(day, day), 'danas');
    });

    test('how long ago', () {
      final now = DateTime.utc(2027, 6, 13, 12);
      expect(ago(now.subtract(const Duration(seconds: 20)), now), 'upravo');
      expect(ago(now.subtract(const Duration(minutes: 5)), now), 'prije 5 min');
      expect(ago(now.subtract(const Duration(hours: 3)), now), 'prije 3 h');
      expect(ago(now.subtract(const Duration(hours: 30)), now), 'jučer');
      expect(ago(now.subtract(const Duration(days: 4)), now), 'prije 4 dana');
    });

    test('euros', () {
      expect(euros(242000), '2.420 €');
      expect(euros(1250), '12,50 €');
      expect(euros(5), '0,05 €');
      expect(euros(-800), '−8 €');
      expect(euros(123456700), '1.234.567 €');
    });

    test('amounts as people type them', () {
      expect(parseEuros('12'), 1200);
      expect(parseEuros('12,5'), 1250);
      expect(parseEuros('12.50'), 1250);
      expect(parseEuros('1.200'), 120000);
      expect(parseEuros('1.200,50'), 120050);
      expect(parseEuros(' 8 € '), 800);
      expect(parseEuros(''), isNull);
      expect(parseEuros('puno'), isNull);
      expect(parseEuros('-5'), isNull);
    });
  });

  group('the seal on a postcard', () {
    test('keeps a short place on one line', () {
      expect(sealLines('Vis'), ['Vis']);
      expect(sealLines('Novi Sad'), ['Novi Sad']);
      expect(sealLines('Aberystwyth'), ['Aberystwyth']);
    });

    test('breaks a long place where the longer line is shortest', () {
      expect(sealLines('Rio de Janeiro'), ['Rio de', 'Janeiro']);
      expect(sealLines('Sveti Filip i Jakov'), ['Sveti Filip', 'i Jakov']);
    });

    test('reads the corner of a photo as the postcard cuts it', () {
      final wide = sealCorner(2000, 1000);
      expect(wide.x, closeTo(375 + .66 * 1250, .001));
      expect(wide.y, closeTo(.03 * 1000, .001));
      expect(wide.width, closeTo(.32 * 1250, .001));
      expect(wide.height, closeTo(.39 * 1000, .001));

      final tall = sealCorner(1000, 2000);
      expect(tall.x, closeTo(.66 * 1000, .001));
      expect(tall.y, closeTo(600 + .03 * 800, .001));
    });

    test('takes dark ink only on a bright corner', () {
      List<int> pixels(int red, int green, int blue) => [
            for (var i = 0; i < 4; i++) ...[red, green, blue, 255],
          ];

      expect(isBright(pixels(234, 244, 251)), isTrue, reason: 'a pale sky');
      expect(isBright(pixels(246, 241, 228)), isTrue, reason: 'a white wall');
      expect(isBright(pixels(47, 143, 179)), isFalse, reason: 'the sea');
      expect(isBright(pixels(16, 26, 38)), isFalse, reason: 'the night');
    });
  });

  group('photo facts', () {
    test('reads the date and position of a JPEG', () {
      final info = readExif(sampleJpeg(littleEndian: true));
      expect(info.takenAt, DateTime.utc(2027, 6, 12, 20, 41, 5));
      expect(info.latitude, closeTo(43.0607, 0.0001));
      expect(info.longitude, closeTo(16.1833, 0.0001));
    });

    test('reads files written the other way round', () {
      final info = readExif(sampleJpeg(littleEndian: false));
      expect(info.takenAt, DateTime.utc(2027, 6, 12, 20, 41, 5));
    });

    test('a broken or plain file gives no facts and no crash', () {
      expect(readExif(Uint8List(0)).takenAt, isNull);
      expect(readExif(Uint8List.fromList([1, 2, 3, 4, 5])).takenAt, isNull);
      final cut = sampleJpeg(littleEndian: true).sublist(0, 40);
      expect(readExif(cut).takenAt, isNull);
    });
  });

  group('anthem sound', () {
    test('writes a valid short mono file', () {
      final wav = encodeWav(List.filled(22050, 0.5), 22050,
          fade: const Duration(milliseconds: 100));
      final data = ByteData.sublistView(wav);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(data.getUint16(22, Endian.little), 1);
      expect(data.getUint32(24, Endian.little), 22050);
      expect(wav.length, 44 + 44100);
    });

    test('fades out to silence at the end', () {
      final wav = encodeWav(List.filled(1000, 1.0), 1000,
          fade: const Duration(milliseconds: 500));
      final data = ByteData.sublistView(wav);
      expect(data.getInt16(44 + 100 * 2, Endian.little), 32767);
      expect(data.getInt16(44 + 750 * 2, Endian.little), closeTo(16384, 2));
      expect(data.getInt16(44 + 999 * 2, Endian.little).abs(), lessThan(100));
    });

    test('loud peaks never wrap around', () {
      final wav = encodeWav([2.0, -2.0], 1000, fade: Duration.zero);
      final data = ByteData.sublistView(wav);
      expect(data.getInt16(44, Endian.little), 32767);
      expect(data.getInt16(46, Endian.little), -32767);
    });
  });
}

/// A tiny JPEG header with an Exif block: date, and Vis as the position.
Uint8List sampleJpeg({required bool littleEndian}) {
  final endian = littleEndian ? Endian.little : Endian.big;
  final tiff = ByteData(200);
  tiff.setUint16(0, littleEndian ? 0x4949 : 0x4D4D);
  tiff.setUint16(2, 42, endian);
  tiff.setUint32(4, 8, endian); // the main block starts at 8

  void entry(int at, int tag, int type, int count, int value) {
    tiff.setUint16(at, tag, endian);
    tiff.setUint16(at + 2, type, endian);
    tiff.setUint32(at + 4, count, endian);
    tiff.setUint32(at + 8, value, endian);
  }

  // Main block: where the Exif and GPS blocks are.
  tiff.setUint16(8, 2, endian);
  entry(10, 0x8769, 4, 1, 40);
  entry(22, 0x8825, 4, 1, 60);
  // Exif block: the date.
  tiff.setUint16(40, 1, endian);
  entry(42, 0x9003, 2, 20, 130);
  // GPS block: north and east, written inline when short.
  tiff.setUint16(60, 4, endian);
  entry(62, 1, 2, 2, 0);
  tiff.setUint8(70, 'N'.codeUnitAt(0));
  entry(74, 2, 5, 3, 152);
  entry(86, 3, 2, 2, 0);
  tiff.setUint8(94, 'E'.codeUnitAt(0));
  entry(98, 4, 5, 3, 176);

  const date = '2027:06:12 20:41:05';
  for (var i = 0; i < date.length; i++) {
    tiff.setUint8(130 + i, date.codeUnitAt(i));
  }
  void rational(int at, int top, int bottom) {
    tiff.setUint32(at, top, endian);
    tiff.setUint32(at + 4, bottom, endian);
  }

  rational(152, 43, 1);
  rational(160, 3, 1);
  rational(168, 3852, 100);
  rational(176, 16, 1);
  rational(184, 10, 1);
  rational(192, 5988, 100);

  final tiffBytes = tiff.buffer.asUint8List();
  final length = tiffBytes.length + 8;
  return Uint8List.fromList([
    0xFF, 0xD8, // start of the file
    0xFF, 0xE1, length >> 8, length & 0xFF, // the Exif segment
    0x45, 0x78, 0x69, 0x66, 0, 0, // "Exif"
    ...tiffBytes,
    0xFF, 0xDA, // the picture itself
  ]);
}
