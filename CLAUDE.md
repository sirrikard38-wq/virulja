# VIRULJA

A trip app for a family or group of friends, used on phones as an installable web
app in Croatian, English and Turkish; code and comments are in English. The user writes
in Croatian and is not a programmer: explain things in plain words.

Every text in the code is the Croatian one inside `tr()`, with `{0}` for what goes into it;
English and Turkish are in `lib/src/domain/i18n.dart`, and `test/i18n_test.dart` fails if
one is missing. Dates and counts are in `format.dart`. Stored texts stay Croatian keys
(poll answers Da, Ne, Možda; offer source Ručno) and are translated when shown.

## Commands

```
dart analyze
dart test
dart run tool/build.dart          # builds the site into build/
dart run tool/serve.dart 8090     # serves build/ (add --lan for a phone on the same Wi-Fi)
```

`.claude/launch.json` has the preview servers `virulja` and `virulja-phone`. This
machine has Dart and git, but no Node, Python or `gh`.

## How it is built

The stack and the deploy were copied from the user's Dartle project as a pattern; nothing
links the two, and each has its own repo and site. Dart compiled to
JavaScript with `package:web`, no framework, screens built with `el()` from
`lib/ui/dom.dart`, a full redraw of the screen after every change, GitHub Pages
through `.github/workflows/pages.yml`, a service worker in `web/sw.js`.

- `lib/src/domain/`: pure Dart, all of it tested. Money is whole cents. Days are UTC
  midnights.
- `lib/ui/store.dart`: everything is saved on the phone in IndexedDB: the data as JSON,
  pictures and sound as blobs.
- `lib/ui/media.dart`: photos are shrunk to 1280 px, a few hundred KB; originals stay in
  the gallery.
- `lib/ui/anthem.dart`: the trip's anthem.
- `lib/ui/cloud.dart`: sharing, on top of the tested logic in `lib/src/domain/tree.dart`,
  `trip_tree.dart` and `session.dart`.
- Opened anew, the app shows VIRULJA rising letter by letter in the middle for about
  3 s and starts on the trips (`showSplash`, a `sessionStorage` mark). The splash is in
  `index.html` itself, so it is the first picture, and the look chosen in Postavke
  comes from `localStorage` before anything is drawn: added by the app once it had
  loaded, it came after a dark flash (2026-11-09). Putovanja is the
  very first step, so a swipe back there only stretches the page; a step of its own
  under it (`#/start`, 2026-11-08) gave a white screen on that swipe (2026-11-09).
  Back on the first step, the way forward is wiped by a copy of the screen put after
  it and a step back onto it (`copy` in the history state); a swipe forward reaches
  only that copy and steps back again. Without it a swipe from the right edge went on
  to Postavke. A newer version never loads while a step back settles (`_settling`); a reload for a
  newer version keeps the screen and shows no splash.
- The bottom bar has two places: Putovanja and Postavke (a screwdriver, `tool`). Past
  trips stand at the very bottom of Putovanja as "Prošla putovanja", always there, with a
  note while there are none; there is no
  Uspomene page any more (an old `#/uspomene` opens Putovanja).
- A new version loads at the next change of screen or return to the app, on any
  screen but a form, a box or typing (`isIdle`); it used to wait for the home
  screen, so someone staying in a trip kept the old one. Postavke shows "Verzija".
- The address (`#/p/<trip>/<section>`) is the route, so the phone's back button works.
  Every step back (the arrow, the phone's back button or swipe) is followed 400 ms later
  by one more step back out of sight and the screen put back as a fresh step through
  the address (`_settleAfterBack`): that wipes out the step forward an iPhone's swipe
  from the right edge would reach, with no copy of a screen left to swipe back to.
  Copies of screens (`/~`) made a swipe back show the same trip again; pushing history
  steps while the phone steps back froze an iPhone and left it white (2026-11-04).
- The screen of the day plan and the journey (`route_screen.dart`, called Plan puta in
  these notes) is named "Prijevoz" in the app. Each day has its own cars and other
  transport (`Leg.dayIndex`; a car is a leg with `Leg.drive`, its cost worked out
  as it is typed, with no way back counted), added to the day shown, each with a
  brush that opens it for changing (`Ui.editingLeg`). The one car a trip had before
  moves to the first day (`moveOldDrive`, id `drive`, both ways when it counted
  them). Dodaj prijevoz has Relacija on a third of a row, growing with its text, then
  Prijevoz and Iznos half and half; any two may stay empty (`Leg.route`; the name is
  "Prijevoz - Relacija", `legName`). Once a part (a car too) has a price, Dodaj or
  the brush's Spremi opens the cost box, as Dodaj trošak, and writes it in Troškovi
  under its name (`Leg.expenseId`, `_afterLeg`); a cost written follows its name and
  price, and goes with the part, undo bringing both back (2026-11-09). At the foot, over "Planirani trošak po osobi", "Prijevoz ukupno" adds up
  every day, each part at its cost in Troškovi once written, and every other cost
  of the kind Prijevoz written in Troškovi, which shows on no day (`transportTotal`);
  the tile Prijevoz in Plan shows the same (2026-11-09).
- `lib/ui/swipes.dart`: sideways swipes between pages, for the food categories, a
  trip's tabs and the days of Plan puta. The next page comes along beside the one
  that goes, as far as the finger has gone (`peek`), and the green mark (the line under
  a tab, the fill of a chip) moves with it (`SwipeMark`); let go past the length, the
  page glides the rest and is drawn in place with no slide of its own (`justSwiped`).
  The page coming in has its faded edges from the start; the green over chips carries
  their words in dark, so each letter turns as the green passes (`marker-words`).
  `.slide-page` is its own block (`flow-root`), so the space over its first line is the
  same beside and in place; otherwise the page jumped 10 px up as it landed. A shorter
  page shrinks smoothly as it lands (`_easeHeight`), so what stands under it glides; a
  taller one takes its height at once, as growing hid its bottom and Dodaj jelo popped
  in (2026-11-09). A swipe anywhere on Prijevoz changes the day. Its
  adders stand still at the bottom, right over the line of the foot (Prijevoz ukupno,
  Planirani trošak po osobi), which is at the bottom of the screen as in every
  category of Plan (`route-foot`; said twice, 2026-11-09). Sliding with the day,
  they jumped as a day with transport landed. A swipe is off while a form is open, as a redraw would wipe it.
- Tool icons and the temporary logo: `tool/make_icons.ps1`, `lib/ui/icons.dart`
  (`logoMark`), `web/styles.css` (`--logo`).

## Agreed with the user

- Theme A Maslina, on the design canvas
  https://claude.ai/artifact/LPK38eCE73Kx6HuBepHRob (variants, logos, a clickable
  prototype). Logo 3 Vir is temporary: the user will make the real logo later.
- Photos: one tap on every phone; each person picks from the gallery and the app sorts
  by day. No automatic gallery reading. Uspomene shows "Prije puta", the days of the trip and
  "Poslije puta" (-1 and `dayCount` from `Trip.photoDay`; a photo moved after the trip
  stores `afterTrip`), and a finger held on a photo drags it to any of them
  (`Photo.dayIndex`, `lib/ui/photo_drag.dart`).
- Photos have reactions and comments, one reaction per person.
- The speaker's ring starts each new screen where the anthem already is (`_progress` in
  `app.dart`); drawn from nothing, it jumped back at every screen.
- Videos are photos with `videoType` (`lib/ui/video_work.dart`). A video from a phone would
  fill the free storage, so the app keeps the first 30 seconds at 3 to 6 MB. A browser can
  only do that by playing the video into a canvas and recording it (`MediaRecorder`), so it
  takes as long as the video, starts with a tap and stops if the app is left. Whether this
  works on a real iPhone is not tested yet. Longer videos would need Cloud Storage and a
  card, or a separate free video service.
- Food planning has both: places with a price per person and dishes with prices. The
  dishes are only in their own category of that row, named Hrana. The sum at the bottom of
  the screen is that of the open category alone, counting what is in the plan; it is part
  of the page, after a form that is open, never over it.
- First version also has: drive calculation, actual costs, who owes whom, voting.
- The group agrees when at least half picks the same, and both when there are two
  (`Trip.votesToAgree`). A poll only goes into Plan napada by itself when every member
  answered Da (`allSayYes`). This is checked on every look at a trip, not only on a vote,
  so a yes from any phone counts (`addWholeYeses`); `Poll.autoAdded` remembers it was done,
  so unticking takes it out for good, until the yes is no longer whole. The box in Ankete
  and the button in Hrana i piće put things there by hand. Ankete shows no "Izglasano";
  "+ Nova anketa" stands on top, on the right. A
  place and the yes or no poll about it are one thing in Plan napada (`placeInAttack`).
  Polls have no day any more: people pick days on each thing in Plan napada. The chips
  Sve, 1 Dan, 2 Dan show each thing on the day with most votes, on all equal ones, and on
  none before the first vote (`votedDays`). Only votes give a day: not the day an older
  poll was made for, nor a stop's day in Plan puta. Days are written "1 Dan", not "Dan 1". While a day is
  open, what was on it stays even when a vote moves it; it moves once the day is left
  (`Ui.attackKept`). Back in Plan napada within 20 s it opens on the same day, later on
  Sve. "Dogovoreno" news still needs half the group (`agreedDays`). Votes,
  days and time never move a thing in Plan napada. Its tick writes a cost and ticks the
  thing off for that day (`Trip.ticked`, day -1 for one with no day): green there, and
  last on that day, the last ticked first, once the day is left (`tickedLast`,
  `Ui.attackOrder`); on Sve the box asks "Koji dan?", offering every day someone voted for
  (`tickDays`; one ticked already shows ✓), and that day is ticked as if it were open;
  on Sve a thing is green and last once every one of those days is ticked, with a green
  edge while only some are. A tap on a green tick takes it back with the
  cost, with the usual undo. The tabs
  show how many presentations, polls and plans there are, and each day chip its plans; the
  cards show no date, only a past one does.
- Spent (Potrošeno, the tiles of Plan, "tvoj trošak") is only what is written in Troškovi
  (2026-11-05). Each thing in Plan napada has a tick that opens the cost box
  (`costSheet`: amount, who paid, for whom, x to close); it is green once a cost of its
  name is written. Kupljeno in Dućan and Razdijeli use the same box. A paid debt stays in the
  list, green, where it stood.
- Removing anything, and settling a debt, is
  undone within 5 seconds instead of asking first. Only a photo or video still asks, as its
  file is deleted at once.
- Presentations (`lib/src/domain/show.dart`, `lib/ui/show_*.dart`, `shows_section.dart`):
  the photos and videos picked for it (`Show.chosen`, in the order picked; older ones have
  all but `leftOut`) follow each other with one of 15 transitions, lengthened with a bar
  from 0 to 12 s (`secondsBar`). The builder has the name on top, then a row for each day,
  Prije puta and the first day first, then "Odabrano za prezentaciju" (a finger held on a photo changes
  the order, `reorderable`) and the preview, which stays at the top of the screen
  (sticky; a tap on it stops and starts it, `ShowPlayer.togglePause`) while the transition, "Produljenje prijelaza" and "Duljina uspomene" are set.
  "Ništa" is a cut with no moving time and no bar (`movingTime`); it is always there and
  not one of the 15 (`effects`). "Lom stakla" (stored as `glass`; an old `black`, Kroz
  crno, reads as it) breaks the photo going out into 24 pieces that fly and fall
  (`_shatter` in `show_player.dart`; a video gives its current picture). A photo then stands 2.5 s, or what its bar
  says, from 0.5 s up to the same daily limit as the transitions; the bars are marked at
  each day's limit (`dayLimits`) and write 6s with no space. A video's piece is set on one bar as long as
  the video (`clipBar`), its ends and middle dragged; while a video is set, the preview
  plays only that piece and stands on the second under the finger (`ShowPlayer.hold`).
  A video plays a piece of it, 6 s of every 30 s
  it lasts at most (`longestClip`, `clipOf`); kept videos are 30 s at most, so one piece of
  6 s. The video stands still on the piece's first picture during its transition. On the first day of the trip 6 s
  and 5 transitions are open; each later day adds the rest up to 12 s divided by the days
  left, in hundredths, so the last day opens 12 s and all 15 (`extraLimit`,
  `openTransitions`). Numbers show one decimal, cut (`tenths`). Each person makes up to 3
  (`showsEach`), shown as 1/3, 2/3. Everyone has one vote (`Trip.showPicks`); the most voted
  is "Prezentacija dana" (`showOfTheDay`) and plays on the trip's cover, the newest before
  any vote (`onCover`). Equal votes do not take its place, only more: `Trip.dayShowId`
  remembers it (`keepShowOfTheDay`, on every look at a trip). The list stays in the order
  made. Each person changes only their own presentations. In Postavke, someone whose
  first name is Riko has "Svi prijelazi odmah" (`Ui.mayOpenAll`, `AppData.allTransitions`):
  every transition open on that phone. A name is no lock, as anyone can take it. A tap on the cover or on a presentation plays it over the whole
  screen (`watchShow`); an iPhone keeps its bars, as Safari gives the whole screen only to
  a video. "Isti prijelazi i duljina uspomene za sve" turns into "Vrati natrag" until
  something else changes. The presentation of the day has a green card with a badge; the
  vote count is big, and the maker's brush sits in a round button inside the card. The players of the cover and of watching keep going across redraws
  (`keptPlayer`).
- package:web types `MouseEvent.clientX` as a whole number, and a phone gives decimals, so
  pointer positions are read straight from the event (`seconds_bar.dart`).
- A poll's card has its name on top, then the brush, then the x in the corner. The name
  is typed only with the brush open (`titleField`: half the row at first, growing with
  the text, then more lines, at most 400 letters counted at the end of the line). A new
  poll is made on a card like one with its brush open (`PollDraft`): the name ready for
  typing with the keyboard up, Da, Ne and Možda each with an x, a field for more, no
  times, and Izradi anketu; it needs a letter in its name (`hasLetter`) and two answers.
  Its x throws it away with the usual undo. New polls stand on top, those in Plan
  napada at the bottom. Leaving Ankete closes a brush. In Plan napada a card has the cost tick in
  the top right corner and the x right of it (2026-11-09; for a while it was at the
  bottom).
- A poll's brush opens and closes in place (`_setBrush`): the page stays where it is, the
  card grows or shrinks smoothly and the polls under it follow; opened where it cannot all
  be seen, the page glides just far enough to show it whole. A poll in Plan napada
  ("Dodaj u plan napada" ticked) is green and goes last, the last one in first, as bought
  lists do (`pollsInOrder`, `Poll.activeAt`); while Ankete is open nothing moves, it sorts
  once Ankete is left (`Ui.pollsKept`). It keeps its votes: a tap on an answer says
  so; untick it to vote again. A poll taken out and brought back with undo stands where
  it stood (the order kept in `Ui.pollsKept` keeps its place).
- A yes or no poll takes one answer from each person (`onlyOneAnswer`). A tap on a poll's name
  opens it for typing; a poll about a place or a dish renames that too, as they are found
  by name (`renamePoll`). The brush at the right of the answers (`Ui.editingPoll`) puts an
  x on each answer, which removes it with the usual undo, and a field for a new one, up
  to 5 (`mostOptions`). A new poll takes plain answers ("Dodaj opciju") or times. A yes
  or no stays one answer per person (`Poll.single`), and in Plan napada the added answer
  with most votes shows. Ne and
  Možda never decide a poll.
- Prijevoz has no Rezervirano: what is written there is so, with no vote, and it
  never goes into Plan napada (2026-11-09; `Leg.reserved` stays only in old data). Troškovi always shows
  Smještaj, Hrana i piće and Prijevoz. Categories of Hrana i piće go only in the bin.
- On a trip's main tabs the settings button is in the corner (it scrolls away with the
  page, as do the speaker and the pin), the anthem's speaker under it,
  and under that a pin while a stay is reserved: Google Maps on foot from the phone to it
  (`walkTo`; when a short map link cannot be read, it walks to the stay's name in the
  trip's city). It is a plain link: `window.open` left the iPhone app white on return.
- Smještaj: each stay has a location (address or Google Maps link) and "Rezervirano". A
  reserved stay is planned and spent in Troškovi (`Offer.reserved`, `Trip.reservedOffer`).
  Rezervirano asks who paid and whom it is for (everyone ticked at first) and writes that
  cost in Troškovi (`Offer.expenseId`), so the others owe the payer; taking the
  reservation back removes the cost, with the usual undo.
  Only Rezervirano picks a stay (its card turns green); anyone votes for any number with
  "Glasaj". With both a location and an offer link, the link icon asks which to open. The name is
  typed in place; the brush opens the rest for changing. "Sortiraj" adds sorts, the first
  deciding most, each removed with its x; turning Sortiraj off clears them (`sortOffersBy`).
- Hrana i piće: a new dish has its name on half the row, growing with the text,
  then Cijena, Porcija and Gdje in one row; Gdje says "Link" in grey, and a dish
  with one has the link icon to Google Maps (a name typed there is looked up in the
  trip's city). The field for a new category stands lower, Dodaj kategoriju in the
  middle of the screen (`_toMiddle`).
- Hrana i piće: a swipe past the last category opens the field for a new one, as the +
  does, without the keyboard; a swipe back closes it. While it is open the + is green, not
  the category before it, and nothing of that category shows under the field.
- Hrana i piće: while a category is held, a bin stands at the top in the middle; let go
  over it and it goes with a puff of sparks and the usual undo. One the group made goes
  with its places; one of the app's own is hidden on this phone (`AppData.hiddenKinds`)
  and comes back when one of that name is added.
- Bars move only by dragging their round knob (or a video's piece); a tap elsewhere on a
  bar changes nothing.
- Names of polls, places and dishes are typed in place (`editableName`); a place or dish
  taken out of Hrana i piće takes its poll along, and undo brings both back; a poll taken
  out of Ankete leaves the place. Its button always says "Anketa".
- Dućan (`shop_screen.dart`, `Trip.shopLists`): named lists of things to buy, each with a
  tick that greys and strikes it out. A list folds as "+ Naziv", open with Kupljeno
  only. Nova lista and a list's brush open the same card (`_editCard`; a new one is
  `Ui.shopDraft` until saved): a box for the name ("Naziv liste" in grey), a box with
  an x for each thing, and an empty "Dodaj u listu" at the bottom; the keyboard's
  tick puts it in and opens the next; so does the tick an iPhone shows over the
  keyboard, which a page cannot remove (it only blurs: `onBlur`, 250 ms later, so a
  tap on the brush or another box goes first). An x leaves the cursor where it is. The brush,
  green, saves; the x in the corner, right of the others, throws the list away
  (2026-11-09). No box lets the page behind
  it scroll (`holdPage`). A bought list greys and says Kupljeno under its name;
  bought lists go last, the last bought first (`listsInOrder`, `ShopList.boughtAt`);
  the whole card of a bought list greys, and bought lists stand under Nova lista;
  one just bought folds and stands first of them. A bought list is drawn folded,
  with +, and "Kupljeno · amount · who paid" under its name; a tap still opens it.
  The foot says "Trošak dućana", every cost of the kind Dućan in Troškovi, the
  bought lists and those written by hand, which show in no list (`shopSpent`), over
  "Planirani trošak po osobi", as Prijevoz ukupno does; the tile Dućan in Plan
  shows the same.
  Kupljeno offers Poništi, which brings the list back where it was. A finger held
  on a list to buy carries it up or down (`movableUpDown` in `list_drag.dart`,
  `orderShopLists`). One whose Kupljeno is taken back stays
  where it stood while Dućan is open (`Ui.shopKept`), then goes among those to buy.
  Kupljeno asks the amount, who paid and whom it is for
  (all ticked at first) and writes it in Troškovi under Dućan; a tap
  on it in Troškovi changes it (`ShopList.expenseId`). Adding to
  or taking off a list is news of the kind Notice.shop; what was taken off is kept in
  `ShopList.removed` for the robot, and undo takes it out again (news mark `#3`).
- Times are picked on two wheels, minutes in steps of 5 (`timePicker`): a phone's own
  time field offers every minute.
- Troškovi shows Potrošeno, Planirano (the whole plan) and Preostalo (plan less spent;
  not "Ostalo", which is a kind of cost), and each kind as "Potrošeno X · Planirano Y".
  "Planirani trošak:" is written as "Procjena za" is, words left, with a box on the right
  for three digits, kept as it is typed with no button,
  that sets the whole the group means to spend (`Trip.budgets`), which is then the plan;
  it widens for a long number. Dućan, Prijevoz and Smještaj have one at the foot of the
  screen (`fill-page`). In Hrana i piće each category has its own under "Procjena za"
  (`food:<category>`, `foodBudgetKey`); food's plan is their sum, each category with
  none counting its estimate (`setBudget`).
- Currencies (2026-11-05): a trip has one or two (`Trip.currencies`, shared, stored as
  "TRY,EUR"). Amounts are written and kept in the first; the second shows small beside
  the sums in Troškovi, the header and the food estimate (`alsoIn`), converted at the
  day's ECB rates from the free `api.frankfurter.dev/v2/rates` (`loadRates`, once a
  day, kept in `AppData.rates`). Changing a trip's currency converts every amount of
  the trip at the day's rate (`changeTripCurrency`; with no rate it says so and keeps
  the currency). A trip's settings have no Spremi: Država and Grad keep as typed, the
  postcard photo once picked, the dates once the settings are left (`Ui.onLeave`, run
  by `render` when the address changes). A currency is taken only with the tick
  beside its wheel, green while the wheel stands on the one in use (2026-11-09). Postavke sets those of new trips (`AppData.currencies`). Both are picked on a
  narrow wheel (`currencyWheel`) turned like the time: the one in the middle, under a
  green ring that stands still, is chosen once the wheel stops. The second currency is
  off for now (2026-11-05, the user's wish): the wheel sets one and `alsoCode` stays
  null; the data still takes two. `euros()` writes the open trip's sign (`moneyCode`), labels with € go
  through `inMoney`.
- Forms of Smještaj and of Dodaj trošak: the name on half the width, growing with its text
  up to the whole row (`growWithText`), then rows of two or three fields (`form-row`,
  `thirds`), units in dark letters inside the box (`unitField`). Every box with a
  unit has it so, grey inside on the right, never in brackets in its label
  (said twice; 2026-11-09), "Planirani trošak po osobi" too. Vrsta and Tko je platio
  are as wide as their words; with no room the payer goes to the next row. Amount boxes
  write 1.250,50 while it is typed, the cursor kept after the same digits, and a typed
  dot is the decimal comma (`typedAmount`, `amountInput`); the cost box is as wide as
  its number. A trip's settings fold Šifra putovanja too,
  above Obavijesti.
- No blur at the top of any screen: an iPhone blurs what scrolls under its status
  bar, so a strip of the page's colour stands there (`top-cover` in `index.html`),
  and the cover photo starts under it (2026-11-09).
- A box over the page holds it by stopping the finger's scroll (`holdPage`), never by
  pinning the body in place: that moved the page, and at its bottom an iPhone jolted
  (2026-11-05). A box taller than the screen scrolls itself.
- A picture already opened on this phone gets its address at once on a redraw
  (`AppStore.knownAddress`); waiting for it flashed every picture blank, which looked
  like the screen jumping. Prezentacija dana folds in place, nothing else redrawn.
- Rows that scroll sideways (`.chips`, `.show-strip`) fade on the side where more is
  hidden (`markEdges`, after every drawing and on every scroll, heard by the page),
  never at the very end; the chosen day of Prijevoz is turned whole into sight
  (`showChosenChip`).
- A redraw of the same screen puts the page back exactly where it was (`_stayAt` in
  `app.dart`): an iPhone moved it while the screen was swapped (2026-11-05).
- Taking something out of a list leaves what is above where it was: a redraw of the
  same screen keeps the page tall enough for its scroll (`_drawnHash` in `app.dart`). A place of Hrana i piće in Plan
  napada whose day has come shows under "Za razdijeliti" (`toSplit`); Razdijeli asks what
  it really cost, who paid and whom it is for (`Place.expenseId`).
- Entering a code with the name (any capitals) and phone number of someone already in
  that trip brings this phone in as that person, at once (`_sameMember`, `rejoin`).
- A tap on a paid cost in Troškovi opens it for changing (`Ui.editingExpense`).
  Plaćeno has the strong line over it, as "Ukupno za tebe" has under it, and
  "+ Dodaj trošak" right under its heading, with no gap.
- Under "Tko kome duguje" comes first "Ukupno za tebe": all you owe each person added
  up, in red with a minus, and what each owes you, in green (`balanceOf`). The box of a
  tick in Plan napada starts with an empty amount.
- The trip's header shows "tvoj trošak": your part of each written cost you share, and an
  equal part of what is planned and not yet written (`Budget.shareOf`).
- Each presentation shows how long ago it was changed (`Show.changedAt`, `sinceCount`).
- Codes in Postavke: the next trip first, past ones last; "Sakrij" hides one on this phone
  (`AppData.hiddenCodes`); with any hidden, a tap on the heading folds them open, faded,
  each with "Prikaži". The anthem takes sound files only. The page does not zoom.
- What is folded open on a screen (presentations in Uspomene, lists of Dućan, a
  card's week in Plan napada, Sortiraj, the folds of Postavke, a brush) stays open
  when the screen is back within 5 s, as after a look at the next tab, and is folded
  again when it was left for longer (`Ui.closeFolds`, `_foldMemory`; 2026-11-09).
- A heading that folds a list open has + before it, and − while open. In Postavke,
  Jezik, Izgled and Valuta fold so under Obavijesti, and in a trip's settings
  Obavijesti, Putolovci and Valuta, in that order (`foldSection`, `Ui.openFolds`).
- In Plan napada the day chips sit under the card's buttons and fill its width
  (`attack-days`), four of one length a row; a trip of more than 7 days shows weeks
  ("Tjedan 1"), and a tap on one opens its days (`Ui.openWeek`). The row on top is then
  Sve, Tjedan 1, Tjedan 2… and the days of the open week after them (`Ui.attackWeeks`);
  it stays turned where it was whatever is picked (`Ui.attackRowLeft`). A day vote, the day chips, a poll's vote and its Plan
  napada tick redraw only the open tab in place, with the counts on the tabs
  (`redrawTripTab`): a full redraw made an iPhone jump to the top (2026-11-05).
  A day vote or a week opened on a card draws only that card and the row of days
  (`_redrawCard`): with 170 plans, drawing them all for one vote lagged (2026-11-09).
  The tab drawn beside during a swipe of a trip's tabs is the one put in place when
  it lands (`_beside`), not drawn twice.
- Numbers are written 1.250,50, and a whole one with no ,00 (`decimal`, `plainAmount`),
  in boxes too, and every typed number is read by `parseDecimal` (amounts by
  `parseEuros` on top of it), so 1.200 km is 1200, not 1,2. Planirano is only what the group planned per person
  ("Planirani trošak po osobi"), times everyone; the app's estimate (`BudgetLine.estimate`)
  is never added to it. The tiles of Plan and "tvoj trošak" show only what was spent. Unticking "Primaj sve
  obavijesti" stops every notification, so there is no separate button to turn them off.
- With JS interop types, `is web.HTMLVideoElement` is always true: keep videos in their own
  map instead of checking (`show_player.dart`).
- The postcard has a round seal with no background, as the user asked, so its ink follows
  the photo: dark on a bright corner, light with a shadow otherwise (`lib/src/domain/seal.dart`).

## Limits that were checked (2026-10-31)

- Anthem: it cannot come from a link. Spotify's `play` is not reliable on iPhones and
  YouTube demands a visible player of at least 200x200. So someone uploads the song once
  and the app keeps only the first 10 seconds. iPhones ignore `audio.volume`, so sound
  goes through a gain node of an audio context, started inside the tap that opens the
  trip. Moving around inside a trip never restarts it. It plays on every entry unless the
  speaker is muted; muting is remembered.
- On opening a trip the audio session is `ambient`: the anthem must not stop music or a
  video already playing on the phone, so an iPhone on silent does not play it. A tap meant
  to hear it (Poslušaj, the note, the speaker) uses `playback`, which plays on silent and
  stops other sound. The user reported "Himna ne radi" on 2026-11-04; the clip was whole in
  the cloud and played in a browser, so silent mode is the likely cause, not confirmed.
  Asked again, the user chose to keep `ambient` on opening a trip.
- The quiet level on a real iPhone is not tested yet.
- 2026-11-05 "Krug ne ide": the ring did not move, so the anthem never started (not silent
  mode). Likely its file never left the phone that added it while pushes failed
  (2026-11-04/05). A tap on the speaker or the note now says why it cannot play: the file
  has not reached this phone, or this phone cannot play it.
- Booking's API needs a partner contract. Airbnb has no public API and forbids scraping:
  do not build a scraper. Google Hotels data through SerpApi (250 free searches a month,
  unofficial) may give automatic prices; whether Booking shows up as a source is untested.

## Sharing between phones

Firebase project `virulja-55da8` on the user's Google account, on the free Spark plan
with no card: the user wants it free. Spark can never bill; over a limit it just stops.
Config is in `web/online.json` (public identifiers); an empty file means the app stays
on the phone. Realtime Database in europe-west1, used through its web interface (no SDK),
with anonymous sign-in. Rules are in `firebase/database.rules.json`; a change there must
also be pasted into the Firebase console.

- Each trip has a code of 10 mixed characters (older trips: 10 digits) in `/codes/<code>`; entering it once joins that device.
  Nobody is added by hand: two members must accept a newcomer, or the only member if alone
  (`JoinRequest`, in the trip's `requests`). Everyone on a trip has the same rights;
  there are no admins. Half of the whole group, rounded down, can vote a person out
  (`kickVotes`), and they may ask to come back, so the group decides again. Changing the
  code keeps the members. Names and phone numbers
  are entered once per device and changed in Postavke. The WhatsApp button is one tap
  (automatic sending needs the paid Business API), a plain link (`whatsAppLink`):
  `window.open` left the iPhone app white on return. The anthem stays an uploaded file.
- The database lets only members in (2026-11-04). `Trip.access` (sign-in id -> member)
  lists the phones of a trip; only they read and change it and its blobs, and move its
  codes; a person may have several. A trip without `access` is from before and stays open
  until a member's phone adds it (`_prepare`). Nobody can wipe a trip or take the lock
  off. A stranger with the code reads only `city`, writes only their own request (never
  its approvals) and reads it back. `keys/<name_last8digits>` -> member (`memberKey`) is
  read one at a time: writing the key to `claims/<uid>` with `access/<uid>` lets the same
  person in on another phone (`comeBack`), so a phone whose sign-in changed gets back in
  by itself. `tool/check_rules.dart` checks all of this against the real database.
- Each value is compared and sent separately (`TripMirror`), so people working at the same
  moment do not overwrite each other, and offline changes wait on the phone.
- The open trip follows the database live through `EventSource`; others are read when the
  app opens or returns to the screen. A redraw waits while someone types, has a form open
  or plays a song, because it would wipe them.
- Removing a trip only takes it off that phone, so nobody can wipe it for the group.
- A person has a general profile photo (`Person.photoId`, global settings) and may set another
  for one trip in that trip's settings (`AppData.tripPhotos`). The group sees `Trip.memberPhotos`.
- Pictures, the anthem and videos (in pieces of 3 MB of text, the limit in the rules) are
  base64 strings in `/blobs/<trip>/<id>`, because Cloud
  Storage needs the Blaze plan and a card. A photo takes about 270 KB, so the free 1 GB
  holds about 3,500 photos, and the free 10 GB a month of downloads is shared by the
  group. If they run out, moving pictures to Cloud Storage means Blaze and a card.
- A stress test (2026-11-09) with 25 people, 30 days, 60 polls, 60 places of each
  kind, 60 costs and 300 items in Dućan found every screen drawn in under 50 ms on a
  computer but Plan napada (about 80 ms, 170 cards), now fixed as above.
- Test two users with `http://localhost:8090` and `http://127.0.0.1:8090`: different
  addresses have separate storage. Delete test trips from the cloud afterwards.

## Trip reminders

Notifications go out 21, 14, 7, 3, 2 and 1 days before a trip (`lib/src/domain/reminders.dart`).
Firebase scheduled functions need Blaze, so `.github/workflows/remind.yml` runs
`tool/remind.dart` once a day, free. It sends standard web push (`tool/web_push.dart`,
tested against the RFC 8291 example). Each phone that turned them on in Postavke keeps its
address and trips in `/push/<uid>`, which only that phone and the sender can read. The
sender is an anonymous Firebase user; its uid is in the rules. Secrets `VAPID_PRIVATE` and
`ROBOT_TOKEN` live in GitHub only, never in the repo, and run logs are public, so the tool
prints only counts. iPhones need iOS 16.4+ and the app on the home screen. GitHub turns
scheduled runs off after 60 days with no activity in the repo. To send a test message,
change `.github/test-notification` and push; this machine cannot run it itself, because
Dart here does not trust the certificate of Apple's push service.

Instant sending would need a server, so `.github/workflows/events.yml` runs
`tool/remind.dart --events` every 5 minutes, which GitHub often stretches: news arrives
late, not at once. It compares each trip with `/push/_robot/<trip>` and tells the group
about new polls, Plan napada items, votes and days agreed, new photos (one message per
person), people coming and going, and each person about reactions and comments on
their photos and comments (`lib/src/domain/trip_events.dart`, `newsFor`).

Each kind (`Notice`) can be turned off for every trip in Postavke (`/push/<uid>/off`) or for
one trip in its settings (`/push/<uid>/trips/<trip>/off`); the phone keeps the choice in
`AppData.noticesOff` and `tripNoticesOff` and sends it with its address. A kind added later
needs a new `newsVersion` mark, or the first run would send the whole past of every trip.

## Not done yet

0. NEXT (asked 2026-11-08 for "tomorrow"): instant notifications through a free
   Cloudflare Worker (no card). The phone that changes something calls the Worker; it
   checks the caller is a member (Firebase ID token), reads `/push`, and sends web push
   at once, for every Notice kind. `VAPID_PRIVATE` and `ROBOT_TOKEN` become Worker
   secrets the user pastes; the user makes the Cloudflare account. The GitHub robot stays
   for reminders and as a fallback.
1. Automatic lists of places from Google Places: needs a billing account with a card, and
   the key kept behind a server function, which also needs Blaze.
2. Automatic hotel prices (SerpApi account, server function).
3. `offerScore` in `lib/src/domain/offers.dart`: the group's weights for the "Preporuka"
   mark are still the user's to decide.

## Publishing

The repo is `sirrikard38-wq/virulja` (public, branch `main`). Every push to `main` tests
the code and deploys it to https://sirrikard38-wq.github.io/virulja/ . Push only as the
GitHub account `sirrikard38-wq`; a browser may be signed in to another account. Commit
identity: `PK Normal`, `sirrikard38-wq@users.noreply.github.com`. Never the user's
personal email: the repo is public.
