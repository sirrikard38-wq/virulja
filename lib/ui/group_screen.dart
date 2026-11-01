import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'install.dart';
import 'join_screen.dart';
import 'language_section.dart';
import 'media.dart';
import 'notifications_section.dart';
import 'widgets.dart';

/// The person's own photo, kept on this phone and sent with the trips.
web.HTMLElement _profilePhoto(Ui ui, Person me) {
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
      el('label', cls: 'text-button', attrs: {'style': 'cursor:pointer'}, children: [
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

/// This phone's settings: who you are, and how the app looks.
web.HTMLElement groupScreen(Ui ui) {
  final me = ui.data.personById(ui.meId)!;
  final name = input(value: me.name);
  final phone = input(type: 'tel', value: me.phone ?? '');

  final help = installHelp;
  final cloud = ui.cloud;
  return el('div', children: [
    topBar(tr('Postavke'), plain: true),
    _profilePhoto(ui, me),
    field(tr('Ime'), name),
    field(tr('Broj mobitela'), phone),
    primaryButton(tr('Spremi'), () {
      if (name.value.trim().isEmpty) return;
      me
        ..name = name.value.trim()
        ..phone = phone.value.trim();
      ui.changed();
      ui.toast(tr('Spremljeno.'));
    }),
    if (cloud != null) ...[
      if (ui.data.trips.any((trip) => trip.code != null)) ...[
        sectionTitle(tr('Šifre putovanja')),
        for (final trip in ui.data.trips)
          if (trip.code != null) codeRow(trip),
      ],
      el('hr', cls: 'divider'),
      sectionTitle(tr('Imaš šifru putovanja?')),
      codeField(ui),
      if (cloud.reachable)
        el('p', cls: 'small pad gap-top', text: tr('Putovanja se dijele s grupom.')),
    ],
    if (cloud?.pushKey != null) ...[
      sectionTitle(tr('Obavijesti')),
      notificationsSection(ui),
    ],
    sectionTitle(tr('Izgled')),
    el('div', cls: 'chips', attrs: {'style': 'padding-top:2px'}, children: [
      for (final theme in ThemeChoice.values)
        chip(theme.label, () {
          ui.data.theme = theme;
          ui.changed();
        }, on: ui.data.theme == theme),
    ]),
    if (help == InstallHelp.prompt) ...[
      sectionTitle(tr('Aplikacija')),
      el('div', cls: 'pad', children: [
        secondaryButton(tr('Stavi na mobitel'), promptInstall),
      ]),
    ],
    if (help == InstallHelp.ios) ...[
      sectionTitle(tr('Aplikacija')),
      el('p', cls: 'soft pad',
          text: tr('U Safariju dodirni Dijeli, zatim Dodaj na početni zaslon.')),
    ],
    sectionTitle(tr('Jezik')),
    languageChips(ui),
  ]);
}
