// CI stamps this with the git SHA on every deploy (sed replaces alaska-v1 → alaska-<sha>)
// so the service worker is always treated as new, triggering a fresh install + cache wipe.
const CACHE = 'alaska-v1';
const PRECACHE = [
  '/',
  '/index.html',
  '/main.js',
  '/manifest.json',
  'https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@400;600;700&display=swap',
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(cache => cache.addAll(PRECACHE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Never cache Google API / Anthropic calls — always go to network
  if (url.hostname.includes('googleapis.com') ||
      url.hostname.includes('anthropic.com') ||
      url.hostname.includes('accounts.google.com')) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Cache-first for app shell assets
  event.respondWith(
    caches.match(event.request).then(cached => cached || fetch(event.request))
  );
});
