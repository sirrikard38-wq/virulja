/// How numbers and dates read in Croatian.
library;

const _monthsOf = [
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

const _weekdays = [
  'ponedjeljak',
  'utorak',
  'srijeda',
  'četvrtak',
  'petak',
  'subota',
  'nedjelja',
];

/// `12. lipnja`
String dayAndMonth(DateTime day) => '${day.day}. ${_monthsOf[day.month - 1]}';

/// `subota, 12. lipnja`
String weekdayAndDate(DateTime day) =>
    '${_weekdays[day.weekday - 1]}, ${dayAndMonth(day)}';

/// `12.–16. lipnja`, `28. lipnja – 3. srpnja`, `30. prosinca 2026. – 2. siječnja 2027.`
String dateRange(DateTime start, DateTime end) {
  if (start.year != end.year) {
    return '${dayAndMonth(start)} ${start.year}. – '
        '${dayAndMonth(end)} ${end.year}.';
  }
  if (start.month != end.month) {
    return '${dayAndMonth(start)} – ${dayAndMonth(end)}';
  }
  if (start.day == end.day) return dayAndMonth(start);
  return '${start.day}.–${dayAndMonth(end)}';
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

String photosCount(int n) =>
    '$n ${plural(n, 'fotografija', 'fotografije', 'fotografija')}';

String peopleCount(int n) => '$n ${plural(n, 'osoba', 'osobe', 'osoba')}';

String songsCount(int n) => '$n ${plural(n, 'pjesma', 'pjesme', 'pjesama')}';

String nightsCount(int n) => '$n ${plural(n, 'noć', 'noći', 'noći')}';

/// `za 224 dana`, `sutra`, `danas`
String daysUntil(DateTime from, DateTime to) {
  final days = to.difference(from).inDays;
  if (days == 0) return 'danas';
  if (days == 1) return 'sutra';
  return 'za $days ${days % 100 != 11 && days % 10 == 1 ? 'dan' : 'dana'}';
}

/// `upravo`, `prije 5 min`, `prije 3 h`, `jučer`, `prije 4 dana`
String ago(DateTime at, DateTime now) {
  final passed = now.difference(at);
  if (passed.inMinutes < 1) return 'upravo';
  if (passed.inHours < 1) return 'prije ${passed.inMinutes} min';
  if (passed.inDays < 1) return 'prije ${passed.inHours} h';
  if (passed.inDays == 1) return 'jučer';
  return 'prije ${passed.inDays} dana';
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
  if (amount == null || amount < 0) return null;
  return (amount * 100).round();
}
