# VIRULJA

A trip app for a family or group of friends, used on phones as an installable web
app. Everything the user sees is in Croatian; code and comments are in English. The
user writes in Croatian and is not a programmer: explain things in plain words.

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

The stack and the deploy come from the user's Dartle project: Dart compiled to
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
- The address (`#/p/<trip>/<section>`) is the route, so the phone's back button works.
- Tool icons and the temporary logo: `tool/make_icons.ps1`, `lib/ui/icons.dart`
  (`logoMark`), `web/styles.css` (`--logo`).

## Agreed with the user

- Theme A Maslina, on the design canvas
  https://claude.ai/artifact/LPK38eCE73Kx6HuBepHRob (variants, logos, a clickable
  prototype). Logo 3 Vir is temporary: the user will make the real logo later.
- Photos: one tap on every phone; each person picks from the gallery and the app sorts
  by day. No automatic gallery reading.
- Photos have reactions and comments, one reaction per person.
- Food planning has both: places with a price per person and dishes with prices.
- First version also has: drive calculation, actual costs, who owes whom, voting.

## Limits that were checked (2026-10-31)

- Anthem: it cannot come from a link. Spotify's `play` is not reliable on iPhones and
  YouTube demands a visible player of at least 200x200. So someone uploads the song once
  and the app keeps only the first 10 seconds. iPhones ignore `audio.volume`, so sound
  goes through a gain node of an audio context, started inside the tap that opens the
  trip. Moving around inside a trip never restarts it. It plays on every entry unless the
  speaker is muted; muting is remembered.
- The audio session is `ambient`: the anthem must not stop music or a video already playing
  on the phone. So an iPhone on silent does not play it (`playback` would, but it stops
  other sound).
- The quiet level on a real iPhone is not tested yet.
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
  (`JoinRequest`, kept inside the trip, so no rule change). This is checked by the app, not
  by the database: the code stays the real lock. Changing the code keeps the members. Admins remove people and
  name admins; `/banned/<trip>/<uid>` locks a removed person out. Names and phone numbers
  are entered once per device and changed in Postavke. The WhatsApp button is one tap
  (automatic sending needs the paid Business API). The anthem stays an uploaded file.
- Each value is compared and sent separately (`TripMirror`), so people working at the same
  moment do not overwrite each other, and offline changes wait on the phone.
- The open trip follows the database live through `EventSource`; others are read when the
  app opens or returns to the screen. A redraw waits while someone types, has a form open
  or plays a song, because it would wipe them.
- Removing a trip only takes it off that phone, so nobody can wipe it for the group.
- Pictures and the anthem are base64 strings in `/blobs/<trip>/<id>`, because Cloud
  Storage needs the Blaze plan and a card. A photo takes about 270 KB, so the free 1 GB
  holds about 3,500 photos, and the free 10 GB a month of downloads is shared by the
  group. If they run out, moving pictures to Cloud Storage means Blaze and a card.
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
about new polls, Plan napada items, and each person about reactions and comments on
their photos and comments (`lib/src/domain/trip_events.dart`).

## Not done yet

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
