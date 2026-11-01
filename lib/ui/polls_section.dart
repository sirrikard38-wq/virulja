import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

web.HTMLElement _pollCard(Ui ui, Trip trip, Poll poll) {
  final me = ui.meIn(trip);
  return el('div', cls: 'poll card', children: [
    el('div', attrs: {'style': 'display:flex;align-items:center'}, children: [
      el('div', cls: 'label grow', text: poll.title),
      removeButton(poll.title, () {
        trip.polls.remove(poll);
        ui.changed();
      }),
    ]),
    el('div', cls: 'checks', attrs: {'style': 'margin:6px 0 0'}, children: [
      for (final option in poll.options)
        chip('${option.time} · ${option.votes.length}', () {
          option.votes.contains(me)
              ? option.votes.remove(me)
              : option.votes.add(me);
          ui.changed();
        }, on: option.votes.contains(me)),
    ]),
    button(
      cls: 'text-button',
      text: poll.active ? 'Makni iz Plana napada' : 'Stavi u Plan napada',
      onTap: () {
        poll.active = !poll.active;
        ui.changed();
      },
    ),
  ]);
}

/// Votes on when to do something: "Na plažu" at 10:00 or 11:30.
web.HTMLElement pollsTab(Ui ui, Trip trip) {
  final day = ui.routeDay.clamp(0, trip.dayCount - 1);
  final polls = trip.polls.where((poll) => poll.dayIndex == day).toList();
  return el('div', children: [
    el('div', cls: 'chips', children: [
      for (var i = 0; i < trip.dayCount; i++)
        chip('Dan ${i + 1}', () {
          ui.routeDay = i;
          ui.rerender();
        }, on: i == day),
    ]),
    if (polls.isEmpty) el('p', cls: 'soft pad', text: 'Za ovaj dan još nema anketa.'),
    for (final poll in polls) _pollCard(ui, trip, poll),
    _newPoll(ui, trip, day),
  ]);
}

/// A new poll: the choices are times, price ranges or locations, as many as
/// wanted; with none it is a plain yes or no.
web.HTMLElement _newPoll(Ui ui, Trip trip, int day) {
  final title = input();
  final choices = <web.HTMLInputElement>[];
  final rows = el('div');
  final error = errorLine();

  web.HTMLElement more(String label, {String type = 'text'}) => button(
        cls: 'text-button',
        text: '+ $label',
        onTap: () {
          final choice = input(type: type);
          choices.add(choice);
          late final web.HTMLElement row;
          row = el('div', cls: 'field', children: [
            el('div', attrs: {'style': 'display:flex;align-items:center;gap:6px'}, children: [
              button(
                cls: 'icon-button',
                ariaLabel: 'Makni: $label',
                onTap: () {
                  choices.remove(choice);
                  row.remove();
                },
                children: [icon('minus', size: 20)],
              ),
              el('span', text: label),
            ]),
            choice,
          ]);
          rows.append(row);
          choice.focus();
        },
      );

  void add() {
    if (title.value.trim().isEmpty) {
      error.textContent = 'Upiši što odlučujete.';
      return;
    }
    final filled = {
      for (final choice in choices)
        if (choice.value.trim().isNotEmpty) choice.value.trim(),
    }.toList();
    final chosen = filled.isEmpty ? ['Da', 'Ne'] : filled;
    trip.polls.add(Poll(
      id: ui.store.newId(),
      title: title.value.trim(),
      dayIndex: day,
      options: [
        for (var i = 0; i < chosen.length; i++)
          PollOption(id: 'o$i', time: chosen[i]),
      ],
    ));
    ui.changed();
  }

  return adder('Nova anketa', [
    field('Što odlučujemo', title),
    rows,
    el('div', attrs: {'style': 'display:flex;flex-wrap:wrap;gap:16px;margin-top:12px'}, children: [
      more('Vrijeme', type: 'time'),
      more('Raspon cijene'),
      more('Lokacija'),
    ]),
    error,
    primaryButton('Napravi anketu', add),
  ]);
}
