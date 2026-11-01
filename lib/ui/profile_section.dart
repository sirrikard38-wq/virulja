import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'media.dart';
import 'widgets.dart';

/// The person's own photo, kept on this phone and sent with the trips. The app's
/// settings hold the general one; a [trip]'s settings hold one for that trip only,
/// which goes back to the general one when removed.
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
        web.document.createTextNode(photo == null ? tr('Dodaj fotografiju') : tr('Promijeni fotografiju')),
      ]),
      if (own != null)
        el('div', children: [
          button(
            cls: 'text-button',
            text: trip == null ? tr('Makni fotografiju') : tr('Koristi opću fotografiju'),
            onTap: () => replace(null),
          ),
        ]),
    ]),
  ]);
}
