// VIRULJA service worker: lets the app open with no connection.
//
//  * The app shell (page, styles, script, icons) is saved when the worker
//    installs. `__BUILD__` is replaced by tool/build.dart, so every deploy gets
//    its own cache and the old one is deleted.
//  * The page itself is fetched from the network first (so an update shows up
//    as soon as there is one) and from the saved copy when offline.
//  * Everything else from this site is saved the first time it is used.
const BUILD = '__BUILD__';
const CACHE = `virulja-${BUILD}`;
const SHELL = [
  './',
  'index.html',
  `styles.css?v=${BUILD}`,
  `main.dart.js?v=${BUILD}`,
  'manifest.webmanifest',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/apple-touch-icon.png',
  'icons/favicon-32.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(
          keys.filter((key) => key.startsWith('virulja-') && key !== CACHE).map((key) => caches.delete(key)),
        ),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;

  // The page: network first, saved copy when offline. Always checked with the
  // server (cache: 'no-cache'): GitHub Pages lets a browser keep the page for 10
  // minutes, which would show an old version right after an update.
  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request, { cache: 'no-cache' })
        .then((response) => {
          const copy = response.clone();
          caches.open(CACHE).then((cache) => cache.put('index.html', copy));
          return response;
        })
        .catch(() => caches.match('index.html')),
    );
    return;
  }

  // The cloud settings: always ask the server, and use the saved copy only when
  // there is no connection.
  if (new URL(request.url).pathname.endsWith('/online.json')) {
    event.respondWith(
      fetch(request, { cache: 'no-cache' })
        .then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy));
          }
          return response;
        })
        .catch(() => caches.match(request)),
    );
    return;
  }

  // Everything else: the saved copy, else the network (and save it).
  event.respondWith(
    caches.match(request).then(
      (hit) =>
        hit ||
        fetch(request).then((response) => {
          if (response.ok) {
            const copy = response.clone();
            caches.open(CACHE).then((cache) => cache.put(request, copy));
          }
          return response;
        }),
    ),
  );
});
