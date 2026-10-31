import 'package:web/web.dart' as web;

/// Tiny DOM builder so view code reads declaratively.
web.HTMLElement el(
  String tag, {
  String? cls,
  String? text,
  Map<String, String> attrs = const {},
  List<web.Node> children = const [],
}) {
  final node = web.document.createElement(tag) as web.HTMLElement;
  if (cls != null) node.className = cls;
  if (text != null) node.textContent = text;
  for (final entry in attrs.entries) {
    node.setAttribute(entry.key, entry.value);
  }
  for (final child in children) {
    node.appendChild(child);
  }
  return node;
}

const String svgNamespace = 'http://www.w3.org/2000/svg';

/// SVG element builder (SVG needs createElementNS).
web.Element svg(
  String tag, {
  String? cls,
  String? text,
  Map<String, String> attrs = const {},
  List<web.Node> children = const [],
}) {
  final node = web.document.createElementNS(svgNamespace, tag);
  if (cls != null) node.setAttribute('class', cls);
  if (text != null) node.textContent = text;
  for (final entry in attrs.entries) {
    node.setAttribute(entry.key, entry.value);
  }
  for (final child in children) {
    node.appendChild(child);
  }
  return node;
}

/// A real <button> with an accessible label.
web.HTMLButtonElement button({
  required void Function() onTap,
  String? text,
  String? cls,
  String? ariaLabel,
  List<web.Node> children = const [],
}) {
  final b = el('button', cls: cls, text: text, attrs: {
    'type': 'button',
    if (ariaLabel != null) 'aria-label': ariaLabel,
  }, children: children) as web.HTMLButtonElement;
  b.onClick.listen((_) => onTap());
  return b;
}

/// Empties [parent] and puts [child] inside.
void show(web.Element parent, web.Node child) {
  parent.textContent = '';
  parent.appendChild(child);
}
