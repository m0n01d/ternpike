// Cache name is stamped with the git SHA at build time so old caches are
// cleaned up on deploy. PRECACHE_URLS is injected at build time from
// dist/assets so the SW knows the hashed JS/CSS filenames it needs to seed
// on install — without this, the very first visit doesn't populate the
// cache (the SW activates *after* the page has already fetched its
// resources, so going offline before a second online visit leaves nothing
// to serve).
const CACHE = '__CACHE_VERSION__';
const PRECACHE_URLS = '__PRECACHE_URLS__';

const APP_SHELL = ['/', '/manifest.json', '/icon-192.png', '/icon-512.png'];

const SKIP_CACHE = [
  'api.ternpike.com',
  'couch.ternpike.com',
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
  event.waitUntil(
    caches.open(CACHE).then(c => {
      const urls = [...APP_SHELL, ...(Array.isArray(PRECACHE_URLS) ? PRECACHE_URLS : [])];
      // Don't let one missing asset fail the whole install.
      return Promise.all(
        urls.map(u => c.add(u).catch(err => console.warn('[sw] precache failed', u, err)))
      );
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('fetch', event => {
  const req = event.request;
  const url = new URL(req.url);

  // Never touch API / auth calls
  if (SKIP_CACHE.some(h => url.href.includes(h))) {
    event.respondWith(fetch(req));
    return;
  }

  // Cache-first for fonts (immutable content-addressed URLs)
  if (STATIC_CACHE_FIRST.some(h => url.hostname.includes(h))) {
    event.respondWith(
      caches.match(req).then(cached => {
        if (cached) return cached;
        return fetch(req).then(response => {
          const clone = response.clone();
          caches.open(CACHE).then(c => c.put(req, clone));
          return response;
        });
      })
    );
    return;
  }

  // Network-first for everything else (index.html, main.js, manifest, icons).
  // Online: always the latest build. Offline: cache fallback, with a final
  // fallback to the cached app shell ('/') for navigation requests so the
  // SPA loads even when the exact requested URL isn't cached.
  event.respondWith(
    fetch(req)
      .then(response => {
        const clone = response.clone();
        caches.open(CACHE).then(c => c.put(req, clone));
        return response;
      })
      .catch(async () => {
        const cached = await caches.match(req);
        if (cached) return cached;
        if (req.mode === 'navigate') {
          const shell = await caches.match('/');
          if (shell) return shell;
        }
        return Response.error();
      })
  );
});

self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) {}
  const title = data.title || 'Ternpike';
  const body  = data.body  || 'Time to scan your receipts.';
  const url   = data.url   || '/trips';
  const tag   = data.tag   || 'weekly-scan-reminder';
  event.waitUntil(self.registration.showNotification(title, {
    badge: '/icon-192.png',
    body,
    data: { url },
    icon: '/icon-192.png',
    tag,
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = (event.notification.data && event.notification.data.url) || '/trips';
  event.waitUntil((async () => {
    const all = await self.clients.matchAll({ includeUncontrolled: true, type: 'window' });
    for (const c of all) {
      if (c.url.includes(self.registration.scope)) {
        c.navigate(target);
        return c.focus();
      }
    }
    return self.clients.openWindow(target);
  })());
});
