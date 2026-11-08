import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:virulja/src/domain/trip_tree.dart';
import 'package:virulja/src/domain/tree.dart';
import 'package:virulja/src/domain/attack.dart';
import 'package:virulja/src/domain/budget.dart';
import 'package:virulja/src/domain/currency.dart';
import 'package:virulja/src/domain/exif.dart';
import 'package:virulja/src/domain/format.dart';
import 'package:virulja/src/domain/links.dart';
import 'package:virulja/src/domain/models.dart';
import 'package:virulja/src/domain/offers.dart';
import 'package:virulja/src/domain/seal.dart';
import 'package:virulja/src/domain/settlement.dart';
import 'package:virulja/src/domain/show.dart';
import 'package:virulja/src/domain/trip_currency.dart';
import 'package:virulja/src/domain/trip_events.dart';
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

  group('a price range', () {
    Place place() => Place(
          id: 'p',
          kind: PlaceKind.restaurant,
          name: 'Konoba',
          pricePerPerson: 2000,
          priceLow: 1000,
          priceHigh: 3000,
          planned: true,
        );

    test('survives saving', () {
      final back = Place.fromJson(jsonDecode(jsonEncode(place().toJson())) as Json);
      expect(back.pricePerPerson, 2000);
      expect(back.priceLow, 1000);
      expect(back.priceHigh, 3000);
    });

    test('counts as its middle in the estimate', () {
      final trip = visTrip()..places.add(place());
      expect(plannedCost(trip, CostCategory.food), 2000 * trip.people);
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

      expect(budget.line(CostCategory.stay).estimate, 40000);
      expect(budget.line(CostCategory.food).estimate, 9000 + 8400);
      expect(budget.line(CostCategory.transport).estimate, 5000);
      expect(budget.line(CostCategory.activities).estimate, 6000);
      // Nothing is planned until the group plans it.
      expect(budget.plannedTotal, 0);
      expect(budget.plannedPerPerson, 0);
    });

    test('a category counts only its own planned places', () {
      Place place(PlaceKind kind, int price, {bool planned = true}) => Place(
            id: '$kind$price',
            kind: kind,
            name: 'Mjesto',
            pricePerPerson: price,
            planned: planned,
          );
      final trip = visTrip()
        ..places.add(place(PlaceKind.beachBar, 2000))
        ..places.add(place(PlaceKind.beachBar, 1000))
        ..places.add(place(PlaceKind.beachBar, 5000, planned: false))
        ..places.add(place(PlaceKind.cafe, 700))
        ..dishes.add(Dish(id: 'd', name: 'Peka', price: 2800, servings: 2));

      final bars = trip.places.where((place) => place.kind == PlaceKind.beachBar);
      expect(plannedPlacesCost(trip, bars), 3000 * trip.people);
      expect(dishesCost(trip), 5600);
      expect(plannedCost(trip, CostCategory.food), 3700 * trip.people + 5600);
    });

    test('your cost counts only what concerns you', () {
      final trip = visTrip()
        ..expenses.add(Expense(
          id: 'x',
          title: 'Vila',
          amount: 30000,
          payerId: 'ana',
          sharedBy: ['ana', 'marko'],
          category: CostCategory.stay,
        ));
      expect(Budget.shareOf(trip, 'ana') - Budget.shareOf(trip, 'iva'), 15000);
    });

    test('a reserved part of the journey is in Plan napada on its voted day', () {
      final trip = visTrip()
        ..legs.add(Leg(id: 'l', title: 'Trajekt', cost: 4000, dayVotes: {
          1: {'ana', 'marko'},
        }));
      expect(planOfAttack(trip, DateTime(2027, 6, 1)).where((i) => i.leg != null), isEmpty);
      trip.legs.single.reserved = true;
      final item = planOfAttack(trip, DateTime(2027, 6, 1)).singleWhere((i) => i.leg != null);
      expect(item.days, [1]);
      expect(item.category, CostCategory.transport);
      final back = Leg.fromJson(jsonDecode(jsonEncode(trip.legs.single.toJson())) as Json);
      expect(back.reserved, isTrue);
      expect(back.dayVotes[1], {'ana', 'marko'});
    });

    test('a thing added to or taken off a shopping list is news', () {
      final trip = visTrip()
        ..uids.addAll({'ana': 'ua', 'marko': 'um'})
        ..shopLists.add(ShopList(id: 'l1', name: 'Konzum', items: [
          ShopItem(id: 'i1', text: 'Kruh', addedBy: 'ana'),
        ], removed: {
          'i2': (text: 'Voda', by: 'ana'),
        }));
      final events = tripEvents(trip, {'ana': 'Ana', 'marko': 'Marko'}).where((e) => e.notice == Notice.shop);
      expect(events.map((e) => e.text), ['Ana dodaje na listu Konzum: Kruh', 'Ana miče s liste Konzum: Voda']);
      Iterable<String> shopNews(String uid, Set<Object?> told) => newsFor(uid, 't1', trip, {'ana': 'Ana'}, told, const {})
          .map((news) => news.body)
          .where((body) => body.contains('Konzum'));
      expect(shopNews('um', {newsVersion}), hasLength(2));
      expect(shopNews('ua', {newsVersion}), isEmpty);
      expect(shopNews('um', {'#2'}), isEmpty);
      final back = ShopList.fromJson(jsonDecode(jsonEncode(trip.shopLists.single.toJson())) as Json);
      expect(back.removed['i2']?.text, 'Voda');
    });

    test('a shopping list goes to the cloud and back, and its cost counts under Dućan', () {
      final trip = visTrip()
        ..shopLists.add(ShopList(id: 'l1', name: 'Konzum', items: [
          ShopItem(id: 'i1', text: 'Kruh'),
          ShopItem(id: 'i2', text: 'Voda', done: true),
        ], expenseId: 'e1'))
        ..expenses.add(Expense(
          id: 'e1',
          title: 'Konzum',
          amount: 2300,
          payerId: 'ana',
          sharedBy: ['ana', 'marko', 'iva'],
          category: CostCategory.shop,
        ));
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(trip, (id) => id)))));
      for (final back in [
        tripFromTree('t1', (tree as Map).cast<String, dynamic>())!.trip,
        Trip.fromJson(jsonDecode(jsonEncode(trip.toJson())) as Json),
      ]) {
        final list = back.shopLists.single;
        expect(list.name, 'Konzum');
        expect(list.items.map((item) => '${item.text} ${item.done}'), ['Kruh false', 'Voda true']);
        expect(list.expenseId, 'e1');
      }
      expect(Budget.of(trip).line(CostCategory.shop).actual, 2300);
      expect(Budget.of(trip).line(CostCategory.shop).estimate, 2300);
    });

    test('a place whose day has come waits to be split, until its cost is written', () {
      final trip = visTrip()
        ..places.add(Place(id: 'k', kind: PlaceKind.restaurant, name: 'Konoba', pricePerPerson: 2000, planned: true, dayVotes: {
          1: {'ana', 'marko'},
        }));
      expect(toSplit(trip, DateTime(2027, 6, 12, 12)), isEmpty);
      expect(toSplit(trip, DateTime(2027, 6, 13, 12)).map((place) => place.name), ['Konoba']);
      trip.expenses.add(Expense(id: 'e', title: 'Konoba', amount: 5500, payerId: 'ana', sharedBy: ['ana', 'marko'], category: CostCategory.food));
      trip.places.single.expenseId = 'e';
      expect(toSplit(trip, DateTime(2027, 6, 13, 12)), isEmpty);
      trip.places.add(Place(id: 'p', kind: PlaceKind.restaurant, name: 'Pizza', pricePerPerson: 1000, planned: true, dayVotes: {
        3: {'ana'},
      }));
      final line = Budget.of(trip, DateTime(2027, 6, 13, 12)).line(CostCategory.food);
      // Konoba cost 55 € for real; the pizza is still only an estimate.
      expect(line.actual, 5500);
    });

    test('a member is found again by name and the last eight digits of the number', () {
      expect(memberKey(' Ana ', '+385 91 234 5678'), memberKey('ana', '091 234 5678'));
      expect(memberKey('Ana', null), isNull);
      expect(memberKey('Ana', '12'), isNull);
      expect(memberKey('A.n#a\$[b]/c', '0912345678'), 'a_n_a__b__c_12345678');
    });

    test('the phones let into a trip and the members\' keys go to the cloud and back', () {
      final trip = visTrip()..access.addAll({'uid1': 'ana', 'uid2': 'ana'});
      final tree = tripToTree(trip, (id) => id == 'ana' ? 'Ana' : 'Ivo', (id) => id == 'ana' ? '091 234 5678' : null);
      expect(tree['keys'], {'ana_12345678': 'ana'});
      final back = jsonDecode(jsonEncode(unflatten(flatten(tree))));
      expect(tripFromTree('t1', (back as Map).cast<String, dynamic>())!.trip.access, {'uid1': 'ana', 'uid2': 'ana'});
      expect(Trip.fromJson(jsonDecode(jsonEncode(trip.toJson())) as Json).access, {'uid1': 'ana', 'uid2': 'ana'});
    });

    test('each category of Hrana i piće has its own plan per person, never mixed with estimates', () {
      final trip = visTrip();
      final every = foodKinds(trip).fold<int>(0, (sum, kind) => sum + foodKindCost(trip, kind));
      expect(every, plannedCost(trip, CostCategory.food));
      expect(setBudget(trip, CostCategory.food), isNull);
      trip.budgets[foodBudgetKey('restaurant')] = 5000;
      trip.budgets[foodBudgetKey('cafe')] = 1000;
      expect(setBudget(trip, CostCategory.food), 6000);
      expect(Budget.of(trip).line(CostCategory.food).planned, 6000 * trip.people);
    });

    test('your cost is only your part of what was really spent', () {
      final trip = visTrip()
        ..budgets['stay'] = 30000
        ..expenses.add(Expense(id: 'x', title: 'Ručak', amount: 9000, payerId: 'ana', sharedBy: ['ana', 'marko', 'iva'], category: CostCategory.food));
      expect(Budget.shareOf(trip, 'ana'), 3000);
      expect(Budget.shareOf(trip, 'nobody'), 0);
    });

    test('a trip saved before a map existed can still be changed', () {
      final json = jsonDecode(jsonEncode(visTrip().toJson())) as Json;
      for (final key in ['access', 'uids', 'memberPhotos', 'gone', 'showPicks']) {
        json.remove(key);
      }
      final trip = Trip.fromJson(json);
      trip.access['uid1'] = 'ana';
      trip.uids['ana'] = 'uid1';
      trip.memberPhotos['ana'] = 'p';
      trip.gone['ivo'] = 'Ivo';
      trip.showPicks['ana'] = 's';
      expect(trip.access, {'uid1': 'ana'});
    });

    test('a trip has one or two currencies, the first the one amounts are in', () {
      expect(cleanCurrencies([]), ['EUR']);
      expect(cleanCurrencies(['TRY', 'TRY', 'EUR', 'USD']), ['TRY', 'EUR']);
      expect(convert(10000, 'EUR', 'TRY', {'TRY': 50}), 500000);
      expect(convert(500000, 'TRY', 'USD', {'TRY': 50, 'USD': 1.1}), 11000);
      expect(convert(100, 'EUR', 'XXX', {}), isNull);
      final trip = visTrip()..currencies = ['TRY', 'EUR'];
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(trip, (id) => id)))));
      expect(tripFromTree('t1', (tree as Map).cast<String, dynamic>())!.trip.currencies, ['TRY', 'EUR']);
      expect(Trip.fromJson(jsonDecode(jsonEncode(trip.toJson())) as Json).currencies, ['TRY', 'EUR']);
      expect(Trip.fromJson(jsonDecode(jsonEncode(visTrip().toJson()..remove('currencies'))) as Json).currencies, ['EUR']);
    });

    test('polls in Plan napada go last, the last one in first', () {
      final trip = visTrip();
      trip.polls
        ..clear()
        ..addAll([
          for (final name in ['A', 'B', 'C', 'D'])
            Poll(id: name, title: name, options: [PollOption(id: 'o', time: 'Da')]),
        ]);
      setPollInAttack(trip, trip.polls[0], true, 'ana', DateTime(2027, 1, 1, 10));
      setPollInAttack(trip, trip.polls[2], true, 'ana', DateTime(2027, 1, 1, 11));
      expect(pollsInOrder(trip).map((poll) => poll.id), ['D', 'B', 'C', 'A']);
      setPollInAttack(trip, trip.polls[2], false, 'ana');
      expect(trip.polls[2].activeAt, isNull);
      expect(pollsInOrder(trip).map((poll) => poll.id), ['D', 'C', 'B', 'A']);
      expect(hasLetter('123 !?'), isFalse);
      expect(hasLetter('3 dana na Visu'), isTrue);
      expect(hasLetter('Šđ'), isTrue);
      trip.polls[0].activeAt = 123;
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(trip, (id) => id)))));
      expect(tripFromTree('t1', (tree as Map).cast<String, dynamic>())!.trip.polls.first.activeAt, 123);
    });

    test('bought lists of Dućan go last, the last bought first', () {
      final trip = visTrip()
        ..shopLists.addAll([
          ShopList(id: 'a', name: 'A', expenseId: 'x', boughtAt: 100),
          ShopList(id: 'b', name: 'B'),
          ShopList(id: 'c', name: 'C', expenseId: 'y', boughtAt: 200),
          ShopList(id: 'd', name: 'D'),
        ])
        ..expenses.addAll([
          Expense(id: 'x', title: 'A', amount: 100, payerId: 'ana', sharedBy: ['ana'], category: CostCategory.shop),
          Expense(id: 'y', title: 'C', amount: 100, payerId: 'ana', sharedBy: ['ana'], category: CostCategory.shop),
        ]);
      expect(listsInOrder(trip).map((list) => list.id), ['b', 'd', 'c', 'a']);
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(trip, (id) => id)))));
      expect(tripFromTree('t1', (tree as Map).cast<String, dynamic>())!.trip.shopLists.firstWhere((l) => l.id == 'c').boughtAt, 200);
    });

    test('changing a trip\'s currency converts every amount in it', () {
      final trip = visTrip()
        ..offers.add(Offer(id: 'o', name: 'Vila', pricePerNight: 10000))
        ..dishes.add(Dish(id: 'd', name: 'Peka', price: 2000, servings: 1))
        ..expenses.add(Expense(id: 'x', title: 'Ručak', amount: 9000, payerId: 'ana', sharedBy: ['ana'], category: CostCategory.food))
        ..payments.add(Payment(id: 'p', fromId: 'marko', toId: 'ana', amount: 3000))
        ..budgets['stay'] = 5000
        ..drive = Drive(tolls: 1000, ferry: 0);
      expect(changeTripCurrency(trip, 'XXX', {}), isFalse);
      expect(trip.offers.single.pricePerNight, 10000);
      expect(changeTripCurrency(trip, 'TRY', {'TRY': 50}), isTrue);
      expect(trip.currencies, ['TRY']);
      expect(trip.offers.single.pricePerNight, 500000);
      expect(trip.dishes.single.price, 100000);
      expect(trip.expenses.single.amount, 450000);
      expect(trip.payments.single.amount, 150000);
      expect(trip.budgets['stay'], 250000);
      expect(trip.drive.tolls, 50000);
    });

    test('amounts are written in the currency of the open trip', () {
      addTearDown(() {
        moneyCode = 'EUR';
        alsoCode = null;
        ratesPerEuro = const {};
      });
      moneyCode = 'TRY';
      expect(euros(30000), '300 ₺');
      expect(inMoney('Iznos (€)'), 'Iznos (₺)');
      expect(parseEuros('1.200,50 ₺'), 120050);
      alsoCode = 'EUR';
      expect(alsoIn(500000), '');
      ratesPerEuro = {'TRY': 50};
      expect(alsoIn(500000), '≈ 100 €');
    });

    test('a plan per person counts for everyone, and what it leaves is ahead', () {
      final trip = visTrip()
        ..budgets['food'] = 50000
        ..expenses.add(Expense(id: 'x', title: 'Ručak', amount: 12000, payerId: 'ana', sharedBy: ['ana'], category: CostCategory.food));
      final line = Budget.of(trip).line(CostCategory.food);
      final whole = 50000 * trip.people;
      expect([line.planned, line.actual, line.ahead], [whole, 12000, whole - 12000]);
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(trip, (id) => id)))));
      expect(tripFromTree('t1', (tree as Map).cast<String, dynamic>())!.trip.budgets, {'food': 50000});
      expect(Trip.fromJson(jsonDecode(jsonEncode(trip.toJson())) as Json).budgets, {'food': 50000});
    });

    test('a reserved stay is estimated, and spent once its cost is written', () {
      final trip = visTrip()
        ..offers.add(Offer(id: 'r', name: 'Vila Mare', pricePerNight: 10000, reserved: true));
      expect(Budget.of(trip).line(CostCategory.stay).estimate, 10000 * trip.nights);
      expect(Budget.of(trip).line(CostCategory.stay).actual, 0);
      trip.expenses.add(Expense(id: 'v', title: 'Vila Mare', amount: 10000 * trip.nights, payerId: 'ana', sharedBy: ['ana'], category: CostCategory.stay));
      final budget = Budget.of(trip);
      expect(budget.line(CostCategory.stay).actual, 10000 * trip.nights);
      expect(trip.reservedOffer?.name, 'Vila Mare');
    });

    test('the way to a stay is read from its address or its map link', () {
      expect(mapsPlace('Ulica 5, Vis'), 'Ulica 5, Vis');
      expect(mapsPlace('https://www.google.com/maps/place/Vila+Mare/@43.06,16.18,17z'), '43.06,16.18');
      expect(mapsPlace('https://maps.google.com/?q=Komiza+Vis'), 'Komiza Vis');
      expect(mapsPlace('https://www.google.com/maps/place/Vila+Mare/data=x'), 'Vila Mare');
      expect(mapsPlace('https://maps.app.goo.gl/abc'), isNull);
      final trip = visTrip();
      final walk = walkTo(Offer(id: 'o', name: 'Vila', pricePerNight: 1, location: 'Ulica 5'), trip);
      expect(walk.queryParameters['travelmode'], 'walking');
      expect(walk.queryParameters['origin'], 'My Location');
      expect(walkTo(Offer(id: 'o', name: 'Vila', pricePerNight: 1), trip, from: (latitude: 43.06, longitude: 16.18))
          .queryParameters['origin'], '43.060000,16.180000');
      expect(walk.queryParameters['destination'], 'Ulica 5');
      expect(walkTo(Offer(id: 'o', name: 'Vila', pricePerNight: 1), trip).queryParameters['destination'],
          'Vila, ${trip.city}');
      expect(
          walkTo(Offer(id: 'o', name: 'Vila', pricePerNight: 1, location: 'https://maps.app.goo.gl/abc'), trip)
              .queryParameters['destination'],
          'Vila, ${trip.city}');
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

    List<String> owed(Trip trip) =>
        debts(trip).map((t) => '${t.fromId}>${t.toId}:${t.amount}').toList();

    test('one person paying leaves two debts to them', () {
      final trip = visTrip()..expenses.add(spent(9000, 'ana', ['ana', 'marko', 'iva']));
      expect(owed(trip), ['marko>ana:3000', 'iva>ana:3000']);
    });

    test('shows every pair that owes something', () {
      final trip = visTrip()
        ..memberIds = ['a', 'b', 'c', 'd']
        ..expenses.add(spent(4000, 'a', ['a', 'b', 'c', 'd']))
        ..expenses.add(spent(2000, 'b', ['a', 'b', 'c', 'd']));
      expect(owed(trip), ['b>a:500', 'c>a:1000', 'c>b:500', 'd>a:1000', 'd>b:500']);
    });

    test('what two people owe each other cancels out', () {
      final trip = visTrip()
        ..expenses.add(spent(2000, 'ana', ['ana', 'marko']))
        ..expenses.add(spent(2000, 'marko', ['ana', 'marko']));
      expect(owed(trip), isEmpty);
    });

    test('a payment that was made is no longer owed', () {
      final trip = visTrip()
        ..expenses.add(spent(9000, 'ana', ['ana', 'marko', 'iva']))
        ..payments.add(Payment(fromId: 'marko', toId: 'ana', amount: 3000));
      expect(owed(trip), ['iva>ana:3000']);
    });

    test('paying every debt clears them all', () {
      final trip = visTrip()
        ..memberIds = ['a', 'b', 'c', 'd', 'e']
        ..expenses.add(spent(12345, 'a', ['a', 'b', 'c', 'd', 'e']))
        ..expenses.add(spent(777, 'b', ['b', 'c']))
        ..expenses.add(spent(5001, 'd', ['a', 'd', 'e']));
      expect(owed(trip), isNotEmpty);
      for (final debt in debts(trip)) {
        trip.payments
            .add(Payment(fromId: debt.fromId, toId: debt.toId, amount: debt.amount));
      }
      expect(debts(trip), isEmpty);
    });

    test('nothing spent means nothing to settle', () {
      expect(debts(visTrip()), isEmpty);
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
      expect(sortOffersBy(offers, []).map((o) => o.id), offers.map((o) => o.id));
      final even = [
        Offer(id: 'a', name: 'A', pricePerNight: 100, rating: 4),
        Offer(id: 'b', name: 'B', pricePerNight: 100, rating: 5),
        Offer(id: 'c', name: 'C', pricePerNight: 50, rating: 3),
      ];
      expect(sortOffersBy(even, [OfferSort.price, OfferSort.rating]).map((o) => o.id), ['c', 'b', 'a']);
      expect(sortOffersBy(even, [OfferSort.rating, OfferSort.price]).map((o) => o.id), ['b', 'a', 'c']);
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

  test('plan of attack keeps everything in its place and shows the winning vote', () {
    final trip = Trip(
      id: 't',
      country: 'Hrvatska',
      city: 'Vis',
      start: dayOf(2026, 7, 1),
      end: dayOf(2026, 7, 3),
      memberIds: ['x', 'y'],
      stops: [
        Stop(id: 'a', dayIndex: 0, title: 'Kava', time: '08:00', dayVotes: {
          0: {'x'},
        }),
        Stop(id: 'b', dayIndex: 0, title: 'Brod', time: '12:00', dayVotes: {
          0: {'y'},
        }),
      ],
      polls: [
        Poll(id: 'p', title: 'Plaža', dayIndex: 0, active: true, options: [
          PollOption(id: 'o0', time: '10:00', votes: {'x'}),
          PollOption(id: 'o1', time: '11:00', votes: {'x', 'y'}),
        ], dayVotes: {
          0: {'x', 'y'},
        }),
        Poll(id: 'q', title: 'Skriveno', options: [PollOption(id: 'o0', time: '09:00')]),
      ],
    );
    final items = planOfAttack(trip, DateTime(2026, 7, 1, 9));
    expect(items.map((item) => item.title), ['Kava', 'Brod', 'Plaža']);
    expect(items.last.time, '11:00');
    expect(items.map((item) => item.past), [true, false, false]);
  });

  group('places in the plan of attack', () {
    Trip trip({List<String> members = const ['x', 'y', 'z']}) => Trip(
          id: 't',
          country: 'Hrvatska',
          city: 'Vis',
          start: dayOf(2026, 7, 1),
          end: dayOf(2026, 7, 4),
          memberIds: members,
          stops: [Stop(id: 's', dayIndex: 0, title: 'Skok', hiddenInAttack: true)],
          polls: [
            Poll(
              id: 'p',
              title: 'Konoba',
              active: true,
              single: true,
              options: [
                PollOption(id: 'o0', time: 'Da', votes: {'x'}),
                PollOption(id: 'o1', time: 'Ne'),
              ],
              dayVotes: {
                2: {'x', 'y'},
                1: {'x'},
              },
            ),
          ],
        );

    test('a yes or no shows no answer, and the days half the group can go', () {
      final item = planOfAttack(trip(), DateTime(2026, 7, 1, 9)).single;
      expect(item.detail, isNull);
      expect(item.days, [2]);
      expect(item.past, isFalse);
    });

    test('at least half must agree, and both when there are two', () {
      Trip of(int people) => trip(members: [for (var i = 0; i < people; i++) 'm$i']);
      expect([1, 2, 3, 4, 5, 6].map((people) => of(people).votesToAgree), [1, 2, 2, 2, 3, 3]);
      final two = trip(members: ['x', 'y']);
      final poll = two.polls.single;
      expect(agreedDays(two, poll.dayVotes), [2]);
      expect(agreedOption(two, poll), isNull);
      poll.options.first.votes.add('y');
      expect(agreedOption(two, poll)?.time, 'Da');
    });

    test('only a Da of the whole group is a whole yes', () {
      final group = trip(members: ['x', 'y']);
      final poll = group.polls.single;
      expect(allSayYes(group, poll), isFalse);
      poll.options.first.votes.add('gone');
      expect(allSayYes(group, poll), isFalse);
      poll.options.first.votes.add('y');
      expect(allSayYes(group, poll), isTrue);
      poll.options.first.votes.clear();
      poll.options.last.votes.addAll({'x', 'y'});
      expect(allSayYes(group, poll), isFalse);
      final times = Poll(id: 'v', title: 'Plaža', options: [
        PollOption(id: 'a', time: '10:00', votes: {'x', 'y'}),
        PollOption(id: 'b', time: '11:30', votes: {'x'}),
      ]);
      expect(allSayYes(group, times), isFalse);
    });

    test('a whole yes goes into Plan napada once, and stays out when taken out', () {
      final group = trip(members: ['x', 'y']);
      final poll = group.polls.single..active = false;
      expect(addWholeYeses(group, 'x'), isEmpty);
      poll.options.first.votes.add('y');
      expect(addWholeYeses(group, 'y'), [poll]);
      expect(pollInAttack(group, poll), isTrue);
      setPollInAttack(group, poll, false, 'x');
      expect(addWholeYeses(group, 'x'), isEmpty);
      expect(pollInAttack(group, poll), isFalse);
      poll.options.first.votes.remove('y');
      expect(wholeYesChanged(group, poll), isTrue);
      addWholeYeses(group, 'x');
      poll.options.first.votes.add('y');
      expect(addWholeYeses(group, 'y'), [poll]);
    });

    test('a renamed poll takes its place along, so they stay one thing', () {
      final group = trip(members: ['x', 'y']);
      final place = Place(id: 'k', kind: PlaceKind.restaurant, name: 'Konoba');
      final poll = Poll(id: 'q', title: 'Konoba', single: true, options: [
        PollOption(id: 'o0', time: 'Da'),
      ]);
      group
        ..places.add(place)
        ..polls.add(poll);
      renamePoll(group, poll, 'Konoba Bako');
      expect(poll.title, 'Konoba Bako');
      expect(place.name, 'Konoba Bako');
      expect(placeOf(group, poll), place);
      final alone = group.polls.first;
      renamePoll(group, alone, 'Kupanje');
      expect(alone.title, 'Kupanje');
      expect(place.name, 'Konoba Bako');
    });

    test('an added answer shows in Plan napada, a no never decides', () {
      final group = trip(members: ['x', 'y']);
      final poll = group.polls.single
        ..options.add(PollOption(id: 'o2x', time: 'Sutra', votes: {'y'}));
      poll.options.first.votes.clear();
      poll.options[1].votes.addAll({'x', 'y'});
      expect(agreedOption(group, poll)?.time, isNot('Ne'));
      final item = planOfAttack(group, DateTime(2026, 6, 1)).firstWhere((i) => i.poll == poll);
      expect(item.detail, 'Sutra');
    });

    test('a no is never agreed, and votes of those not in the group do not count', () {
      final group = trip(members: ['x', 'y']);
      final poll = group.polls.single;
      poll.options.first.votes.clear();
      poll.options.last.votes.addAll({'x', 'y'});
      expect(agreedOption(group, poll), isNull);
      poll.options.first.votes.addAll({'x', 'gone'});
      expect(agreedOption(group, poll), isNull);
    });

    test('a thing stands on the day with most votes, on all equal ones, and on none without a vote', () {
      final group = trip();
      expect(votedDays(group, {}), isEmpty);
      expect(votedDays(group, {
        1: {'x'},
      }), [1]);
      expect(votedDays(group, {
        1: {'x', 'y'},
        2: {'y', 'z'},
        0: {'z'},
      }), [1, 2]);
      expect(votedDays(group, {
        1: {'x', 'y'},
        2: {'y', 'z', 'x'},
      }), [2]);
      expect(votedDays(group, {
        1: {'x'},
        2: {'gone', 'left'},
      }), [1]);
    });

    test('it goes grey only once its last agreed day has gone by', () {
      expect(planOfAttack(trip(), DateTime(2026, 7, 3, 23)).single.past, isFalse);
      expect(planOfAttack(trip(), DateTime(2026, 7, 4, 0, 5)).single.past, isTrue);
    });

    test('a hidden stop stays out, and only days left can be chosen', () {
      expect(planOfAttack(trip(), DateTime(2026, 7, 1)).any((i) => i.stop != null), isFalse);
      expect(remainingDays(trip(), DateTime(2026, 7, 3, 12)), [2, 3]);
    });

    test('only votes give a day, not the day of Plan puta or of an older poll', () {
      final plan = trip()
        ..stops.add(Stop(id: 'b', dayIndex: 0, title: 'Brod', dayVotes: {
          3: {'x', 'z'},
          1: {'y'},
        }))
        ..polls.add(Poll(id: 'old', title: 'Stara', dayIndex: 0, active: true, options: [
          PollOption(id: 'o0', time: '10:00', votes: {'x'}),
        ]));
      final items = planOfAttack(plan, DateTime(2026, 6, 1));
      expect(items.firstWhere((i) => i.stop != null).days, [3]);
      expect(items.firstWhere((i) => i.title == 'Stara').days, isEmpty);
    });

    test('a place is in the plan once, whether through its poll or itself', () {
      final plan = trip()
        ..places.add(Place(id: 'k', kind: PlaceKind.restaurant, name: 'Konoba', pricePerPerson: 2000));
      final poll = plan.polls.single;
      final only = planOfAttack(plan, DateTime(2026, 7, 1, 9)).single;
      expect(only.place?.id, 'k');
      expect(only.cost, 6000);
      setPollInAttack(plan, poll, false, 'x');
      expect(planOfAttack(plan, DateTime(2026, 7, 1, 9)), isEmpty);
      expect(pollInAttack(plan, poll), isFalse);
      setPollInAttack(plan, poll, true, 'y');
      expect(plan.places.single.planned, isTrue);
      expect(plan.places.single.plannedBy, 'y');
      expect(poll.active, isFalse);
      expect(planOfAttack(plan, DateTime(2026, 7, 1, 9)).single.place?.id, 'k');
    });

    test('a poll with times shows the time, a yes or no never shows its yes', () {
      final plan = trip()
        ..polls.add(Poll(id: 'q', title: 'Plaža', active: true, options: [
          PollOption(id: 'o0', time: 'Da', votes: {'x', 'y'}),
          PollOption(id: 'o1', time: 'Ne'),
        ]))
        ..polls.add(Poll(id: 'r', title: 'Brod', active: true, options: [
          PollOption(id: 'o0', time: '10:00', votes: {'x'}),
          PollOption(id: 'o1', time: '11:30', votes: {'x', 'y'}),
        ]));
      final items = {for (final item in planOfAttack(plan, DateTime(2026, 6, 1))) item.title: item};
      expect(items['Plaža']!.detail, isNull);
      expect(items['Brod']!.time, '11:30');
    });

    test('day votes and who left survive saving and the cloud', () {
      final plan = trip()
        ..places.add(Place(
          id: 'k',
          kind: PlaceKind.restaurant,
          name: 'Kafe',
          planned: true,
          plannedBy: 'x',
          dayVotes: {
            1: {'x'},
          },
        ))
        ..gone['w'] = 'Wanda';
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(plan, (id) => id)))));
      final back = tripFromTree('t', (tree as Map).cast<String, dynamic>())!.trip;
      expect(back.polls.single.dayVotes, {
        1: {'x'},
        2: {'x', 'y'},
      });
      expect(back.places.single.dayVotes, {
        1: {'x'},
      });
      expect(back.places.single.plannedBy, 'x');
      expect(back.gone, {'w': 'Wanda'});
      expect(back.stops.single.hiddenInAttack, isTrue);
      final saved = Trip.fromJson(jsonDecode(jsonEncode(plan.toJson())) as Json);
      expect(saved.places.single.dayVotes, {
        1: {'x'},
      });
      expect(saved.gone, {'w': 'Wanda'});
    });
  });

  group('the plan of attack in Troškovi', () {
    Trip trip() => Trip(
          id: 't',
          country: 'Hrvatska',
          city: 'Vis',
          start: dayOf(2026, 7, 1),
          end: dayOf(2026, 7, 4),
          memberIds: ['x', 'y'],
          places: [
            Place(
              id: 'k',
              kind: PlaceKind.restaurant,
              name: 'Konoba',
              pricePerPerson: 2000,
              planned: true,
              dayVotes: {
                1: {'x', 'y'},
              },
            ),
            Place(id: 'n', kind: PlaceKind.cafe, name: 'Bez dana', pricePerPerson: 500, planned: true),
          ],
          stops: [
            Stop(id: 'b', dayIndex: 0, title: 'Brod', cost: 3000, dayVotes: {
              0: {'x', 'y'},
            }),
          ],
        );

    test('is only an estimate, before its day and after it, until its cost is written', () {
      final before = Budget.of(trip(), DateTime(2026, 6, 30));
      expect(before.line(CostCategory.food).estimate, 5000);
      expect(before.actualTotal, 0);
      final after = Budget.of(trip(), DateTime(2026, 7, 3));
      expect(after.actualTotal, 0);
      expect(after.plannedTotal, before.plannedTotal);
    });

    test('a real cost of the same name counts instead of the estimate', () {
      final paid = trip()
        ..expenses.add(Expense(
          id: 'e',
          title: 'konoba ',
          amount: 5500,
          payerId: 'x',
          sharedBy: ['x', 'y'],
          category: CostCategory.food,
        ));
      expect(Budget.of(paid, DateTime(2026, 7, 3)).line(CostCategory.food).actual, 5500);
    });

    test('something long over is still not spent until it is written', () {
      final over = Budget.of(trip(), DateTime(2026, 8, 1));
      expect(over.actualTotal, 0);
    });
  });

  group('news', () {
    final names = {'a': 'Ana', 'b': 'Bruno'};
    final device = <String, dynamic>{
      'trips': {'t': <String, dynamic>{}},
    };
    Trip trip() => Trip(
          id: 't',
          country: 'Hrvatska',
          city: 'Vis',
          start: dayOf(2026, 7, 1),
          end: dayOf(2026, 7, 4),
          memberIds: ['a', 'b'],
          uids: {'a': 'ua', 'b': 'ub'},
          polls: [
            Poll(id: 'p', title: 'Plaža', addedBy: 'a', options: [
              PollOption(id: 'o0', time: 'Da'),
              PollOption(id: 'o1', time: 'Ne'),
            ]),
          ],
          photos: [
            Photo(id: 'f1', takenAt: DateTime(2026, 7, 1), addedBy: 'a'),
            Photo(id: 'f2', takenAt: DateTime(2026, 7, 2), addedBy: 'a'),
          ],
        );
    Set<Object?> allOf(Trip trip) =>
        {newsVersion, for (final event in tripEvents(trip, names)) event.key};
    List<String> bodies(List<({String body, String route})> news) =>
        [for (final item in news) item.body];

    test('the photos of one person come as one message', () {
      expect(bodies(newsFor('ub', 't', trip(), names, {newsVersion}, device)),
          containsAll(['Nova anketa: Plaža', 'Ana dodaje nove uspomene (2)']));
    });

    test('nobody is told what they did', () {
      expect(bodies(newsFor('ua', 't', trip(), names, {newsVersion}, device)),
          ['Bruno je sada na putovanju']);
    });

    test('a kind turned off everywhere or for one trip is not sent', () {
      final none = <String, dynamic>{
        'off': {'polls': true},
        'trips': {'t': <String, dynamic>{}},
      };
      expect(bodies(newsFor('ub', 't', trip(), names, allOf(trip())..remove('poll:p'), none)),
          isEmpty);
      final quiet = <String, dynamic>{
        'trips': {
          't': {
            'off': {'photos': true},
          },
        },
      };
      expect(bodies(newsFor('ub', 't', trip(), names, {newsVersion}, quiet)),
          isNot(contains('Ana dodaje nove uspomene (2)')));
      expect(wantsNotice(quiet, 'other', Notice.photos), isTrue);
      expect(wantsNotice(none, 'other', Notice.polls), isFalse);
    });

    test('kinds new in this version are not news the first time', () {
      final told = {for (final event in tripEvents(trip(), names)) event.key}
        ..removeWhere((key) => key.startsWith('photo:'));
      expect(newsFor('ub', 't', trip(), names, told, device), isEmpty);
    });

    test('a poll the group voted through is told once, as voted', () {
      final voted = trip();
      final poll = voted.polls.single..options.first.votes.addAll({'a', 'b'});
      setPollInAttack(voted, poll, true, 'a');
      final keys = [for (final event in tripEvents(voted, names)) event.key];
      expect(keys, contains('passed:p'));
      expect(keys, isNot(contains('attack:p')));
    });

    test('a day agreed on and someone leaving are news', () {
      final before = trip()
        ..places.add(Place(id: 'k', kind: PlaceKind.restaurant, name: 'Konoba', planned: true));
      final after = trip()
        ..places.add(Place(id: 'k', kind: PlaceKind.restaurant, name: 'Konoba', planned: true, dayVotes: {
          1: {'a', 'b'},
        }))
        ..gone['c'] = 'Cvita';
      expect(bodies(newsFor('ub', 't', after, names, allOf(before), device)),
          ['Dogovoreno: Konoba, četvrtak, 2. srpnja', 'Cvita više nije na putovanju']);
    });
  });

  group('presentations', () {
    Trip trip(int days) => Trip(
          id: 't',
          country: 'Hrvatska',
          city: 'Vis',
          start: dayOf(2026, 11, 2),
          end: dayOf(2026, 11, 1 + days),
          memberIds: ['a', 'b', 'c'],
        );
    DateTime on(int day) => DateTime(2026, 11, day, 12);

    test('a transition gets longer each day of the trip, up to 12 s on the last', () {
      final four = trip(4);
      expect([for (final day in [1, 2, 3, 4, 5, 9]) extraLimit(four, on(day))],
          [6, 6, 8, 10, 12, 12]);
      final eight = trip(8);
      final limits = [for (var day = 2; day <= 9; day++) extraLimit(eight, on(day))];
      expect(limits.first, 6);
      expect(limits[1], 6.86);
      expect(limits.last, 12);
      for (var i = 1; i < limits.length; i++) {
        expect(limits[i], greaterThan(limits[i - 1]));
      }
      final one = trip(1);
      expect(extraLimit(one, on(2)), 6);
      expect(extraLimit(one, on(3)), 12);
    });

    test('five transitions at first, all fifteen on the last day', () {
      final four = trip(4);
      expect([for (final day in [1, 2, 3, 4, 5]) openTransitions(four, on(day))],
          [5, 5, 8, 11, 15]);
      expect(effects, hasLength(15));
      expect(Transition.values, hasLength(16));
      expect(effects, isNot(contains(Transition.none)));
    });

    test('each day of the trip opens a little more, the marks on the bars', () {
      expect(dayLimits(trip(4)), [6, 8, 10, 12]);
      expect(dayLimits(trip(8)).take(2), [6, 6.86]);
    });

    test('a photo is on the day it was taken or moved to, or before or after the trip', () {
      final plan = trip(4);
      Photo at(int day, [int? moved]) =>
          Photo(id: '$day', takenAt: DateTime(2026, 11, day, 12), addedBy: 'a', dayIndex: moved);
      expect([for (final day in [1, 2, 3, 5, 6, 9]) plan.photoDay(at(day))], [-1, 0, 1, 3, 4, 4]);
      expect(plan.photoDay(at(2, 2)), 2);
      expect(plan.photoDay(at(2, afterTrip)), 4);
      expect(plan.photoDay(at(4, -1)), -1);
      expect([photoDayTitle(plan, -1), photoDayTitle(plan, 4)], ['Prije puta', 'Poslije puta']);
    });

    test('the time since a change counts seconds, then minutes, then hours', () {
      expect(sinceCount(const Duration(seconds: 5)), '5 sekundi');
      expect(sinceCount(const Duration(seconds: 2)), '2 sekunde');
      expect(sinceCount(const Duration(minutes: 3)), '3 minute');
      expect(sinceCount(const Duration(minutes: 30)), '30 minuta');
      expect(sinceCount(const Duration(minutes: 61)), '1 sata');
      expect(sinceCount(const Duration(minutes: 1)), '1 minute');
      expect(sinceCount(const Duration(hours: 5)), '5 sati');
      expect([listsCount(0), listsCount(1), listsCount(3), listsCount(5)], ['0 lista', '1 lista', '3 liste', '5 lista']);
    });

    test('a presentation keeps the photos picked for it in their order', () {
      final plan = trip(4)
        ..photos.addAll([
          Photo(id: 'a', takenAt: DateTime(2026, 11, 2, 9), addedBy: 'a'),
          Photo(id: 'b', takenAt: DateTime(2026, 11, 3, 9), addedBy: 'a', dayIndex: 0),
          Photo(id: 'c', takenAt: DateTime(2026, 11, 2, 8), addedBy: 'a', dayIndex: 2),
        ]);
      expect(photosByDay(plan).map((photo) => photo.id), ['a', 'b', 'c']);
      final show = Show(id: 's', name: 'Moja', addedBy: 'a', chosen: ['c', 'removed', 'a']);
      expect(slidesOf(plan, show).map((slide) => slide.photoId), ['c', 'a']);
    });

    test('takes everything in the order it was taken, but what is left out', () {
      final plan = trip(4)
        ..photos.addAll([
          Photo(id: 'late', takenAt: DateTime(2026, 11, 3, 18), addedBy: 'a'),
          Photo(id: 'early', takenAt: DateTime(2026, 11, 2, 9), addedBy: 'b'),
          Photo(
              id: 'film',
              takenAt: DateTime(2026, 11, 2, 10),
              addedBy: 'a',
              videoType: 'video/mp4',
              seconds: 20),
          Photo(id: 'old film', takenAt: DateTime(2026, 11, 2, 10, 30), addedBy: 'a', videoType: 'video/mp4'),
          Photo(id: 'out', takenAt: DateTime(2026, 11, 2, 11), addedBy: 'a'),
        ]);
      final show = Show(id: 's', name: 'Dan 1', addedBy: 'a', look: Look(Transition.push))
        ..leftOut.add('out')
        ..looks['late'] = Look(Transition.circle, 2.5);
      final slides = slidesOf(plan, show);
      expect(slides.map((slide) => slide.photoId), ['early', 'film', 'old film', 'late']);
      expect(slides.map((slide) => slide.video), [null, 20, 30, null]);
      expect(slides.first.look.transition, Transition.push);
      expect(slides.last.look.extra, 2.5);
    });

    test('a photo stands 2,5 s or as long as set, a video plays a piece of 6 s in every 30 s', () {
      final slides = <Slide>[
        (photoId: 'x', look: Look(Transition.fade), video: null),
        (photoId: 'y', look: Look(Transition.push, 2), video: null),
      ];
      expect(slideLength(slides.first), 3.5);
      expect(slideLength((photoId: 'z', look: Look(Transition.fade, 0, 3.5), video: null)), 4.5);
      expect(frameAt(slides, 0), (index: 0, previous: null, progress: 0, into: 0));
      expect(frameAt(slides, 4.5), (index: 1, previous: 0, progress: 1 / 3, into: 1));
      expect(frameAt(slides, 8), (index: 1, previous: 0, progress: 1, into: 4.5));
      expect(frameAt(slides, 9.5), (index: 0, previous: 1, progress: 0.5, into: 0.5));
      expect(secondsBefore(slides, 1), 3.5);

      expect([longestClip(4), longestClip(20), longestClip(30), longestClip(45)], [4, 6, 6, 12]);
      final film = (photoId: 'f', look: Look(Transition.fade, 1, 0, 18, 6), video: 20.0);
      expect(clipOf(film), (from: 14, length: 6));
      expect(slideLength(film), 8);
      final short = (photoId: 'g', look: Look(Transition.fade, 0, 0, 2, 6), video: 4.0);
      expect(clipOf(short), (from: 0, length: 4));
    });

    test('the presentation with most votes is of the day and plays on the cover', () {
      final plan = trip(4)
        ..photos.add(Photo(id: 'p', takenAt: DateTime(2026, 11, 2, 9), addedBy: 'a'))
        ..shows.addAll([
          Show(id: 's1', name: 'Prva', addedBy: 'a', chosen: ['p']),
          Show(id: 's2', name: 'Druga', addedBy: 'b', chosen: ['p']),
          Show(id: 's3', name: 'Treća', addedBy: 'b', chosen: ['removed']),
        ]);
      expect(showOfTheDay(plan), isNull);
      expect(onCover(plan)?.id, 's2');
      plan.showPicks['b'] = 's2';
      expect(keepShowOfTheDay(plan), isTrue);
      expect(showOfTheDay(plan)?.id, 's2');
      // As many votes do not take its place.
      plan.showPicks['a'] = 's1';
      expect(keepShowOfTheDay(plan), isFalse);
      expect(showOfTheDay(plan)?.id, 's2');
      // More do; votes of those not in the group do not count.
      plan.showPicks.addAll({'c': 's1', 'gone': 's2', 'x': 's2'});
      expect(keepShowOfTheDay(plan), isTrue);
      expect(showOfTheDay(plan)?.id, 's1');
      expect(onCover(plan)?.id, 's1');
      plan
        ..dayShowId = null
        ..showPicks.remove('c');
      expect(showOfTheDay(plan)?.id, 's1');
      expect(showsBy(plan, 'b').map((show) => show.name), ['Druga', 'Treća']);
      expect(showsBy(plan, 'c'), isEmpty);
      expect(showsEach, 3);
    });

    test('a presentation and the picks survive saving and the cloud', () {
      final plan = trip(4)
        ..shows.add(Show(
          id: 's1',
          name: 'Najbolji dan',
          addedBy: 'a',
          look: Look(Transition.wipe, 1.25),
          looks: {'p': Look(Transition.spin, 6.86, 4.2)},
          leftOut: {'q'},
          chosen: ['q', 'p', 'r'],
        ))
        ..showPicks['b'] = 's1'
        ..dayShowId = 's1'
        ..photos.add(Photo(id: 'p', takenAt: DateTime(2026, 11, 2, 9), addedBy: 'a', dayIndex: 2));
      final tree = jsonDecode(jsonEncode(unflatten(flatten(tripToTree(plan, (id) => id)))));
      for (final back in [
        tripFromTree('t', (tree as Map).cast<String, dynamic>())!.trip,
        Trip.fromJson(jsonDecode(jsonEncode(plan.toJson())) as Json),
      ]) {
        final show = back.shows.single;
        expect(show.name, 'Najbolji dan');
        expect(show.look.transition, Transition.wipe);
        expect(show.look.extra, 1.25);
        expect(show.looks['p']?.transition, Transition.spin);
        expect(show.looks['p']?.extra, 6.86);
        expect(show.looks['p']?.still, 4.2);
        expect(show.look.still, 2.5);
        expect(show.leftOut, {'q'});
        expect(show.chosen, ['q', 'p', 'r']);
        expect(back.showPicks, {'b': 's1'});
        expect(back.dayShowId, 's1');
        expect(back.photos.single.dayIndex, 2);
      }
    });

    test('Ništa cuts at once, and an old Kroz crno comes back as Lom stakla', () {
      final cut = (photoId: 'c', look: Look(Transition.none, 4, 3), video: null);
      expect(movingTime(cut.look), 0);
      expect(slideLength(cut), 3);
      expect(frameAt([cut, cut], 1).progress, 1);
      expect(Look.fromJson({'transition': 'black'}).transition, Transition.glass);
      expect(Look.fromJson({'transition': 'none'}).transition, Transition.none);
    });

    test('seconds show their first decimal only', () {
      expect(tenths(7.72), '7,7');
      expect(tenths(6.86), '6,8');
      expect(tenths(12), '12,0');
      expect(tenths(0.3), '0,3');
    });
  });

  test('a yes or no takes one answer from each person', () {
    Poll poll(List<String> answers) => Poll(id: 'p', title: 'Ronjenje', options: [
          for (var i = 0; i < answers.length; i++) PollOption(id: 'o$i', time: answers[i]),
        ]);
    expect(onlyOneAnswer(poll(['Da', 'Ne'])), isTrue);
    expect(onlyOneAnswer(poll(['10:00', '11:30'])), isFalse);
    expect(onlyOneAnswer(Poll(id: 'k', title: 'Konoba', single: true, options: [])), isTrue);
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

    test('numbers are written with a dot between thousands and no ,00', () {
      expect(decimal(4), '4');
      expect(decimal(4.5), '4,5');
      expect(decimal(1200), '1.200');
      expect(decimal(1234567.891), '1.234.567,89');
      expect(euros(20000), '200 €');
      expect(euros(125050), '1.250,50 €');
      expect(plainAmount(125000), '1.250');
    });

    test('what stands between you and each person is all debts added up', () {
      const transfers = [
        Transfer(fromId: 'riko', toId: 'ramo', amount: 550),
        Transfer(fromId: 'riko', toId: 'ramo', amount: 450),
        Transfer(fromId: 'frajta', toId: 'riko', amount: 9000),
        Transfer(fromId: 'ivo', toId: 'ana', amount: 100),
        Transfer(fromId: 'ana', toId: 'riko', amount: 300),
        Transfer(fromId: 'riko', toId: 'ana', amount: 300),
      ];
      expect(balanceOf(transfers, 'riko'), {'ramo': -1000, 'frajta': 9000});
    });

    test('an amount is written as it is typed: 1.250,50', () {
      expect(typedAmount('1250', 4), (text: '1.250', caret: 5));
      expect(typedAmount('1.2500', 6), (text: '12.500', caret: 6));
      expect(typedAmount('12500,5', 7), (text: '12.500,5', caret: 8));
      expect(typedAmount('1.250,555', 9), (text: '1.250,55', caret: 8));
      expect(typedAmount('12.', 3, dotTyped: true), (text: '12,', caret: 3));
      expect(typedAmount('007', 3), (text: '7', caret: 1));
      expect(typedAmount(',5', 2), (text: '0,5', caret: 3));
      expect(typedAmount('1.250', 2), (text: '1.250', caret: 1));
      expect(typedAmount('', 0), (text: '', caret: 0));
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
      expect(parseEuros('Infinity'), isNull);
    });

    test('reads a price that may be a range', () {
      const tenToThirty = (middle: 2000, low: 1000, high: 3000);
      expect(parsePriceRange('20'), (middle: 2000, low: null, high: null));
      expect(parsePriceRange('12,50'), (middle: 1250, low: null, high: null));
      expect(parsePriceRange('10-30'), tenToThirty);
      expect(parsePriceRange(' 10 – 30 € '), tenToThirty);
      expect(parsePriceRange('10--30'), tenToThirty);
      expect(parsePriceRange('10—30'), tenToThirty);
      expect(parsePriceRange('30-10'), tenToThirty);
      expect(parsePriceRange('10,50-12'), (middle: 1125, low: 1050, high: 1200));
      expect(parsePriceRange('20-20'), (middle: 2000, low: null, high: null));
      expect(parsePriceRange(''), isNull);
      expect(parsePriceRange('10-'), isNull);
      expect(parsePriceRange('-10'), isNull);
      expect(parsePriceRange('10-20-30'), isNull);
      expect(parsePriceRange('puno'), isNull);
    });

    test('shows a range of euros', () {
      expect(eurosRange(1000, 3000), '10–30 €');
      expect(eurosRange(750, 1200), '7,50–12 €');
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

  group('videos', () {
    test('a big file is kept in pieces the database accepts', () {
      expect(piecesFor(100), 1);
      expect(piecesFor(2250000), 1);
      expect(piecesFor(2250001), 2);
      expect(piecesFor(4000000), 2);
      expect(piecesFor(4600000), 3);
      expect(pieceId('v', 0), 'v');
      expect(pieceId('v', 2), 'v.2');
    });

    test('a video stays a video through saving and the cloud', () {
      final trip = visTrip()
        ..photos.add(Photo(
          id: 'v',
          takenAt: DateTime.utc(2027, 6, 12, 10),
          addedBy: 'ana',
          videoType: 'video/mp4',
          parts: 2,
        ))
        ..photos.add(Photo(id: 'p', takenAt: DateTime.utc(2027, 6, 12), addedBy: 'ana'));
      final saved = Trip.fromJson(jsonDecode(jsonEncode(trip.toJson())) as Json);
      final tree = unflatten(flatten(tripToTree(trip, (id) => id)));
      final cloud = tripFromTree(trip.id, jsonDecode(jsonEncode(tree)) as Tree)!.trip;
      for (final back in [saved, cloud]) {
        final video = back.photos.firstWhere((photo) => photo.id == 'v');
        expect(video.isVideo, isTrue);
        expect(video.videoType, 'video/mp4');
        expect(video.parts, 2);
        final picture = back.photos.firstWhere((photo) => photo.id == 'p');
        expect(picture.isVideo, isFalse);
        expect(picture.parts, 1);
      }
    });

    Uint8List movie(int version, int seconds) {
      final bytes = ByteData(40);
      const name = 'mvhd';
      for (var i = 0; i < 4; i++) {
        bytes.setUint8(10 + i, name.codeUnitAt(i));
      }
      bytes.setUint8(14, version);
      if (version == 1) {
        bytes.setUint32(18, 0);
        bytes.setUint32(22, seconds);
      } else {
        bytes.setUint32(18, seconds);
      }
      return bytes.buffer.asUint8List();
    }

    test('reads when a video was taken', () {
      final taken = DateTime.utc(2027, 6, 12, 10, 30);
      final seconds = taken.difference(DateTime.utc(1904)).inSeconds;
      expect(readVideoDate(movie(0, seconds)), taken);
      expect(readVideoDate(movie(1, seconds)), taken);
    });

    test('a video without a date has none', () {
      expect(readVideoDate(movie(0, 0)), isNull);
      expect(readVideoDate(Uint8List(64)), isNull);
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
