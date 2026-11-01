import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// Someone with the right code, waiting for the group to let them in.
web.HTMLElement requestCard(Ui ui, Trip trip, JoinRequest request) {
  final me = ui.meIn(trip);
  final given = request.approvals.contains(me);
  final phone = request.phone;
  return el('div', cls: 'poll card', children: [
    el('div', cls: 'label', text: '${request.name} želi na putovanje'),
    el('div', cls: 'small', text: [
      if (phone != null && phone.isNotEmpty) phone,
      'Prihvatilo: ${request.approvals.length} od ${trip.approvalsNeeded}',
    ].join(' · ')),
    el('div', attrs: {'style': 'display:flex;gap:8px;margin-top:8px'}, children: [
      chip(given ? 'Prihvaćeno' : 'Prihvati', () {
        if (given) return;
        request.approvals.add(me);
        ui.changed();
      }, on: given),
      chip('Odbij', () {
        trip.requests.remove(request);
        ui.changed();
      }),
    ]),
  ]);
}

/// The trips this phone is waiting to enter.
List<web.HTMLElement> waitingNotes(Ui ui) => [
      for (final city in ui.data.waiting.values)
        el('p', cls: 'soft pad gap-top', text: '$city: čeka se da te grupa prihvati.'),
    ];
