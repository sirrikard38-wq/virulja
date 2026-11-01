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

web.HTMLElement newPollButton(Ui ui, Trip trip) => button(
      cls: 'secondary wide',
      text: 'Nova anketa',
      onTap: () => ui.go(ui.tripRoute(trip, 'anketa')),
    );

web.HTMLElement newPollScreen(Ui ui, Trip trip) {
  final title = input();
  final times = [input(type: 'time'), input(type: 'time'), input(type: 'time')];
  final error = errorLine();

  void add() {
    final chosen = {
      for (final time in times)
        if (time.value.isNotEmpty) time.value,
    }.toList()
      ..sort();
    if (title.value.trim().isEmpty || chosen.length < 2) {
      error.textContent = 'Upiši naziv i barem dva vremena.';
      return;
    }
    trip.polls.add(Poll(
      id: ui.store.newId(),
      title: title.value.trim(),
      options: [
        for (var i = 0; i < chosen.length; i++)
          PollOption(id: 'o$i', time: chosen[i]),
      ],
    ));
    ui.saved();
    ui.back();
  }

  return el('div', children: [
    topBar('Nova anketa'),
    field('Za što', title),
    el('div', cls: 'fields', children: [
      field('Vrijeme 1', times[0], tight: true),
      field('Vrijeme 2', times[1], tight: true),
    ]),
    field('Vrijeme 3', times[2]),
    error,
    primaryButton('Napravi anketu', add),
  ]);
}
