import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../src/domain/attack.dart';
import '../src/domain/i18n.dart';
import '../src/domain/models.dart';
import 'context.dart';
import 'dom.dart';
import 'icons.dart';
import 'swipes.dart';
import 'trip_screen.dart';
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
  ui.saved();
  redrawTripTab(ui, trip);
}

const Duration _foldTime = Duration(milliseconds: 260);

/// Opens or closes the brush of [poll]. The page stays where it is: the card
/// grows or shrinks smoothly and the polls under it follow. Opened where it
/// cannot all be seen, the page glides just far enough to show it whole.
void _setBrush(Ui ui, Trip trip, Poll poll, bool open) {
  final selector = '[data-poll="${poll.id}"]';
  final from = (web.document.querySelector(selector) as web.HTMLElement?)?.offsetHeight ?? 0;
  // The page never gets shorter under the finger.
  final frame = web.document.querySelector('.frame') as web.HTMLElement?;
  if (frame != null) {
    final need = web.window.scrollY + web.window.innerHeight;
    final has = double.tryParse(frame.style.minHeight.replaceAll('px', '')) ?? 0;
    if (need > has) frame.style.minHeight = '${need.round()}px';
  }
  ui.editingPoll = open ? poll.id : null;
  redrawTripTab(ui, trip);
  final card = web.document.querySelector(selector) as web.HTMLElement?;
  if (card == null) return;
  final to = card.offsetHeight;
  if (open) {
    // Just far enough down for the whole poll, above the bar at the bottom.
    final nav = web.document.querySelector('.nav')?.getBoundingClientRect().top ?? web.window.innerHeight;
    final bottom = card.getBoundingClientRect().top + to;
    if (bottom > nav - 8) {
      web.window.scrollBy(web.ScrollToOptions(top: bottom - nav + 16, behavior: 'smooth'));
    }
  }
  if (wantsLessMotion || from == 0 || from == to) return;
  card.style
    ..transition = 'none'
    ..overflow = 'hidden'
    ..height = '${from}px';
  card.getBoundingClientRect(); // so that the browser sees where it starts
  card.style
    ..transition = 'height ${_foldTime.inMilliseconds}ms ease'
    ..height = '${to}px';
  Timer(_foldTime + const Duration(milliseconds: 40), () {
    card.style
      ..transition = ''
      ..overflow = ''
      ..height = '';
  });
}

/// One more answer to vote for, typed in the poll's card while its answers are
/// being changed. A yes or no stays one answer per person.
web.HTMLElement _optionForm(Ui ui, Trip trip, Poll poll) {
  final answer = input(placeholder: tr('Nova mogućnost'));
  void close() => _setBrush(ui, trip, poll, false);

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
    ui.saved();
    redrawTripTab(ui, trip);
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
void _removeOption(Ui ui, Trip trip, Poll poll, PollOption option) {
  final at = poll.options.indexOf(option);
  poll.options.removeAt(at);
  ui.saved();
  redrawTripTab(ui, trip);
  ui.offerUndo(tr('Uklonjeno: {0}', [tr(option.time)]), () {
    poll.options.insert(at.clamp(0, poll.options.length), option);
    ui.changed();
  });
}

/// The poll's name, which a tap opens for typing like any text.
web.HTMLElement _pollTitle(Ui ui, Trip trip, Poll poll) => titleField(
      poll.title,
      label: tr('Naziv ankete'),
      quiet: true,
      onDone: (name) {
        if (name.isEmpty || name == poll.title) {
          redrawTripTab(ui, trip);
          return;
        }
        renamePoll(trip, poll, name);
        ui.saved();
        redrawTripTab(ui, trip);
      },
    );

web.HTMLElement _pollCard(Ui ui, Trip trip, Poll poll) {
  final me = ui.meIn(trip);
  final inAttack = pollInAttack(trip, poll);
  final editing = ui.editingPoll == poll.id;
  return el('div', cls: inAttack ? 'poll card in-attack' : 'poll card', attrs: {'data-poll': poll.id}, children: [
    el('div', cls: 'poll-top', children: [
      _pollTitle(ui, trip, poll),
      el('span', cls: 'poll-gap'),
      button(
        cls: editing ? 'icon-button more-option on' : 'icon-button more-option',
        ariaLabel: tr('Uredi mogućnosti'),
        onTap: () => _setBrush(ui, trip, poll, !editing),
        children: [icon('brush', size: 20)],
      )..setAttribute('aria-pressed', '$editing'),
      removeWithUndo(ui, trip.polls, poll, poll.title, named: false),
    ]),
    el('div', cls: 'checks', attrs: {'style': 'margin:6px 0 0'}, children: [
      for (final option in poll.options)
        el('span', cls: 'option', children: [
          chip('${tr(option.time)} · ${option.votes.length}', () {
            // A poll in Plan napada keeps its votes; untick it to vote again.
            if (inAttack) {
              ui.toast(tr('Anketa je u planu napada, izmjena glasova nije moguća.'));
              return;
            }
            _vote(ui, trip, poll, option, me);
          }, on: option.votes.contains(me)),
          if (editing && poll.options.length > 1)
            button(
              cls: 'option-x',
              ariaLabel: tr('Makni: {0}', [tr(option.time)]),
              onTap: () => _removeOption(ui, trip, poll, option),
              children: [icon('close', size: 12)],
            ),
        ]),
    ]),
    if (editing && poll.options.length < mostOptions) _optionForm(ui, trip, poll),
    el('div', attrs: {'style': 'margin-top:6px'}, children: [
      tick(tr('Dodaj u plan napada'), inAttack, () {
        setPollInAttack(trip, poll, !inAttack, me);
        ui.saved();
        redrawTripTab(ui, trip);
      }),
    ]),
  ]);
}

/// Votes on what to do and when: "Na plažu" at 10:00 or 11:30. The days are
/// picked in Plan napada.
web.HTMLElement pollsTab(Ui ui, Trip trip) {
  // Those in Plan napada go last, the last one in first; while Ankete is open
  // nothing moves, and a new poll comes in under the others.
  final kept = ui.pollsKept;
  final List<Poll> shown;
  if (kept != null && kept.trip == trip.id) {
    final byId = {for (final poll in trip.polls) poll.id: poll};
    shown = [
      for (final id in kept.ids)
        if (byId[id] case final poll?) poll,
      for (final poll in trip.polls)
        if (!kept.ids.contains(poll.id)) poll,
    ];
  } else {
    shown = pollsInOrder(trip);
  }
  ui.pollsKept = (trip: trip.id, ids: [for (final poll in shown) poll.id]);
  final draft = ui.pollDraft;
  return el('div', children: [
    if (draft == null)
      el('div', cls: 'new-poll-row', children: [
        button(
          cls: 'text-button new-poll',
          text: '+ ${tr('Nova anketa')}',
          onTap: () {
            ui.pollDraft = PollDraft();
            redrawTripTab(ui, trip);
            (web.document.querySelector('.poll-draft textarea') as web.HTMLElement?)?.focus();
          },
        ),
      ])
    else
      _draftCard(ui, trip, draft),
    if (trip.polls.isEmpty) el('p', cls: 'soft pad gap-top', text: tr('Još nema anketa.')),
    for (final poll in shown) _pollCard(ui, trip, poll),
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

/// A new poll on a card as polls are: its name on top with the x that throws
/// it away (with the usual undo), answers of any kind or times under it, as
/// many as wanted, and Napravi anketu. With no answers it is a yes or no.
web.HTMLElement _draftCard(Ui ui, Trip trip, PollDraft draft) {
  final error = errorLine();
  final rows = el('div');

  void drawChoice(PollChoice choice) {
    final web.HTMLElement control;
    if (choice.time) {
      final picker = timePicker();
      final wheels = picker.view.querySelectorAll('select');
      if (choice.value.contains(':') && wheels.length == 2) {
        (wheels.item(0) as web.HTMLSelectElement).value = choice.value.split(':').first;
        (wheels.item(1) as web.HTMLSelectElement).value = choice.value.split(':').last;
        picker.value.value = choice.value;
      }
      picker.view.addEventListener('change', ((web.Event _) {
        choice.value = picker.value.value;
      }).toJS);
      control = picker.view;
    } else {
      final box = input(value: choice.value);
      box.onInput.listen((_) => choice.value = box.value);
      control = box;
    }
    late final web.HTMLElement row;
    row = el('div', cls: 'field', children: [
      el('div', attrs: {'style': 'display:flex;align-items:center;gap:6px'}, children: [
        button(
          cls: 'icon-button',
          ariaLabel: tr('Makni: {0}', [choice.time ? tr('Vrijeme') : tr('Opcija')]),
          onTap: () {
            draft.choices.remove(choice);
            row.remove();
          },
          children: [icon('minus', size: 20)],
        ),
        el('span', text: choice.time ? tr('Vrijeme') : tr('Opcija')),
      ]),
      control,
    ]);
    rows.append(row);
  }

  for (final choice in draft.choices) {
    drawChoice(choice);
  }

  web.HTMLElement more(String label, {required bool time, String? action}) => button(
        cls: 'text-button',
        text: '+ ${action ?? label}',
        onTap: () {
          final choice = PollChoice(time: time);
          draft.choices.add(choice);
          drawChoice(choice);
          (rows.lastElementChild?.querySelector('input, select') as web.HTMLElement?)?.focus();
        },
      );

  void create() {
    final title = draft.title.trim();
    if (title.isEmpty) {
      error.textContent = tr('Upiši što odlučujete.');
      return;
    }
    final filled = {
      for (final choice in draft.choices)
        if (choice.value.trim().isNotEmpty) choice.value.trim(),
    }.toList();
    final chosen = filled.isEmpty ? ['Da', 'Ne'] : filled;
    trip.polls.add(Poll(
      id: ui.store.newId(),
      title: title,
      dayIndex: -1,
      addedBy: ui.meIn(trip),
      options: [
        for (var i = 0; i < chosen.length; i++)
          PollOption(id: 'o$i', time: chosen[i]),
      ],
    ));
    ui.pollDraft = null;
    ui.pollsKept = null;
    ui.saved();
    redrawTripTab(ui, trip);
  }

  void throwAway() {
    ui.pollDraft = null;
    redrawTripTab(ui, trip);
    ui.offerUndo(tr('Uklonjeno: {0}', [tr('Nova anketa')]), () {
      ui.pollDraft = draft;
      redrawTripTab(ui, trip);
    });
  }

  return el('div', cls: 'poll card poll-draft', children: [
    el('div', cls: 'poll-top', children: [
      titleField(
        draft.title,
        label: tr('Što odlučujemo'),
        placeholder: tr('Što odlučujemo?'),
        onInput: (text) => draft.title = text,
      ),
      el('span', cls: 'poll-gap'),
      button(
        cls: 'icon-button',
        ariaLabel: tr('Makni: {0}', [tr('Nova anketa')]),
        onTap: throwAway,
        children: [icon('close', size: 20)],
      ),
    ]),
    rows,
    el('div', attrs: {'style': 'display:flex;flex-wrap:wrap;gap:16px;margin-top:10px'}, children: [
      more(tr('Opcija'), time: false, action: tr('Dodaj opciju')),
      more(tr('Vrijeme'), time: true),
    ]),
    error,
    primaryButton(tr('Napravi anketu'), create),
  ]);
}
