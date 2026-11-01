import 'package:web/web.dart' as web;

import '../src/domain/i18n.dart';
import 'context.dart';
import 'dom.dart';
import 'widgets.dart';

void chooseLanguage(Ui ui, Language choice) {
  ui.data.chosenLanguage = choice;
  language = choice;
  ui.store.save();
  ui.cloud?.languageChanged();
  ui.rerender();
}

/// The choice of language at the bottom of the settings.
web.HTMLElement languageChips(Ui ui) => el('div', cls: 'chips', attrs: {
      'style': 'padding-top:2px',
    }, children: [
      for (final choice in Language.values)
        chip(choice.label, () => chooseLanguage(ui, choice), on: choice == language),
    ]);
