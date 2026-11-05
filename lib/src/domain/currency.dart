/// Currencies: the one a trip's amounts are written in, and one more shown
/// beside them, converted at the day's rate.
library;

class Currency {
  const Currency(this.code, this.sign);

  final String code;

  /// What follows an amount: `12,50 €`, `300 ₺`.
  final String sign;
}

/// What the wheel offers: the euro and its neighbours first, then the rest.
const List<Currency> currencies = [
  Currency('EUR', '€'),
  Currency('USD', r'$'),
  Currency('GBP', '£'),
  Currency('CHF', 'CHF'),
  Currency('TRY', '₺'),
  Currency('BAM', 'KM'),
  Currency('RSD', 'din'),
  Currency('MKD', 'ден'),
  Currency('ALL', 'L'),
  Currency('HUF', 'Ft'),
  Currency('CZK', 'Kč'),
  Currency('PLN', 'zł'),
  Currency('RON', 'lei'),
  Currency('DKK', 'kr'),
  Currency('SEK', 'kr'),
  Currency('NOK', 'kr'),
  Currency('ISK', 'kr'),
  Currency('GEL', '₾'),
  Currency('AED', 'AED'),
  Currency('EGP', 'E£'),
  Currency('MAD', 'MAD'),
  Currency('TND', 'DT'),
  Currency('JPY', '¥'),
  Currency('CNY', '¥'),
  Currency('THB', '฿'),
  Currency('INR', '₹'),
  Currency('KRW', '₩'),
  Currency('IDR', 'Rp'),
  Currency('AUD', r'A$'),
  Currency('CAD', r'C$'),
  Currency('NZD', r'NZ$'),
  Currency('MXN', r'MX$'),
  Currency('BRL', r'R$'),
  Currency('ZAR', 'R'),
  Currency('ILS', '₪'),
  Currency('SGD', r'S$'),
  Currency('HKD', r'HK$'),
  Currency('MYR', 'RM'),
  Currency('PHP', '₱'),
];

Currency currencyOf(String code) =>
    currencies.firstWhere((currency) => currency.code == code, orElse: () => Currency(code, code));

/// At most two, the first the one amounts are written in; never none.
List<String> cleanCurrencies(Iterable<String> codes) {
  final kept = <String>[];
  for (final code in codes) {
    if (code.isNotEmpty && !kept.contains(code) && kept.length < 2) kept.add(code);
  }
  return kept.isEmpty ? ['EUR'] : kept;
}

/// [chosen] after a tap on [code]: a chosen one is let go, unless it is the
/// only one; another is taken while there is room for two. Null when the tap
/// changes nothing, so that the phone can say why.
List<String>? tapCurrency(List<String> chosen, String code) {
  if (chosen.contains(code)) {
    if (chosen.length == 1) return null;
    return [for (final each in chosen) if (each != code) each];
  }
  if (chosen.length >= 2) return null;
  return [...chosen, code];
}

/// [cents] of [from] in [to], with rates as units per euro. Null when a rate
/// is not known yet.
int? convert(int cents, String from, String to, Map<String, double> perEuro) {
  if (from == to) return cents;
  final rateFrom = from == 'EUR' ? 1.0 : perEuro[from];
  final rateTo = to == 'EUR' ? 1.0 : perEuro[to];
  if (rateFrom == null || rateTo == null || rateFrom <= 0) return null;
  return (cents / rateFrom * rateTo).round();
}
