import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import '../src/domain/seal.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'media.dart';

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

/// Writes an amount in [box] as amounts are written while it is being typed:
/// 1.250,50, the cursor kept after the same digits.
void typeAmount(web.HTMLInputElement box, web.Event event) {
  final typed = (event as web.InputEvent).data;
  final caret = box.selectionStart ?? box.value.length;
  final next = typedAmount(box.value, caret, dotTyped: typed == '.');
  if (next.text == box.value) return;
  box.value = next.text;
  box.setSelectionRange(next.caret, next.caret);
}

/// Rows that scroll sideways fade on the side where more is hidden, so that it
/// is plain there is more to see. Each row is watched once; [markEdges] runs
/// after every drawing.
void markEdges() {
  if (!_edgesWatched) {
    _edgesWatched = true;
    // A row's scroll does not rise to the page, but the page hears it first.
    web.document.addEventListener(
      'scroll',
      ((web.Event event) {
        final row = event.target as web.Element?;
        final list = row?.classList;
        if (row != null && list != null &&
            (list.contains('chips') || list.contains('show-strip'))) {
          _markRow(row as web.HTMLElement);
        }
      }).toJS,
      true.toJS,
    );
  }
  final rows = web.document.querySelectorAll('.chips, .show-strip');
  for (var i = 0; i < rows.length; i++) {
    final row = rows.item(i) as web.HTMLElement;
    _markRow(row);
    web.window.requestAnimationFrame(((double _) => _markRow(row)).toJS);
  }
}

bool _edgesWatched = false;

/// At the very end of a row there is nothing more on that side: no fade.
void _markRow(web.HTMLElement row) {
  final most = row.scrollWidth - row.clientWidth;
  row.classList.toggle('more-left', row.scrollLeft > 2);
  row.classList.toggle('more-right', most - row.scrollLeft > 2);
}

/// Turns [row] so that its chosen chip stands whole in sight, in the middle
/// when it can; the first and last ones go to their end, where nothing fades.
void showChosenChip(web.HTMLElement row) {
  final chosen = row.querySelector('.chip.on') as web.HTMLElement?;
  if (chosen == null) return;
  row.scrollLeft = chosen.offsetLeft - (row.clientWidth - chosen.offsetWidth) / 2;
  _markRow(row);
}

/// A box for an amount, written as all amounts are while it is typed: 1.250,50.
/// With [fit] it is as wide as the number, three digits at least.
web.HTMLInputElement amountInput({String value = '', bool fit = false}) {
  final box = numberInput(value: value);
  void size() {
    if (!fit) return;
    final ruler = _ruler ??= (web.document.createElement('canvas') as web.HTMLCanvasElement)
        .getContext('2d') as web.CanvasRenderingContext2D;
    ruler.font = web.window.getComputedStyle(box).font;
    final text = box.value.length < 3 ? '000' : box.value;
    box.style.width = '${ruler.measureText(text).width + 52}px';
  }

  box.onInput.listen((event) {
    typeAmount(box, event);
    size();
  });
  box.onChange.listen((_) {
    final cents = parseEuros(box.value);
    if (cents != null) box.value = plainAmount(cents);
    size();
  });
  scheduleMicrotask(size);
  return box;
}

web.CanvasRenderingContext2D? _ruler;

/// Lets [field], on half of its row ([least] of it), grow with the text in
/// [box] up to the whole row; a longer text then scrolls in the box as usual.
web.HTMLElement growWithText(web.HTMLElement field, web.HTMLInputElement box,
    {double least = .5}) {
  void fit() {
    final row = field.parentElement;
    if (row == null || !field.isConnected) return;
    final ruler = _ruler ??= (web.document.createElement('canvas') as web.HTMLCanvasElement)
        .getContext('2d') as web.CanvasRenderingContext2D;
    ruler.font = web.window.getComputedStyle(box).font;
    final need = ruler.measureText(box.value).width + 32;
    final whole = row.clientWidth.toDouble();
    final short = whole * least - 5;
    field.style.flex = '0 0 ${need.clamp(short, whole)}px';
  }

  box.onInput.listen((_) => fit());
  scheduleMicrotask(fit);
  return field;
}

/// The most letters a poll's name may have.
const int longestTitle = 400;

/// A name typed on a line under it: it starts on half its row and grows with
/// the text up to the whole row, then goes on to more lines. At the end of the
/// line it counts the letters, up to [longestTitle]; [quiet] shows the count
/// and the line only while typing. [onInput] hears every letter, [onDone] the
/// name once the keyboard closes.
web.HTMLElement titleField(
  String value, {
  required String label,
  String placeholder = '',
  bool quiet = false,
  void Function(String text)? onInput,
  void Function(String text)? onDone,
}) {
  final area = (el('textarea', cls: 'title-area', attrs: {
    'rows': '1',
    'maxlength': '$longestTitle',
    'aria-label': label,
    'placeholder': placeholder,
    'enterkeyhint': 'done',
  }) as web.HTMLTextAreaElement)
    ..value = value;
  final count = el('span', cls: 'title-count');
  final field = el('div', cls: quiet ? 'title-field quiet' : 'title-field', children: [area, count]);

  void fit() {
    count.textContent = '${area.value.length}/$longestTitle';
    final ruler = _ruler ??= (web.document.createElement('canvas') as web.HTMLCanvasElement)
        .getContext('2d') as web.CanvasRenderingContext2D;
    ruler.font = web.window.getComputedStyle(area).font;
    final text = area.value.isEmpty ? area.placeholder : area.value;
    field.style.width = '${ruler.measureText(text).width + count.offsetWidth + 30}px';
    area.style.height = 'auto';
    area.style.height = '${area.scrollHeight}px';
  }

  area.onInput.listen((_) {
    // One name, no new lines: the text breaks onto them by itself.
    if (area.value.contains('\n')) area.value = area.value.replaceAll('\n', ' ');
    fit();
    onInput?.call(area.value);
  });
  area.onKeyDown.listen((event) {
    if (event.key == 'Enter') {
      event.preventDefault();
      area.blur();
    }
  });
  area.onChange.listen((_) => onDone?.call(area.value.trim()));
  scheduleMicrotask(fit);
  return field;
}

web.HTMLElement field(String label, web.Node control, {bool tight = false}) =>
    el(
      'label',
      cls: tight ? 'field tight' : 'field',
      children: [web.document.createTextNode(label), control],
    );

/// A time picked on two wheels, the hours and the minutes in steps of 5, as a
/// phone shows a list; its own time field would offer every minute. [value]
/// holds it as 08:30, or nothing while no hour is picked.
({web.HTMLElement view, web.HTMLInputElement value}) timePicker() {
  String two(int n) => n.toString().padLeft(2, '0');
  final value = el('input', attrs: {'type': 'hidden'}) as web.HTMLInputElement;
  final hours = el('select', cls: 'input', attrs: {'aria-label': tr('Sati')}, children: [
    el('option', text: '--', attrs: {'value': ''}),
    for (var hour = 0; hour < 24; hour++) el('option', text: two(hour), attrs: {'value': two(hour)}),
  ]) as web.HTMLSelectElement;
  final minutes = el('select', cls: 'input', attrs: {'aria-label': tr('Minute')}, children: [
    for (var minute = 0; minute < 60; minute += 5)
      el('option', text: two(minute), attrs: {'value': two(minute)}),
  ]) as web.HTMLSelectElement;
  void keep() => value.value = hours.value.isEmpty ? '' : '${hours.value}:${minutes.value}';
  hours.onChange.listen((_) => keep());
  minutes.onChange.listen((_) => keep());
  return (
    view: el('span', cls: 'time-picker', children: [hours, el('span', text: ':'), minutes, value]),
    value: value,
  );
}

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

/// A heading with + that folds [body] open, and − while it is open, as
/// Obavijesti does. [key] remembers it in `Ui.openFolds`.
List<web.HTMLElement> foldSection(Ui ui, String key, String title, List<web.HTMLElement> Function() body) {
  final open = ui.openFolds.contains(key);
  return [
    button(
      cls: open ? 'fold open' : 'fold',
      onTap: () {
        open ? ui.openFolds.remove(key) : ui.openFolds.add(key);
        ui.rerender();
      },
      children: [
        icon(open ? 'minus' : 'plus', size: 22),
        el('span', cls: 'section', text: title),
      ],
    )..setAttribute('aria-expanded', '$open'),
    if (open) ...body(),
  ];
}

/// A field with its unit in dark letters at the right, inside the box.
web.HTMLElement unitField(String label, web.HTMLInputElement control, String unit,
        {bool tight = true}) =>
    el('label', cls: tight ? 'field tight' : 'field', children: [
      web.document.createTextNode(label),
      el('span', cls: 'unit-box', children: [
        control..style.paddingRight = 'calc(${unit.length}ch + 18px)',
        el('span', cls: 'unit', text: unit),
      ]),
    ]);

web.HTMLElement checkbox(String label, web.HTMLInputElement box) =>
    el('label', cls: 'check', children: [box, web.document.createTextNode(label)]);

web.HTMLInputElement checkInput({bool checked = false}) =>
    (el('input', attrs: {'type': 'checkbox'}) as web.HTMLInputElement)
      ..checked = checked;

web.HTMLElement chip(String label, void Function() onTap, {bool on = false}) =>
    button(onTap: onTap, text: label, cls: on ? 'chip on' : 'chip');

/// A grey box and grey words; ticked, the words and the tick turn green.
web.HTMLElement tick(String label, bool on, void Function() onTap, {bool locked = false}) =>
    button(
      cls: ['tick', if (on) 'on', if (locked) 'locked'].join(' '),
      onTap: locked ? () {} : onTap,
      children: [
        el('span', cls: 'tick-box', children: [icon('check', size: 18)]),
        el('span', text: label),
      ],
    )
      ..setAttribute('role', 'checkbox')
      ..setAttribute('aria-checked', '$on')
      ..setAttribute('aria-disabled', '$locked');

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

/// Holds the page still behind a box that is open: a finger can no longer
/// scroll it, while it stays exactly where it was. Pinning the page in place
/// instead moved it, and an iPhone at the bottom of a page jolted. A box that
/// is taller than the screen still scrolls itself. Gives what lets it go.
void Function() holdPage() {
  final root = web.document.documentElement! as web.HTMLElement;
  root.classList.add('held');
  final block = ((web.Event event) {
    final target = event.target;
    final card = target != null && target.isA<web.Element>()
        ? (target as web.Element).closest('.sheet-card') as web.HTMLElement?
        : null;
    if (card != null && card.scrollHeight > card.clientHeight) return;
    event.preventDefault();
  }).toJS;
  final options = web.AddEventListenerOptions(passive: false);
  web.document.addEventListener('touchmove', block, options);
  web.document.addEventListener('wheel', block, options);
  return () {
    web.document.removeEventListener('touchmove', block, options);
    web.document.removeEventListener('wheel', block, options);
    root.classList.remove('held');
  };
}

/// Takes [item] out of [list] at once, with a moment to take that back.
/// [also] runs with the removal and gives back what puts the rest as it was.
/// A name that a tap opens for typing, like any text; [rename] hears the new
/// one once the keyboard closes, if it changed and is not empty.
web.HTMLElement editableName(String name, String label, void Function(String name) rename) {
  final field = el('input', cls: 'name-field', attrs: {
    'type': 'text',
    'value': name,
    'aria-label': label,
    'enterkeyhint': 'done',
  }) as web.HTMLInputElement;
  field.onKeyDown.listen((event) {
    if (event.key == 'Enter') field.blur();
    if (event.key == 'Escape') {
      field.value = name;
      field.blur();
    }
  });
  field.onChange.listen((_) {
    final text = field.value.trim();
    if (text.isEmpty || text == name) {
      field.value = name;
      return;
    }
    rename(text);
  });
  return field;
}

web.HTMLElement removeWithUndo<T>(
  Ui ui,
  List<T> list,
  T item,
  String what, {
  void Function() Function()? also,
  bool named = true,
}) =>
    button(
      cls: 'icon-button',
      ariaLabel: tr('Ukloni: {0}', [what]),
      onTap: () {
        final at = list.indexOf(item);
        if (at < 0) return;
        list.removeAt(at);
        final restore = also?.call();
        ui.changed();
        ui.offerUndo(named ? tr('Uklonjeno: {0}', [what]) : tr('Uklonjeno'), () {
          list.insert(min(at, list.length), item);
          restore?.call();
          ui.changed();
        });
      },
      children: [icon('close', size: 20)],
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
  final known = ui.store.knownAddress(id);
  final image = el('img', cls: cls, attrs: {'alt': alt, if (known != null) 'src': known});
  if (known == null) {
    ui.imageAddress(trip, id).then((address) {
      if (address != null) image.setAttribute('src', address);
    });
  }
  return image;
}

/// `2.420` with the right word; the small line under a place to stay.
String offerFacts(Offer offer) => [
      if (offer.rating != null) decimal(offer.rating!),
      if (offer.beachMeters != null) tr('{0} m do plaže', [decimal(offer.beachMeters!)]),
      tr(offer.source),
    ].join(' · ');

/// The round seal on a postcard: the place and, under it, the year, in ink with
/// nothing behind it.
web.Element seal(String place, int year) {
  final lines = sealLines(place);
  final size = min(lines.length == 1 ? 29.0 : 19.0, 66 / lines.map(lettersWide).reduce(max));
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
        'style': 'fill:none;stroke:currentColor',
      });

  return svg('svg', cls: 'seal', attrs: {
    'viewBox': '0 0 100 100',
    'width': '96',
    'height': '96',
    'aria-hidden': 'true',
  }, children: [
    ring(47, 2),
    ring(43.5, 1.3, dots: '.01 3.027'),
    ring(40.5, .7),
    for (var i = 0; i < lines.length; i++)
      svg('text', text: lines[i], attrs: {
        'x': '50',
        'y': '${first + i * lead}',
        'text-anchor': 'middle',
        'style': 'fill:currentColor;font-family:var(--display);'
            'font-weight:700;font-size:${size}px',
      }),
    svg('line', attrs: {
      'x1': '32',
      'x2': '68',
      'y1': '$rule',
      'y2': '$rule',
      'stroke-width': '.8',
      'style': 'stroke:currentColor',
    }),
    svg('text', text: '$year', attrs: {
      'x': '50',
      'y': '${rule + 13}',
      'text-anchor': 'middle',
      'style': 'fill:currentColor;font-family:var(--body);'
          'font-weight:700;font-size:11px;letter-spacing:.16em',
    }),
  ]);
}

/// Which covers are bright under the seal, so that a redraw does not blink.
final Map<String, bool> _brightCovers = {};

/// The photo of a postcard, which gives [mark] the ink that reads on it. The seal
/// waits for the photo the first time, so it never shows in the wrong ink.
web.HTMLElement coverUnderSeal(Ui ui, Trip trip, String cover, web.Element mark) {
  void ink(bool bright) =>
      mark.setAttribute('class', bright ? 'seal on-bright' : 'seal on-dark');

  final image = storedImage(ui, trip, cover, cls: 'postcard-photo', alt: trip.city)
      as web.HTMLImageElement;
  final known = _brightCovers[cover];
  if (known != null) {
    ink(known);
    return image;
  }
  mark.classList.add('waiting');
  image.onLoad.listen((_) {
    try {
      ink(_brightCovers[cover] = sealCornerIsBright(image));
    } on Object {
      ink(false);
    }
  });
  image.onError.listen((_) => ink(false));
  return image;
}
