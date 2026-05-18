// Cache name is stamped with git SHA by CI — ensures old caches are cleaned up on deploy.
const CACHE = 'alaska-7c3a756060c4b40f42ab051c9de3808a6ab7ebaf';

const SKIP_CACHE = [
  'googleapis.com',
  'anthropic.com',
  'accounts.google.com',
  'gsi/client',
  'unpkg.com',
  'cdn.jsdelivr.net',
  'cdn.tailwindcss.com',
];

const STATIC_CACHE_FIRST = [
  'fonts.googleapis.com',
  'fonts.gstatic.com',
];

self.addEventListener('install', event => {
  // Activate immediately — don't wait for old tabs to close
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  // Delete any old caches from previous deploys
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Never touch API / auth calls
  if (SKIP_CACHE.some(h => url.href.includes(h))) {
    event.respondWith(fetch(event.request));
    return;
  }

  // Cache-first for fonts (immutable content-addressed URLs)
  if (STATIC_CACHE_FIRST.some(h => url.hostname.includes(h))) {
    event.respondWith(
      caches.match(event.request).then(cached => {
        if (cached) return cached;
        return fetch(event.request).then(response => {
          const clone = response.clone();
          caches.open(CACHE).then(c => c.put(event.request, clone));
          return response;
        });
      })
    );
    return;
  }

  // Network-first for everything else (index.html, main.js, manifest, icons).
  // This means: when online you always get the latest build instantly,
  // no cache-clearing needed. Falls back to cache only when offline.
  event.respondWith(
    fetch(event.request)
      .then(response => {
        const clone = response.clone();
        caches.open(CACHE).then(c => c.put(event.request, clone));
        return response;
      })
      .catch(() => caches.match(event.request))
  );
});
