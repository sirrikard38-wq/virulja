import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';

/// The title row of a screen; the round buttons float over its corners.
web.HTMLElement topBar(String title, {bool plain = false}) => el(
      'div',
      cls: plain ? 'top plain' : 'top',
      children: [el('h1', cls: 'title', text: title)],
    );

web.HTMLElement sectionTitle(String text) =>
    el('h2', cls: 'section', text: text);

web.HTMLInputElement input({
  String type = 'text',
  String value = '',
  String placeholder = '',
  String? inputMode,
  String? list,
  String? name,
}) =>
    el('input', cls: 'input', attrs: {
      'type': type,
      if (placeholder.isNotEmpty) 'placeholder': placeholder,
      if (inputMode != null) 'inputmode': inputMode,
      if (list != null) 'list': list,
      if (name != null) 'name': name,
      'autocomplete': 'off',
    }) as web.HTMLInputElement
      ..value = value;

/// A number or amount field that brings up the phone's number keys.
web.HTMLInputElement numberInput({String value = '', String placeholder = ''}) =>
    input(value: value, placeholder: placeholder, inputMode: 'decimal');

web.HTMLElement field(String label, web.Node control, {bool tight = false}) =>
    el(
      'label',
      cls: tight ? 'field tight' : 'field',
      children: [web.document.createTextNode(label), control],
    );

web.HTMLSelectElement select<T>(
  List<T> values,
  String Function(T) label, {
  T? selected,
}) {
  final node = el('select', cls: 'input', children: [
    for (var i = 0; i < values.length; i++)
      el('option', text: label(values[i]), attrs: {'value': '$i'}),
  ]) as web.HTMLSelectElement;
  if (selected != null && values.contains(selected)) {
    node.selectedIndex = values.indexOf(selected);
  }
  return node;
}

web.HTMLElement checkbox(String label, web.HTMLInputElement box) =>
    el('label', cls: 'check', children: [box, web.document.createTextNode(label)]);

web.HTMLInputElement checkInput({bool checked = false}) =>
    (el('input', attrs: {'type': 'checkbox'}) as web.HTMLInputElement)
      ..checked = checked;

web.HTMLElement chip(String label, void Function() onTap, {bool on = false}) =>
    button(onTap: onTap, text: label, cls: on ? 'chip on' : 'chip');

/// A folded-away form with a plus in its title.
web.HTMLElement adder(String title, List<web.Node> children) => el(
      'details',
      cls: 'adder',
      children: [
        el('summary', children: [
          icon('plus', size: 20),
          web.document.createTextNode(title),
        ]),
        ...children,
      ],
    );

web.HTMLElement primaryButton(
  String label,
  void Function() onTap, {
  bool wide = true,
}) =>
    button(onTap: onTap, text: label, cls: wide ? 'primary wide' : 'primary');

web.HTMLElement secondaryButton(
  String label,
  void Function() onTap, {
  bool wide = false,
}) =>
    button(onTap: onTap, text: label, cls: wide ? 'secondary wide' : 'secondary');

web.HTMLElement outLink(String label, Uri address) => el(
      'a',
      cls: 'secondary',
      text: label,
      attrs: {'href': '$address', 'target': '_blank', 'rel': 'noopener'},
    );

/// A little "open this link" button at the end of a row.
web.HTMLElement linkIcon(String address, String label) => el(
      'a',
      cls: 'icon-button',
      attrs: {
        'href': address,
        'target': '_blank',
        'rel': 'noopener',
        'aria-label': label,
      },
      children: [icon('link', size: 20)],
    );

web.HTMLElement removeButton(String what, void Function() onConfirmed) => button(
      cls: 'icon-button',
      ariaLabel: tr('Ukloni: {0}', [what]),
      onTap: () {
        if (web.window.confirm(tr('Ukloniti: {0}?', [what]))) onConfirmed();
      },
      children: [icon('close', size: 20)],
    );

web.HTMLElement errorLine() =>
    el('p', cls: 'error', attrs: {'role': 'alert'});

String initials(String name) {
  final letters = name.trim().runes.take(2).toList();
  return String.fromCharCodes(letters).toUpperCase();
}

web.HTMLElement avatar(String name, {bool big = false}) => el(
      'div',
      cls: big ? 'avatar big' : 'avatar',
      text: initials(name),
      attrs: {'aria-hidden': 'true'},
    );

/// The circle of a person of [trip]: their photo, or their initials until there
/// is one.
web.HTMLElement personAvatar(Ui ui, Trip trip, String id, {bool big = false}) {
  final circle = avatar(ui.nameOf(id), big: big);
  final photo = ui.data.personById(id == ui.meIn(trip) ? ui.meId : id)?.photoId;
  if (photo != null) circle.append(storedImage(ui, trip, photo, cls: 'avatar-photo'));
  return circle;
}

/// A stored picture of [trip], which appears as soon as it is read from storage
/// or has arrived from the cloud.
web.HTMLElement storedImage(
  Ui ui,
  Trip trip,
  String id, {
  required String cls,
  String alt = '',
}) {
  final image = el('img', cls: cls, attrs: {'alt': alt});
  ui.imageAddress(trip, id).then((address) {
    if (address != null) image.setAttribute('src', address);
  });
  return image;
}

/// `2.420` with the right word; the small line under a place to stay.
String offerFacts(Offer offer) => [
      if (offer.rating != null) offer.rating!.toString().replaceAll('.', ','),
      if (offer.beachMeters != null) tr('{0} m do plaže', [offer.beachMeters]),
      tr(offer.source),
    ].join(' · ');

/// The perforated stamp on a postcard.
web.Element stamp(String place, int year) {
  final mask = 'stamp-$year-${place.hashCode}';
  return svg('svg', cls: 'stamp', attrs: {
    'viewBox': '0 0 60 74',
    'width': '60',
    'height': '74',
    'aria-hidden': 'true',
  }, children: [
    svg('mask', attrs: {'id': mask}, children: [
      svg('rect', attrs: {'width': '60', 'height': '74', 'fill': '#fff'}),
      svg('rect', attrs: {
        'x': '2',
        'y': '2',
        'width': '56',
        'height': '70',
        'fill': 'none',
        'stroke': '#000',
        'stroke-width': '4',
        'stroke-linecap': 'round',
        'stroke-dasharray': '0.01 6.99',
      }),
    ]),
    svg('rect', attrs: {
      'x': '1',
      'y': '1',
      'width': '58',
      'height': '72',
      'mask': 'url(#$mask)',
      'style': 'fill:var(--card)',
    }),
    svg('text', text: place.length > 5 ? place.substring(0, 5) : place, attrs: {
      'x': '30',
      'y': '36',
      'text-anchor': 'middle',
      'style': 'fill:var(--accent);font-family:var(--display);'
          'font-weight:700;font-size:20px',
    }),
    svg('text', text: '$year', attrs: {
      'x': '30',
      'y': '54',
      'text-anchor': 'middle',
      'style': 'fill:var(--accent);font-family:var(--body);font-size:11px',
    }),
  ]);
}
