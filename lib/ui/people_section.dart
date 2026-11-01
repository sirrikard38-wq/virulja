import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// A vote to put [id] out of the group; a second tap takes the vote back.
void _voteToKick(Ui ui, Trip trip, String id) {
  final me = ui.meIn(trip);
  final voters = trip.kickVotes[id] ??= {};
  if (voters.remove(me)) {
    if (voters.isEmpty) trip.kickVotes.remove(id);
  } else if (web.window.confirm(tr('Glasati za izbacivanje: {0}?', [ui.nameOf(id)]))) {
    voters.add(me);
    ui.cloud?.settleGroup(trip);
  } else {
    if (voters.isEmpty) trip.kickVotes.remove(id);
    return;
  }
  ui.changed();
}

/// A vote that is going on, for everyone but the person it is about.
web.HTMLElement kickCard(Ui ui, Trip trip, String id) {
  final voted = trip.kickVotes[id]?.contains(ui.meIn(trip)) ?? false;
  return el('div', cls: 'poll card', children: [
    el('div', cls: 'label', text: tr('Glasanje za izbacivanje: {0}', [ui.nameOf(id)])),
    el('div', cls: 'small',
        text: tr('Glasalo: {0} od {1}', [trip.kickVotesAgainst(id), trip.kickVotesNeeded])),
    el('div', attrs: {'style': 'display:flex;gap:8px;margin-top:8px'}, children: [
      chip(voted ? tr('Povuci glas') : tr('Izbaci'), () => _voteToKick(ui, trip, id),
          on: voted),
    ]),
  ]);
}

/// One person of the group, the same wherever the group is shown. Everyone has
/// the same rights: anyone can vote anyone else out.
web.HTMLElement memberRow(Ui ui, Trip trip, String id) {
  final me = ui.meIn(trip);
  final phone = ui.data.personById(id)?.phone;
  return el('div', cls: 'row', children: [
    personAvatar(ui, trip, id),
    el('div', cls: 'grow', children: [
      el('div', text: ui.nameOf(id)),
      if (phone != null && phone.isNotEmpty) el('div', cls: 'small', text: phone),
      if (id != me)
        el('div', attrs: {'style': 'margin-top:6px'}, children: [
          chip(
            tr('Izbaci · {0}/{1}', [trip.kickVotesAgainst(id), trip.kickVotesNeeded]),
            () => _voteToKick(ui, trip, id),
            on: trip.kickVotes[id]?.contains(me) ?? false,
          ),
        ]),
    ]),
  ]);
}
