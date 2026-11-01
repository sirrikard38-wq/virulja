import 'package:web/web.dart' as web;

import '../src/domain/format.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'dom.dart';
import 'icons.dart';

const _months = [
  'Siječanj', 'Veljača', 'Ožujak', 'Travanj', 'Svibanj', 'Lipanj',
  'Srpanj', 'Kolovoz', 'Rujan', 'Listopad', 'Studeni', 'Prosinac',
];

/// One calendar for the whole trip: the first tap is the start, the second the
/// end. A tap after that starts a new period.
class RangePicker {
  RangePicker({this.start, this.end}) {
    final first = start ?? today();
    _month = dayOf(first.year, first.month, 1);
    _draw();
  }

  DateTime? start;
  DateTime? end;
  late DateTime _month;

  final web.HTMLElement element = el('div');

  void _pick(DateTime day) {
    final from = start;
    if (from == null || end != null) {
      start = day;
      end = null;
    } else if (day.isBefore(from)) {
      start = day;
      end = from;
    } else {
      end = day;
    }
    _draw();
  }

  void _shift(int months) {
    _month = dayOf(_month.year, _month.month + months, 1);
    _draw();
  }

  web.HTMLElement _dayButton(DateTime day) {
    final from = start, to = end;
    final edge = day == from || day == to;
    final inside =
        from != null && to != null && day.isAfter(from) && day.isBefore(to);
    return button(
      text: '${day.day}',
      cls: edge ? 'edge' : (inside ? 'inside' : null),
      onTap: () => _pick(day),
    );
  }

  void _draw() {
    final from = start, to = end;
    final length = dayOf(_month.year, _month.month + 1, 0).day;
    final summary = from == null
        ? tr('Odaberi polazak')
        : to == null
            ? '${dayAndMonth(from)}: ${tr('Odaberi povratak')}'
            : dateRange(from, to);
    show(
      element,
      el('div', children: [
        el('p', cls: 'label pad gap-top', text: summary),
        el('div', cls: 'calendar card', children: [
          el('div', cls: 'calendar-head', children: [
            button(cls: 'icon-button', ariaLabel: tr('Prethodni mjesec'), onTap: () => _shift(-1), children: [icon('back')]),
            el('span', cls: 'label', text: '${tr(_months[_month.month - 1])} ${_month.year}'),
            button(cls: 'icon-button', ariaLabel: tr('Sljedeći mjesec'), onTap: () => _shift(1), children: [icon('send')]),
          ]),
          el('div', cls: 'calendar-days', children: [
            for (final name in weekdayLetters)
              el('span', cls: 'small', text: name),
            for (var i = 1; i < _month.weekday; i++) el('span'),
            for (var d = 1; d <= length; d++)
              _dayButton(dayOf(_month.year, _month.month, d)),
          ]),
        ]),
      ]),
    );
  }
}
