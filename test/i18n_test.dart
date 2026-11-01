import 'dart:io';

import 'package:test/test.dart';
import 'package:virulja/src/domain/format.dart';
import 'package:virulja/src/domain/i18n.dart';
import 'package:virulja/src/domain/models.dart';

void main() {
  tearDown(() => language = Language.hr);

  /// Every text the code passes to [tr].
  Set<String> textsInCode() {
    final found = <String>{};
    final pattern = RegExp(r"\btr\(\s*'((?:[^'\\]|\\.)*)'");
    for (final folder in ['lib', 'tool']) {
      for (final file in Directory(folder).listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        if (file.path.endsWith('i18n.dart')) continue;
        for (final match in pattern.allMatches(file.readAsStringSync())) {
          found.add(match.group(1)!.replaceAll(r"\'", "'"));
        }
      }
    }
    return found;
  }

  test('every text in the code has English and Turkish', () {
    final texts = textsInCode();
    expect(texts, isNotEmpty);
    expect(texts.where((text) => !isTranslated(text)), isEmpty);
  });

  test('translations keep what goes into a text', () {
    for (final text in textsInCode()) {
      final holes = RegExp(r'\{\d\}').allMatches(text).map((m) => m[0]).toSet();
      for (final translation in translationsOf(text) ?? const <String>[]) {
        expect(RegExp(r'\{\d\}').allMatches(translation).map((m) => m[0]).toSet(), holes,
            reason: text);
      }
    }
  });

  test('the visible screens have no Croatian left outside tr', () {
    const words = r'(Dodaj|Upiši|Obriši|Još|Nema |Šifra|Odaberi|Makni|putovanj|Spremi)';
    final literal = RegExp("(?<!tr\\()(?<!tr\\(\\s)'[^'\\n]*$words[^'\\n]*'");
    final left = <String>[];
    for (final file in Directory('lib/ui').listSync()) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final line in file.readAsLinesSync()) {
        if (line.trimLeft().startsWith('//')) continue;
        if (literal.hasMatch(line)) left.add(line.trim());
      }
    }
    expect(left, isEmpty);
  });

  test('a text takes what goes into it, in the right language', () {
    expect(tr('Dan {0}', [2]), 'Dan 2');
    language = Language.en;
    expect(tr('Dan {0}', [2]), 'Day 2');
    language = Language.tr;
    expect(tr('Dan {0}', [2]), '2. gün');
    expect(tr('Nešto novo'), 'Nešto novo');
  });

  test('dates and counts read right in each language', () {
    final start = dayOf(2027, 6, 12);
    final end = dayOf(2027, 6, 16);
    expect(dateRange(start, end), '12.–16. lipnja');
    language = Language.en;
    expect(dateRange(start, end), '12–16 June');
    expect(weekdayAndDate(start), 'Saturday, 12 June');
    expect(peopleCount(1), '1 person');
    expect(peopleCount(3), '3 people');
    expect(daysUntil(start, end), 'in 4 days');
    language = Language.tr;
    expect(dateRange(start, end), '12–16 Haziran');
    expect(weekdayAndDate(start), '12 Haziran Cumartesi');
    expect(peopleCount(3), '3 kişi');
    expect(daysUntil(start, end), '4 gün sonra');
  });

  test('the chosen language is remembered', () {
    final data = AppData(chosenLanguage: Language.tr, kindOrder: {
      't': ['winery', 'cafe'],
    });
    final back = AppData.fromJson(data.toJson());
    expect(back.chosenLanguage, Language.tr);
    expect(back.kindOrder['t'], ['winery', 'cafe']);
  });

  test('labels follow the language', () {
    language = Language.en;
    expect(PlaceKind.cafe.label, 'Cafés');
    expect(CostCategory.values.first.label, 'Stay');
  });

  test('every kind of place has its estimate in each language', () {
    expect(PlaceKind.beachBar.estimateTitle, 'Procjena za beach bar');
    for (final other in [Language.en, Language.tr]) {
      language = other;
      for (final kind in PlaceKind.values) {
        expect(kind.estimateTitle, isNot(contains('Procjena')));
      }
    }
  });
}
