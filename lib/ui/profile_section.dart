import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import 'context.dart';
import 'dom.dart';
import 'media.dart';
import 'widgets.dart';

/// The person's own photo, kept on this phone and sent with the trips. It stands
/// at the top of both settings screens, the app's and a trip's.
web.HTMLElement profilePhoto(Ui ui) {
  final me = ui.data.personById(ui.meId)!;
  final photo = me.photoId;
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
    me.photoId = id;
    if (photo != null) {
      ui.store.removeBlob(photo);
      ui.cloud?.removeProfilePhoto(photo);
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
      el('div', cls: 'small', text: tr('Profilna fotografija')),
      el('label', cls: 'secondary profile-button', children: [
        picker,
        web.document.createTextNode(photo == null ? tr('Dodaj fotografiju') : tr('Promijeni fotografiju')),
      ]),
      if (photo != null)
        el('div', children: [
          button(cls: 'text-button', text: tr('Makni fotografiju'), onTap: () => replace(null)),
        ]),
    ]),
  ]);
}
