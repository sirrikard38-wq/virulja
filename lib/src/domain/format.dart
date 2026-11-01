/// How numbers and dates read in each language.
library;

import 'dart:math';

import 'i18n.dart';

const _monthsHr = [
  'siječnja',
  'veljače',
  'ožujka',
  'travnja',
  'svibnja',
  'lipnja',
  'srpnja',
  'kolovoza',
  'rujna',
  'listopada',
  'studenoga',
  'prosinca',
];

const _monthsEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _monthsTr = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

const _weekdaysHr = [
  'ponedjeljak',
  'utorak',
  'srijeda',
  'četvrtak',
  'petak',
  'subota',
  'nedjelja',
];

const _weekdaysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _weekdaysTr = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

/// The first letters of the days of the week, from Monday.
List<String> get weekdayLetters => switch (language) {
      Language.hr => const ['P', 'U', 'S', 'Č', 'P', 'S', 'N'],
      Language.en => const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
      Language.tr => const ['P', 'S', 'Ç', 'P', 'C', 'C', 'P'],
    };

String _month(DateTime day) => switch (language) {
      Language.hr => _monthsHr[day.month - 1],
      Language.en => _monthsEn[day.month - 1],
      Language.tr => _monthsTr[day.month - 1],
    };

/// A number that stands for a day of the month before something: `12.` in
/// Croatian, `12` otherwise.
String _dayNumber(DateTime day) =>
    language == Language.hr ? '${day.day}.' : '${day.day}';

/// `12. lipnja`, `12 June`, `12 Haziran`
String dayAndMonth(DateTime day) => '${_dayNumber(day)} ${_month(day)}';

/// `subota, 12. lipnja`, `Saturday, 12 June`, `12 Haziran Cumartesi`
String weekdayAndDate(DateTime day) => switch (language) {
      Language.hr => '${_weekdaysHr[day.weekday - 1]}, ${dayAndMonth(day)}',
      Language.en => '${_weekdaysEn[day.weekday - 1]}, ${dayAndMonth(day)}',
      Language.tr => '${dayAndMonth(day)} ${_weekdaysTr[day.weekday - 1]}',
    };

/// `12.–16. lipnja`, `28. lipnja – 3. srpnja`, `30. prosinca 2026. – 2. siječnja 2027.`
String dateRange(DateTime start, DateTime end) {
  final dot = language == Language.hr ? '.' : '';
  if (start.year != end.year) {
    return '${dayAndMonth(start)} ${start.year}$dot – '
        '${dayAndMonth(end)} ${end.year}$dot';
  }
  if (start.month != end.month) {
    return '${dayAndMonth(start)} – ${dayAndMonth(end)}';
  }
  if (start.day == end.day) return dayAndMonth(start);
  return '${_dayNumber(start)}–${dayAndMonth(end)}';
}

/// Picks the Croatian word for a count: 1 [one], 2-4 [few], otherwise [many].
/// Numbers ending in 11-14 always take [many].
String plural(int count, String one, String few, String many) {
  final lastTwo = count.abs() % 100;
  final last = lastTwo % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return many;
  if (last == 1) return one;
  if (last >= 2 && last <= 4) return few;
  return many;
}

/// `3 osobe`, `3 people`, `3 kişi`: Turkish keeps one form after a number.
String _count(int n, (String, String, String) croatian, String english, String englishMany, String turkish) =>
    switch (language) {
      Language.hr => '$n ${plural(n, croatian.$1, croatian.$2, croatian.$3)}',
      Language.en => '$n ${n == 1 ? english : englishMany}',
      Language.tr => '$n $turkish',
    };

String photosCount(int n) =>
    _count(n, ('fotografija', 'fotografije', 'fotografija'), 'photo', 'photos', 'fotoğraf');

String peopleCount(int n) =>
    _count(n, ('osoba', 'osobe', 'osoba'), 'person', 'people', 'kişi');

String songsCount(int n) =>
    _count(n, ('pjesma', 'pjesme', 'pjesama'), 'song', 'songs', 'şarkı');

String nightsCount(int n) => _count(n, ('noć', 'noći', 'noći'), 'night', 'nights', 'gece');

String daysCount(int n) => _count(n, ('dan', 'dana', 'dana'), 'day', 'days', 'gün');

/// `za 224 dana`, `sutra`, `danas`
String daysUntil(DateTime from, DateTime to) {
  final days = to.difference(from).inDays;
  return switch (language) {
    Language.hr => days == 0
        ? 'danas'
        : days == 1
            ? 'sutra'
            : 'za $days ${days % 100 != 11 && days % 10 == 1 ? 'dan' : 'dana'}',
    Language.en => days == 0
        ? 'today'
        : days == 1
            ? 'tomorrow'
            : 'in $days days',
    Language.tr => days == 0
        ? 'bugün'
        : days == 1
            ? 'yarın'
            : '$days gün sonra',
  };
}

/// `upravo`, `prije 5 min`, `prije 3 h`, `jučer`, `prije 4 dana`
String ago(DateTime at, DateTime now) {
  final passed = now.difference(at);
  final minutes = passed.inMinutes, hours = passed.inHours, days = passed.inDays;
  return switch (language) {
    Language.hr => minutes < 1
        ? 'upravo'
        : hours < 1
            ? 'prije $minutes min'
            : days < 1
                ? 'prije $hours h'
                : days == 1
                    ? 'jučer'
                    : 'prije $days dana',
    Language.en => minutes < 1
        ? 'just now'
        : hours < 1
            ? '$minutes min ago'
            : days < 1
                ? '$hours h ago'
                : days == 1
                    ? 'yesterday'
                    : '$days days ago',
    Language.tr => minutes < 1
        ? 'az önce'
        : hours < 1
            ? '$minutes dk önce'
            : days < 1
                ? '$hours sa önce'
                : days == 1
                    ? 'dün'
                    : '$days gün önce',
  };
}

/// `2.420 €`, `12,50 €`, `−8 €`
String euros(int cents) {
  final sign = cents < 0 ? '−' : '';
  final whole = (cents.abs() ~/ 100).toString();
  final rest = cents.abs() % 100;
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) grouped.write('.');
    grouped.write(whole[i]);
  }
  final fraction = rest == 0 ? '' : ',${rest.toString().padLeft(2, '0')}';
  return '$sign$grouped$fraction €';
}

/// `10–30 €`, `7,50–12 €`
String eurosRange(int low, int high) =>
    '${euros(low).replaceAll(' €', '')}–${euros(high)}';

/// Reads a price per person: one amount or a range, such as `10-30`. A range counts
/// as the amount in the middle of it and keeps its ends to show. Returns null when
/// it is not a price.
({int middle, int? low, int? high})? parsePriceRange(String text) {
  final parts = text.split(RegExp(r'[-–—−]+'));
  if (parts.length > 2) return null;
  final first = parseEuros(parts.first);
  final last = parseEuros(parts.last);
  if (first == null || last == null) return null;
  if (first == last) return (middle: first, low: null, high: null);
  return (
    middle: ((first + last) / 2).round(),
    low: min(first, last),
    high: max(first, last),
  );
}

/// Reads an amount as people type it: `12`, `12,5`, `1.200`, `1.200,50`,
/// `12.50 €`. Returns cents, or null when it is not an amount.
int? parseEuros(String text) {
  var value = text.replaceAll(RegExp(r'[\s€]'), '');
  if (value.isEmpty) return null;
  if (value.contains(',')) {
    value = value.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(value)) {
    value = value.replaceAll('.', '');
  }
  final amount = double.tryParse(value);
  if (amount == null || amount < 0 || !amount.isFinite) return null;
  return (amount * 100).round();
}
