import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'media.dart';
import 'widgets.dart';

const int _undoSeconds = 10;

/// A trip's own photo just given up, which can still be taken back.
class _PhotoUndo {
  _PhotoUndo(this.trip, this.photo);

  final Trip trip;
  final String photo;
  late final Timer timer;
  int left = _undoSeconds;
}

_PhotoUndo? _undo;

/// The time is up, or something else happened: the photo is gone for good.
void _finishUndo(Ui ui) {
  final undo = _undo;
  if (undo == null) return;
  _undo = null;
  undo.timer.cancel();
  ui.store.removeBlob(undo.photo);
  ui.cloud?.removeBlob(undo.trip, undo.photo);
  // Written in place: a redraw would wipe what is being typed on this screen.
  web.document.querySelector('.photo-undo')
    ?..textContent = tr('Koristi se opća fotografija')
    ..className = 'small';
}

/// Goes back to the general photo, keeping the trip's own for a few seconds.
void _useGeneral(Ui ui, Trip trip, String own) {
  _finishUndo(ui);
  ui.data.tripPhotos.remove(trip.id);
  final undo = _PhotoUndo(trip, own);
  undo.timer = Timer.periodic(const Duration(seconds: 1), (_) {
    undo.left--;
    if (undo.left <= 0) {
      _finishUndo(ui);
    } else {
      web.document.querySelector('.photo-countdown')?.textContent = '${undo.left}';
    }
  });
  _undo = undo;
  ui.changed();
}

void _takeBack(Ui ui) {
  final undo = _undo;
  if (undo == null) return;
  _undo = null;
  undo.timer.cancel();
  ui.data.tripPhotos[undo.trip.id] = undo.photo;
  ui.changed();
}

/// The person's own photo, kept on this phone and sent with the trips. The app's
/// settings hold the general one; a [trip]'s settings hold one for that trip only,
/// which goes back to the general one when removed. The two never change each
/// other; a trip without its own simply shows the general one.
web.HTMLElement profilePhoto(Ui ui, {Trip? trip}) {
  final me = ui.data.personById(ui.meId)!;
  final own = trip == null ? me.photoId : ui.data.tripPhotos[trip.id];
  final photo = own ?? me.photoId;
  final circle = el('div', cls: 'avatar big profile', text: initials(me.name),
      attrs: {'aria-hidden': 'true'});
  if (photo != null) {
    final image = el('img', cls: 'avatar-photo', attrs: {'alt': ''});
    circle.append(image);
    ui.store.blobAddress(photo).then((address) {
      if (address != null) image.setAttribute('src', address);
    });
  }

  void replace(String? id) {
    _finishUndo(ui);
    if (trip == null) {
      me.photoId = id;
    } else if (id == null) {
      ui.data.tripPhotos.remove(trip.id);
    } else {
      ui.data.tripPhotos[trip.id] = id;
    }
    if (own != null) {
      ui.store.removeBlob(own);
      if (trip == null) {
        ui.cloud?.removeProfilePhoto(own);
      } else {
        ui.cloud?.removeBlob(trip, own);
      }
    }
    ui.changed();
  }

  final picker = el('input', cls: 'file', attrs: {
    'type': 'file',
    'accept': 'image/*',
  }) as web.HTMLInputElement;
  picker.onChange.listen((_) async {
    final files = pickedFiles(picker);
    if (files.isEmpty) return;
    try {
      final id = ui.store.newId();
      await storeAvatar(ui.store, id, files.first);
      replace(id);
    } on Object {
      ui.toast(tr('Tu fotografiju ne mogu pročitati.'));
    }
  });
  return el('div', cls: 'row', attrs: {'style': 'border:0'}, children: [
    circle,
    el('div', cls: 'grow', children: [
      el('div', cls: 'small',
          text: trip == null ? tr('Profilna fotografija') : tr('Profilna fotografija za ovo putovanje')),
      el('label', cls: 'secondary profile-button', children: [
        picker,
        web.document.createTextNode(switch ((trip != null, own != null, photo != null)) {
          (true, false, _) => tr('Dodaj za ovo putovanje'),
          (_, _, true) => tr('Promijeni fotografiju'),
          _ => tr('Dodaj fotografiju'),
        }),
      ]),
      if (trip != null && own == null)
        if (_undo?.trip.id == trip.id)
          el('div', cls: 'photo-undo', children: [
            button(
              cls: 'text-button',
              text: tr('Vrati natrag profilnu'),
              onTap: () => _takeBack(ui),
            ),
            el('span', cls: 'photo-countdown', text: '${_undo!.left}'),
          ])
        else
          el('div', cls: 'small', attrs: {'style': 'margin-top:6px'},
              text: tr('Koristi se opća fotografija')),
      if (own != null)
        el('div', children: [
          button(
            cls: 'text-button',
            text: trip == null ? tr('Makni fotografiju') : tr('Koristi opću fotografiju'),
            onTap: () => trip == null ? replace(null) : _useGeneral(ui, trip, own),
          ),
        ]),
    ]),
  ]);
}
