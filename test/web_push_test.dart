import 'dart:convert';

import 'package:test/test.dart';
import 'package:virulja/src/domain/models.dart';
import 'package:virulja/src/domain/reminders.dart';
import 'package:virulja/src/domain/trip_events.dart';

import '../tool/web_push.dart';

void main() {
  test('reminders come 3, 2 and 1 weeks and 3, 2 and 1 days before', () {
    final start = dayOf(2027, 7, 22);
    final due = [
      for (var days = 0; days <= 30; days++)
        if (reminderText(start, start.subtract(Duration(days: days))) != null) days,
    ];
    expect(due, [1, 2, 3, 7, 14, 21]);
  });

  test('events reach the right people and never the one who acted', () {
    final trip = Trip(
      id: 't',
      country: 'Hrvatska',
      city: 'Vis',
      start: dayOf(2027, 7, 1),
      end: dayOf(2027, 7, 3),
      memberIds: ['a', 'b'],
      polls: [
        Poll(id: 'p', title: 'Plaža', options: [], addedBy: 'a', active: true, activeBy: 'b'),
      ],
      stops: [Stop(id: 's', dayIndex: 0, title: 'Brod', addedBy: 'a')],
      photos: [
        Photo.fromJson({
          'id': 'f',
          'addedBy': 'a',
          'blobId': 'f',
          'day': '2027-07-01',
          'dayIndex': 0,
          'takenAt': '2027-07-01',
          'at': '2027-07-01',
          'reactions': {
            'a': {'heart': true},
            'b': {'heart': true},
          },
          'comments': [
            {'id': 'c1', 'authorId': 'b', 'text': 'x', 'at': '2027-07-01'},
            {'id': 'c2', 'authorId': 'a', 'text': 'y', 'at': '2027-07-02', 'replyTo': 'c1'},
            {'id': 'c3', 'authorId': 'b', 'text': 'z', 'at': '2027-07-03', 'replyTo': 'c1'},
          ],
        }),
      ],
    );
    final events = tripEvents(trip, {'a': 'Ana', 'b': 'Boris'});
    final byKey = {for (final event in events) event.key: event};
    expect(byKey['poll:p']!.from, 'a');
    expect(byKey['attack:p']!.from, 'b');
    expect(byKey['stop:s']!.to, isNull);
    expect(byKey['react:f:b:heart']!.to, 'a');
    expect(byKey['react:f:b:heart']!.text, 'Boris reagira na tvoju fotografiju');
    expect(byKey.containsKey('react:f:a:heart'), isFalse);
    expect(byKey['comment:c1']!.to, 'a');
    expect(byKey['comment:c2']!.text, 'Ana odgovara na tvoj komentar');
    expect(byKey['comment:c2']!.to, 'b');
    expect(byKey.containsKey('comment:c3'), isFalse);
  });

  test('encryption matches the example in RFC 8291', () {
    final sealed = encryptPush(
      utf8.encode('When I grow up, I want to be a watermelon'),
      fromBase64Url(
          'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4'),
      fromBase64Url('BTBZMqHH6r4Tts7J_aSIgg'),
      privateKey: fromBase64Url('yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw'),
      salt: fromBase64Url('DGv6ra1nlYgDCS1FRnbzlw'),
    );
    expect(
      toBase64Url(sealed),
      'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIg'
      'Dll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVB'
      'St2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
    );
  });

  test('the sender signature can be checked with the public key', () {
    final key = newPrivateKey();
    final header = vapidHeader('https://push.example/abc', key, 'https://a.example/', DateTime(2027));
    expect(header, startsWith('vapid t='));
    expect(vapidIsValid(header, publicKeyOf(key)), isTrue);
    expect(vapidIsValid(header, publicKeyOf(newPrivateKey())), isFalse);
  });
}
