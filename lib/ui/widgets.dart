import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
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
  final photo = ui.photoIn(trip, id);
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

/// About how wide [line] is in the display font, in font sizes.
double _lettersWide(String line) => line.split('').fold(
    0, (width, letter) => width + (letter == letter.toLowerCase() ? .44 : .72));

/// The round seal on a postcard: the place and, under it, the year.
web.Element seal(String place, int year) {
  final lines = sealLines(place);
  final size = min(lines.length == 1 ? 29.0 : 19.0, 66 / lines.map(_lettersWide).reduce(max));
  final lead = lines.length == 1 ? 0.0 : 1.08 * size;
  // The name, the rule and the year stand together in the middle of the circle.
  final first = 40 + (.63 * size - lead) / 2;
  final rule = first + lead + 7;

  web.Element ring(double radius, double width, {String? dots}) => svg('circle', attrs: {
        'cx': '50',
        'cy': '50',
        'r': '$radius',
        'stroke-width': '$width',
        if (dots != null) 'stroke-linecap': 'round',
        if (dots != null) 'stroke-dasharray': dots,
        'style': 'fill:none;stroke:var(--accent)',
      });

  return svg('svg', cls: 'seal', attrs: {
    'viewBox': '0 0 100 100',
    'width': '96',
    'height': '96',
    'aria-hidden': 'true',
  }, children: [
    svg('circle', attrs: {
      'cx': '50',
      'cy': '50',
      'r': '49',
      'fill-opacity': '.9',
      'style': 'fill:var(--card)',
    }),
    ring(47, 2),
    ring(43.5, 1.3, dots: '.01 3.027'),
    ring(40.5, .7),
    for (var i = 0; i < lines.length; i++)
      svg('text', text: lines[i], attrs: {
        'x': '50',
        'y': '${first + i * lead}',
        'text-anchor': 'middle',
        'style': 'fill:var(--accent);font-family:var(--display);'
            'font-weight:700;font-size:${size}px',
      }),
    svg('line', attrs: {
      'x1': '32',
      'x2': '68',
      'y1': '$rule',
      'y2': '$rule',
      'stroke-width': '.8',
      'style': 'stroke:var(--accent)',
    }),
    svg('text', text: '$year', attrs: {
      'x': '50',
      'y': '${rule + 13}',
      'text-anchor': 'middle',
      'style': 'fill:var(--accent);font-family:var(--body);'
          'font-weight:700;font-size:11px;letter-spacing:.16em',
    }),
  ]);
}
