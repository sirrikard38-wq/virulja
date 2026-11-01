import 'dart:js_interop';

import '../src/domain/countries.dart';
import '../src/domain/i18n.dart';

/// The browser's own translation of country names.
@JS('Intl.DisplayNames')
extension type _DisplayNames._(JSObject _) implements JSObject {
  external factory _DisplayNames(JSArray<JSString> locales, JSObject options);

  external String? of(String code);
}

/// The countries of the world in the current language, for the country field.
List<String> countryNames() {
  if (language == Language.hr) return countries;
  try {
    final names = _DisplayNames(
      [language.name.toJS].toJS,
      {'type': 'region'}.jsify() as JSObject,
    );
    return [
      for (final code in countryCodes.split(' ')) names.of(code) ?? code,
    ]..sort();
  } on Object {
    return countries;
  }
}
