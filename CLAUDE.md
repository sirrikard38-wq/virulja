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
- `lib/ui/media.dart`: photos are shrunk to about 1 MB; originals stay in the gallery.
- `lib/ui/anthem.dart`: the trip's anthem.
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
  trip. Moving around inside a trip never restarts it; muting is remembered.
- The quiet level on a real iPhone is not tested yet.
- Booking's API needs a partner contract. Airbnb has no public API and forbids scraping:
  do not build a scraper. Google Hotels data through SerpApi (250 free searches a month,
  unofficial) may give automatic prices; whether Booking shows up as a source is untested.

## Not done yet

1. Sharing between phones (accounts, a cloud copy of data and photos). Until then each
   phone has only its own data. The plan is Firebase through its web interface, as Dartle
   does. Cloud Storage needs the Blaze plan, so a Google billing account with a card.
2. Automatic lists of places from Google Places (needs the same billing account), with
   the key kept behind a server function.
3. Automatic hotel prices (SerpApi account, server function).

## Publishing

The repo is `sirrikard38-wq/virulja` (public, branch `main`). Every push to `main` tests
the code and deploys it to https://sirrikard38-wq.github.io/virulja/ . Push only as the
GitHub account `sirrikard38-wq`; a browser may be signed in to another account. Commit
identity: `PK Normal`, `sirrikard38-wq@users.noreply.github.com`. Never the user's
personal email: the repo is public.
