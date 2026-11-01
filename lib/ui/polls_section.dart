import 'package:web/web.dart' as web;

import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
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
  ]);
}

/// Votes on when to do something: "Na plažu" at 10:00 or 11:30.
web.HTMLElement pollsSection(Ui ui, Trip trip) => el('div', children: [
      for (final poll in trip.polls) _pollCard(ui, trip, poll),
    ]);

/// A new poll: the choices are times, price ranges or locations, as many as
/// wanted; with none it is a plain yes or no.
web.HTMLElement newPoll(Ui ui, Trip trip) {
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
          rows.append(field(label, choice));
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
