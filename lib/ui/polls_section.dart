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

/// Closes the brush of a poll and puts the page back where it stood before it
/// opened, as if it had never moved.
void _closeBrush(Ui ui) {
  ui.editingPoll = null;
  ui.rerender();
  final before = ui.pollScrollBefore;
  ui.pollScrollBefore = null;
  if (before == null) return;
  Timer(const Duration(milliseconds: 60), () {
    web.window.scrollTo(web.ScrollToOptions(top: before, behavior: 'smooth'));
    // Then the page is as tall as before too, with no room left under it.
    Timer(const Duration(milliseconds: 600), () {
      (web.document.querySelector('.frame') as web.HTMLElement?)?.style.minHeight = '';
    });
  });
}

/// One more answer to vote for, typed in the poll's card while its answers are
/// being changed. A yes or no stays one answer per person.
web.HTMLElement _optionForm(Ui ui, Trip trip, Poll poll) {
  final answer = input(placeholder: tr('Nova mogućnost'));
  void close() => _closeBrush(ui);

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
    ui.changed();
  }

  answer.onKeyDown.listen((event) {
    if (event.key == 'Enter') add();
    if (event.key == 'Escape') close();
  });
  return el('div', cls: 'option-form', children: [
    el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [answer]),
    button(cls: 'text-button', text: tr('Dodaj'), onTap: add),
  ]);
}

/// Takes [option] out of [poll], votes and all, with a moment to change your mind.
void _removeOption(Ui ui, Poll poll, PollOption option) {
  final at = poll.options.indexOf(option);
  poll.options.removeAt(at);
  ui.changed();
  ui.offerUndo(tr('Uklonjeno: {0}', [tr(option.time)]), () {
    poll.options.insert(at.clamp(0, poll.options.length), option);
    ui.changed();
  });
}

/// The poll's name, which a tap opens for typing like any text.
web.HTMLElement _pollTitle(Ui ui, Trip trip, Poll poll) =>
    editableName(poll.title, tr('Naziv ankete'), (name) {
      renamePoll(trip, poll, name);
      ui.changed();
    });

web.HTMLElement _pollCard(Ui ui, Trip trip, Poll poll) {
  final me = ui.meIn(trip);
  final inAttack = pollInAttack(trip, poll);
  final editing = ui.editingPoll == poll.id;
  return el('div', cls: 'poll card', attrs: {'data-poll': poll.id}, children: [
    el('div', attrs: {'style': 'display:flex;align-items:center'}, children: [
      el('div', cls: 'grow', children: [_pollTitle(ui, trip, poll)]),
      removeWithUndo(ui, trip.polls, poll, poll.title, named: false),
    ]),
    el('div', cls: 'checks', attrs: {'style': 'margin:6px 0 0'}, children: [
      for (final option in poll.options)
        el('span', cls: 'option', children: [
          chip('${tr(option.time)} · ${option.votes.length}',
              () => _vote(ui, trip, poll, option, me),
              on: option.votes.contains(me)),
          if (editing && poll.options.length > 1)
            button(
              cls: 'option-x',
              ariaLabel: tr('Makni: {0}', [tr(option.time)]),
              onTap: () => _removeOption(ui, poll, option),
              children: [icon('close', size: 12)],
            ),
        ]),
      button(
        cls: editing ? 'icon-button more-option on' : 'icon-button more-option',
        ariaLabel: tr('Uredi mogućnosti'),
        onTap: () {
          if (editing) {
            _closeBrush(ui);
            return;
          }
          // Opened at the bottom of the screen, the poll moves up into sight;
          // closed, the page goes back to where it stood.
          ui.pollScrollBefore ??= web.window.scrollY;
          ui.editingPoll = poll.id;
          ui.rerender();
          Timer(const Duration(milliseconds: 60), () {
            web.document
                .querySelector('[data-poll="${poll.id}"]')
                ?.scrollIntoView(web.ScrollIntoViewOptions(block: 'nearest', behavior: 'smooth'));
          });
        },
        children: [icon('brush', size: 20)],
      )..setAttribute('aria-pressed', '$editing'),
    ]),
    if (editing && poll.options.length < mostOptions) _optionForm(ui, trip, poll),
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

/// A new poll: the choices are answers of any kind or times, as many as wanted;
/// with none it is a plain yes or no.
web.HTMLElement _newPoll(Ui ui, Trip trip) {
  final title = input();
  final choices = <web.HTMLInputElement>[];
  final rows = el('div');
  final error = errorLine();

  web.HTMLElement more(String label, {String? action, String type = 'text'}) => button(
        cls: 'text-button',
        text: '+ ${action ?? label}',
        onTap: () {
          final picker = type == 'time' ? timePicker() : null;
          final choice = picker?.value ?? input(type: type);
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
            picker?.view ?? choice,
          ]);
          rows.append(row);
          (picker?.view.querySelector('select') as web.HTMLElement? ?? choice).focus();
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
      more(tr('Opcija'), action: tr('Dodaj opciju')),
      more(tr('Vrijeme'), type: 'time'),
    ]),
    error,
    primaryButton(tr('Napravi anketu'), add),
  ]);
}
