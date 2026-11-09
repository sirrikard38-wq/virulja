import 'dart:async';

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

/// The poll's name; with the brush open it is typed on its line.
web.HTMLElement _pollTitle(Ui ui, Trip trip, Poll poll, {required bool editing}) => !editing
    ? el('div', cls: 'poll-name', text: poll.title)
    : titleField(
      poll.title,
      label: tr('Naziv ankete'),
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
      _pollTitle(ui, trip, poll, editing: editing),
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
        if (!inAttack) ui.toast(tr('Dodano u Plan napada.'));
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
  final List<String> order;
  if (kept != null && kept.trip == trip.id) {
    // A poll taken out keeps its place in the order, so that undo puts it
    // back where it stood.
    order = [
      ...kept.ids,
      for (final poll in trip.polls)
        if (!kept.ids.contains(poll.id)) poll.id,
    ];
  } else {
    order = [for (final poll in pollsInOrder(trip)) poll.id];
  }
  final byId = {for (final poll in trip.polls) poll.id: poll};
  shown = [
    for (final id in order)
      if (byId[id] case final poll?) poll,
  ];
  ui.pollsKept = (trip: trip.id, ids: order);
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

/// A new poll on a card as a poll with its brush open: the name on its line,
/// ready for typing, Da, Ne and Možda each with an x, a field for more, the x
/// in the corner that throws it away (with the usual undo), and Izradi anketu.
/// It needs a name with at least one letter, and two answers.
web.HTMLElement _draftCard(Ui ui, Trip trip, PollDraft draft) {
  final error = errorLine();
  void again() => redrawTripTab(ui, trip);
  final answer = input(placeholder: tr('Nova mogućnost'));

  void addAnswer() {
    final text = answer.value.trim();
    if (text.isEmpty) return;
    if (draft.options.any((option) => tr(option).toLowerCase() == text.toLowerCase())) {
      ui.toast(tr('Ta mogućnost već postoji.'));
      return;
    }
    if (draft.options.length >= mostOptions) return;
    draft.options.add(text);
    again();
    (web.document.querySelector('.poll-draft .option-form input') as web.HTMLElement?)?.focus();
  }

  answer.onKeyDown.listen((event) {
    if (event.key == 'Enter') addAnswer();
  });

  void create() {
    final title = draft.title.trim();
    if (!hasLetter(title)) {
      error.textContent = tr('Upiši što odlučujete, barem jednim slovom.');
      return;
    }
    if (draft.options.length < 2) {
      error.textContent = tr('Anketa treba barem dvije mogućnosti.');
      return;
    }
    trip.polls.add(Poll(
      id: ui.store.newId(),
      title: title,
      dayIndex: -1,
      single: draft.options.every(yesOrNo.contains),
      addedBy: ui.meIn(trip),
      options: [
        for (var i = 0; i < draft.options.length; i++)
          PollOption(id: 'o$i', time: draft.options[i]),
      ],
    ));
    ui.pollDraft = null;
    ui.pollsKept = null;
    ui.saved();
    again();
  }

  void throwAway() {
    ui.pollDraft = null;
    again();
    ui.offerUndo(tr('Uklonjeno: {0}', [tr('Nova anketa')]), () {
      ui.pollDraft = draft;
      again();
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
    el('div', cls: 'checks', attrs: {'style': 'margin:8px 0 0'}, children: [
      for (final option in draft.options)
        el('span', cls: 'option', children: [
          el('span', cls: 'chip', text: tr(option)),
          button(
            cls: 'option-x',
            ariaLabel: tr('Makni: {0}', [tr(option)]),
            onTap: () {
              draft.options.remove(option);
              again();
            },
            children: [icon('close', size: 12)],
          ),
        ]),
    ]),
    if (draft.options.length < mostOptions)
      el('div', cls: 'option-form', children: [
        el('label', cls: 'grow', attrs: {'style': 'display:block'}, children: [answer]),
        button(cls: 'text-button', text: tr('Dodaj'), onTap: addAnswer),
      ]),
    error,
    primaryButton(tr('Izradi anketu'), create),
  ]);
}
