import 'dart:async';

import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'widgets.dart';

/// Casts or takes back the vote of [me]. The vote that makes the whole group say
/// Da ticks the poll's Plan napada, which puts it there.
void _vote(Ui ui, Trip trip, Poll poll, PollOption option, String me) {
  final had = option.votes.contains(me);
  if (onlyOneAnswer(poll)) {
    for (final other in poll.options) {
      other.votes.remove(me);
    }
  } else {
    option.votes.remove(me);
  }
  if (!had) option.votes.add(me);
  if (addWholeYeses(trip, me).isNotEmpty) ui.toast(tr('Izglasano! Dodano u Plan napada.'));
  ui.changed();
}

/// One more answer to vote for, typed in the poll's card. A yes or no stays one
/// answer per person.
web.HTMLElement _optionForm(Ui ui, Trip trip, Poll poll) {
  final answer = input(placeholder: tr('Nova mogućnost'));
  void close() {
    ui.addingOption = null;
    ui.rerender();
  }

  void add() {
    final text = answer.value.trim();
    if (text.isEmpty) return;
    if (poll.options.any((option) => tr(option.time).toLowerCase() == text.toLowerCase())) {
      ui.toast(tr('Ta mogućnost već postoji.'));
      return;
    }
    if (poll.options.length >= mostOptions) return;
    if (onlyOneAnswer(poll)) poll.single = true;
    // Kept in order by its id, after the ones before it.
    poll.options.add(PollOption(id: 'o${poll.options.length}${ui.store.newId()}', time: text));
    ui.addingOption = null;
    ui.changed();
  }

  answer.onKeyDown.listen((event) {
    if (event.key == 'Enter') add();
    if (event.key == 'Escape') close();
  });
  scheduleMicrotask(() => answer.focus());
  return el('div', cls: 'option-form', children: [
    el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [answer]),
    button(cls: 'text-button', text: tr('Dodaj'), onTap: add),
    button(cls: 'icon-button', ariaLabel: tr('Odustani'), onTap: close, children: [icon('close', size: 18)]),
  ]);
}

web.HTMLElement _pollCard(Ui ui, Trip trip, Poll poll) {
  final me = ui.meIn(trip);
  final inAttack = pollInAttack(trip, poll);
  return el('div', cls: 'poll card', children: [
    el('div', attrs: {'style': 'display:flex;align-items:center'}, children: [
      el('div', cls: 'grow', children: [
        el('div', cls: 'label', text: poll.title),
      ]),
      removeWithUndo(ui, trip.polls, poll, poll.title),
    ]),
    el('div', cls: 'checks', attrs: {'style': 'margin:6px 0 0'}, children: [
      for (final option in poll.options)
        chip('${tr(option.time)} · ${option.votes.length}',
            () => _vote(ui, trip, poll, option, me),
            on: option.votes.contains(me)),
      if (poll.options.length < mostOptions && ui.addingOption != poll.id)
        button(
          cls: 'icon-button more-option',
          ariaLabel: tr('Dodaj mogućnost za glasanje'),
          onTap: () {
            ui.addingOption = poll.id;
            ui.rerender();
          },
          children: [icon('plus', size: 22)],
        ),
    ]),
    if (ui.addingOption == poll.id) _optionForm(ui, trip, poll),
    el('div', attrs: {'style': 'margin-top:6px'}, children: [
      tick(tr('Plan napada'), inAttack, () {
        setPollInAttack(trip, poll, !inAttack, me);
        ui.changed();
      }),
    ]),
  ]);
}

/// Votes on what to do and when: "Na plažu" at 10:00 or 11:30. The days are
/// picked in Plan napada.
web.HTMLElement pollsTab(Ui ui, Trip trip) {
  return el('div', children: [
    _newPoll(ui, trip)..classList.add('on-top'),
    if (trip.polls.isEmpty) el('p', cls: 'soft pad gap-top', text: tr('Još nema anketa.')),
    for (final poll in trip.polls) _pollCard(ui, trip, poll),
  ]);
}

/// A yes, no or maybe poll on [title], one answer per person.
void addYesNoPoll(Ui ui, Trip trip, String title) {
  const answers = ['Da', 'Ne', 'Možda'];
  trip.polls.add(Poll(
    id: ui.store.newId(),
    title: title,
    dayIndex: -1,
    single: true,
    addedBy: ui.meIn(trip),
    options: [
      for (var i = 0; i < answers.length; i++)
        PollOption(id: 'o$i', time: answers[i]),
    ],
  ));
  ui.toast(tr('Dodano u Ankete.'));
}

/// A new poll: the choices are times, price ranges or locations, as many as
/// wanted; with none it is a plain yes or no.
web.HTMLElement _newPoll(Ui ui, Trip trip) {
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
                ariaLabel: tr('Makni: {0}', [label]),
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
      error.textContent = tr('Upiši što odlučujete.');
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
      dayIndex: -1,
      addedBy: ui.meIn(trip),
      options: [
        for (var i = 0; i < chosen.length; i++)
          PollOption(id: 'o$i', time: chosen[i]),
      ],
    ));
    ui.changed();
  }

  return adder(tr('Nova anketa'), [
    field(tr('Što odlučujemo'), title),
    rows,
    el('div', attrs: {'style': 'display:flex;flex-wrap:wrap;gap:16px;margin-top:12px'}, children: [
      more(tr('Vrijeme'), type: 'time'),
      more(tr('Raspon cijene')),
      more(tr('Lokacija')),
    ]),
    error,
    primaryButton(tr('Napravi anketu'), add),
  ]);
}
