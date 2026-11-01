import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
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
    el('div', cls: 'label', text: tr('{0} želi na putovanje', [request.name])),
    el('div', cls: 'small', text: [
      if (phone != null && phone.isNotEmpty) phone,
      tr('Prihvatilo: {0} od {1}', [request.approvals.length, trip.approvalsNeeded]),
    ].join(' · ')),
    el('div', attrs: {'style': 'display:flex;gap:8px;margin-top:8px'}, children: [
      chip(given ? tr('Prihvaćeno') : tr('Prihvati'), () {
        if (given) return;
        request.approvals.add(me);
        ui.cloud?.settleGroup(trip);
        ui.changed();
      }, on: given),
      chip(tr('Odbij'), () {
        trip.requests.remove(request);
        ui.changed();
      }),
    ]),
  ]);
}

/// The trips this phone is waiting to enter.
List<web.HTMLElement> waitingNotes(Ui ui) => [
      for (final city in ui.data.waiting.values)
        el('p', cls: 'soft pad gap-top', text: tr('{0}: čeka se da te grupa prihvati.', [city])),
    ];
