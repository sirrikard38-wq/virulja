import 'dart:convert';

import 'package:test/test.dart';
import 'package:virulja/src/domain/models.dart';
import 'package:virulja/src/domain/tree.dart';
import 'package:virulja/src/domain/trip_events.dart';
import 'package:virulja/src/domain/trip_tree.dart';

Trip _trip(List<String> members) => Trip(
      id: 'tttttttttttttttt',
      country: 'Hrvatska',
      city: 'Vis',
      start: dayOf(2027, 7, 1),
      end: dayOf(2027, 7, 3),
      memberIds: members,
    );

void main() {
  group('changes the database accepts', () {
    bool overlaps(Map<String, Object?> changes) => changes.keys.any((path) =>
        changes.keys.any((other) => other.startsWith('$path/')));

    test('a value that became a branch is never named twice', () {
      final from = <String, Object>{'reactions/ana': 'sun', 'city': 'Vis'};
      final to = <String, Object>{'reactions/ana/sun': true, 'city': 'Vis'};
      final changes = changesBetween(from, to);
      expect(overlaps(changes), isFalse);
      expect(changes, {'reactions/ana/sun': true});
      expect(applyChanges(from, changes), to);
    });

    test('a branch that became a value is never named twice', () {
      final from = <String, Object>{'a/b': 1, 'a/c': 2};
      final to = <String, Object>{'a': 3};
      final changes = changesBetween(from, to);
      expect(overlaps(changes), isFalse);
      expect(applyChanges(from, changes), to);
    });

    test('a mirror with an old reaction has nothing left after sending', () {
      final mirror = TripMirror(server: {'reactions/ana': 'sun'});
      final local = <String, Object>{'reactions/ana/sun': true};
      mirror.confirm(mirror.pending(local));
      expect(mirror.pending(local), isEmpty);
    });

    test('removing things still sends the removal', () {
      expect(changesBetween({'a/b': 1}, {}), {'a/b': null});
    });
  });

  test('profile photos survive the cloud', () {
    final tree = unflatten(flatten(
        tripToTree(_trip(['a', 'b']), (id) => id, null, (id) => id == 'a' ? 'pic' : null)));
    final back = tripFromTree('tttttttttttttttt', jsonDecode(jsonEncode(tree)) as Tree)!;
    expect(back.photos, {'a': 'pic'});
    final person = Person.fromJson(Person(id: 'a', name: 'A', photoId: 'pic').toJson());
    expect(person.photoId, 'pic');
  });

  test('categories the group made survive the cloud', () {
    final trip = _trip(['a'])
      ..customKinds = [CustomKind(id: 'k1', label: 'Pizzerije')]
      ..places = [
        Place(id: 'p1', kind: PlaceKind.restaurant, name: 'Mare', customKindId: 'k1'),
      ];
    final tree = unflatten(flatten(tripToTree(trip, (id) => id)));
    final back = tripFromTree(trip.id, jsonDecode(jsonEncode(tree)) as Tree)!.trip;
    expect(back.customKinds.single.label, 'Pizzerije');
    expect(back.places.single.customKindId, 'k1');
    final copy = Trip.fromJson(jsonDecode(jsonEncode(trip.toJson())) as Json);
    expect(copy.customKinds.single.id, 'k1');
    expect(copy.places.single.customKindId, 'k1');
  });

  group('joining', () {
    test('a lone member decides alone, a bigger group needs two approvals', () {
      expect(_trip(['a']).approvalsNeeded, 1);
      expect(_trip(['a', 'b']).approvalsNeeded, 2);
      expect(_trip(['a', 'b', 'c', 'd']).approvalsNeeded, 2);
    });

    test('a request survives the trip to the cloud and back', () {
      final trip = _trip(['a', 'b'])
        ..requests = [
          JoinRequest(id: 'uid1', name: 'Mate', phone: '091', approvals: {'a'}),
        ];
      final tree = unflatten(flatten(tripToTree(trip, (id) => id)));
      final back = tripFromTree(trip.id, jsonDecode(jsonEncode(tree)) as Tree)!.trip;
      expect(back.requests.single.name, 'Mate');
      expect(back.requests.single.approvals, {'a'});
      final copy = Trip.fromJson(jsonDecode(jsonEncode(trip.toJson())) as Json);
      expect(copy.requests.single.id, 'uid1');
    });

    test('the group hears about a request', () {
      final trip = _trip(['a', 'b'])
        ..requests = [JoinRequest(id: 'uid1', name: 'Mate')];
      final event = tripEvents(trip, const {}).single;
      expect(event.text, 'Mate želi na putovanje');
      expect(event.to, isNull);
      expect(event.from, isNull);
    });
  });
}
