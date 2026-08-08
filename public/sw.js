// Cache name is stamped with the git SHA at build time so old caches are
// cleaned up on deploy. PRECACHE_URLS is injected at build time from
// dist/assets so the SW knows the hashed JS/CSS filenames it needs to seed
// on install — without this, the very first visit doesn't populate the
// cache (the SW activates *after* the page has already fetched its
// resources, so going offline before a second online visit leaves nothing
// to serve).
const CACHE = '__CACHE_VERSION__';
const PRECACHE_URLS = '__PRECACHE_URLS__';

const APP_SHELL = ['/', '/manifest.json', '/favicon.svg', '/icon-192.png', '/icon-512.png', '/apple-touch-icon.png'];

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

// The app shell minus '/' — incidental assets whose absence still leaves a
// usable build. '/' plus the hashed entry JS/CSS are handled separately below.
const INCIDENTAL = APP_SHELL.filter(u => u !== '/');

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE).then(async c => {
      // ATOMIC critical set (#477). This install no longer calls
      // `skipWaiting()`, so activation can happen hours later and possibly
      // OFFLINE. A holed precache used to be harmless (activate followed
      // install by milliseconds); now it would strand the user on an
      // unusable generation — and we'd have offered them a toast for it.
      // `addAll` is all-or-nothing: a partial precache fails install, the
      // worker never reaches `waiting`, and no toast is ever offered.
      const critical = ['/', ...(Array.isArray(PRECACHE_URLS) ? PRECACHE_URLS : [])];
      await c.addAll(critical);
      // Icons / manifest stay tolerant: missing ones don't break the app.
      await Promise.all(
        INCIDENTAL.map(u => c.add(u).catch(err => console.warn('[sw] precache failed', u, err)))
      );
    })
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => {
        // Keep the current generation AND the most recent previous one
        // (#477). A user who ignores the update toast can sit on the old
        // worker indefinitely; deleting every non-current cache the moment a
        // new generation activates would leave a failed rollout with nothing
        // to serve offline. `caches.keys()` resolves oldest-first, so the
        // tail of the non-current list is the previous generation.
        const others = keys.filter(k => k !== CACHE);
        const stale = others.slice(0, Math.max(0, others.length - 1));
        return Promise.all(stale.map(k => caches.delete(k)));
      })
      // Keep claiming: `controllerchange` is what the Reload button waits on.
      .then(() => self.clients.claim())
  );
});

self.addEventListener('message', event => {
  if (!event.data) return;
  if (event.data.type === 'SKIP_WAITING') {
    // The ONLY early-activation path now — a user tapping Reload.
    self.skipWaiting();
  }
  if (event.data.type === 'GET_VERSION' && event.ports && event.ports[0]) {
    // Lets the page ask a waiting worker which generation it would serve, so
    // it can suppress the spurious toast a network-first refresh produces
    // (the page is already running the new bundle). See src/main.js.
    event.ports[0].postMessage({ version: CACHE });
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

  // Cache-first for fonts (immutable content-addressed URLs).
  // Scoped to CACHE, not `caches.match` — two generations now coexist for an
  // unbounded window (see `activate`), and the global match searches every
  // cache oldest-first, which would serve the PREVIOUS generation's copy.
  if (STATIC_CACHE_FIRST.some(h => url.hostname.includes(h))) {
    event.respondWith(
      caches.open(CACHE).then(c => c.match(req)).then(cached => {
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
        // Same generation-scoping as the font branch above.
        const c = await caches.open(CACHE);
        const cached = await c.match(req);
        if (cached) return cached;
        if (req.mode === 'navigate') {
          const shell = await c.match('/');
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
