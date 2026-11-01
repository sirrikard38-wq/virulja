import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

/// Asks first: only that person can give it up again.
void _giveAdmin(Ui ui, Trip trip, String id) {
  if (web.window.confirm('Dati admina: ${ui.nameOf(id)}?')) {
    trip.adminIds.add(id);
    ui.changed();
  }
}

/// Being an admin can only be given up by that person, and a trip must keep one.
void _stepDown(Ui ui, Trip trip, String me) {
  if (trip.adminIds.length == 1) {
    ui.toast('Prvo daj admina nekome drugome.');
  } else if (web.window.confirm('Maknuti admina sa sebe?')) {
    trip.adminIds.remove(me);
    ui.changed();
  }
}

Future<void> _removeMember(Ui ui, Trip trip, String id) async {
  try {
    await ui.cloud?.removeMember(trip, id);
  } on Object {
    ui.toast('Nema veze. Pokušaj ponovno.');
  }
  ui.rerender();
}

/// One person of the group, the same wherever the group is shown. An admin can
/// make others admins and remove people who are not admins; admins cannot touch
/// each other, only step down themselves.
web.HTMLElement memberRow(Ui ui, Trip trip, String id) {
  final me = ui.meIn(trip);
  final amAdmin = trip.adminIds.contains(me);
  final isAdmin = trip.adminIds.contains(id);
  final canGive = amAdmin && !isAdmin;
  final phone = ui.data.personById(id)?.phone;
  return el('div', cls: 'row', children: [
    avatar(ui.nameOf(id)),
    el('div', cls: 'grow', children: [
      el('div', text: ui.nameOf(id)),
      el('div', cls: 'small', text: [
        if (isAdmin) 'admin',
        if (phone != null && phone.isNotEmpty) phone,
      ].join(' · ')),
    ])
      ..onClick.listen((_) {
        if (canGive) _giveAdmin(ui, trip, id);
      }),
    if (canGive) chip('Daj admina', () => _giveAdmin(ui, trip, id)),
    if (id == me && isAdmin) chip('Makni admina', () => _stepDown(ui, trip, me)),
    if (canGive)
      removeButton(ui.nameOf(id), () => _removeMember(ui, trip, id)),
  ]);
}
