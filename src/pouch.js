import PouchDB from 'pouchdb'

const COUCH_BASE = 'https://couch.ternpike.com'
const PERSONAL_KEY = 'ternpike'

export function attachPouch(app, { creds = null } = {}) {
  const handles = new Map()

  let credsCache = null
  let firstSyncSettled = false

  const emitSync = state =>
    app.ports.pouchIn.send({ tag: 'SyncState', state })

  const logHandles = () => {
    if (import.meta.env.DEV) {
      console.log('[pouch] open handles:', Array.from(handles.keys()))
    }
  }

  function makeRemote(dbName, email, password) {
    const url   = `${COUCH_BASE}/${dbName}`
    const basic = 'Basic ' + btoa(`${email}:${password}`)
    return new PouchDB(url, {
      skip_setup: true,
      fetch: (u, opts) => {
        const o = { ...opts }
        o.headers = new Headers(o.headers || {})
        o.headers.set('Authorization', basic)
        o.credentials = 'omit'
        return PouchDB.fetch(u, o)
      },
    })
  }

  function wireChanges(handle) {
    handle.changes = handle.local.changes({
      since: 'now',
      live: true,
      include_docs: true,
    }).on('change', change => {
      if (change.deleted) {
        app.ports.pouchIn.send({
          tag: 'DbDeleted',
          id: change.id,
          sourceDbName: handle.localName,
        })
      } else if (change.doc) {
        const { _rev, ...doc } = change.doc
        if (handle.localName === PERSONAL_KEY && change.id === 'user:sharedtrips') {
          // Server admin-writes user:sharedtrips on create/join/leave; re-derive
          // the open-handle set on every update so adds and removes both
          // converge without a reload.
          reconcileFlocks(doc).catch(err =>
            console.error('[pouch] reconcileFlocks:', err))
          return
        }
        if (handle.localName === PERSONAL_KEY && change.id === 'milepost::progress') {
          // The earned-marker singleton (#408). Client-written, personal-DB
          // only. Route it as a typed DbChange so the docChangeDecoder's
          // "milepostProgress" arm decodes it. Unlike every other doc here we
          // KEEP `_rev` on the payload — Elm threads it through the next write
          // so PouchDB doesn't 409 on a second save.
          app.ports.pouchIn.send({
            tag: 'DbChange',
            doc: change.doc,
            sourceDbName: handle.localName,
          })
          return
        }
        if (change.id === 'sharedtrip:meta') {
          // Route shared trip metadata up as a typed SharedTripMeta event so Elm can
          // decode it through Data.SharedTrip.decoder rather than the
          // expense/trip-shaped DbChange channel.
          // NOTE: the document's _id is 'sharedtrip:meta' and its type field is
          // 'sharedtrip:meta' (the CouchDB wire type). We match on _id (change.id)
          // rather than doc.type so this works regardless of the type field value.
          app.ports.pouchIn.send({ tag: 'SharedTripMeta', doc })
          return
        }
        const tagged = handle.flockId != null && doc.type === 'trip'
          ? { ...doc, flockId: handle.flockId }
          : doc
        app.ports.pouchIn.send({
          tag: 'DbChange',
          doc: tagged,
          sourceDbName: handle.localName,
        })
      }
    }).on('error', err => {
      app.ports.pouchIn.send({ tag: 'DbError', message: String(err) })
    })
  }

  // Safari's IndexedDB aborts transactions with `indexed_db_went_bad` /
  // "The operation was aborted" when too many operations land on a brand-new
  // PouchDB instance before its IDB connection has fully opened. We used to
  // queue an explicit `local.compact()`, a live `changes()` feed, and a
  // bidirectional `sync()` all on the same tick — Chrome shrugged, Safari
  // choked. Drop the eager compact (`auto_compaction: true` already handles
  // it inline on every write) and `await local.info()` to force the IDB
  // `open()` to settle before we wire changes/sync on top.
  async function openPersonalHandle() {
    if (handles.has(PERSONAL_KEY)) return handles.get(PERSONAL_KEY)
    const local = new PouchDB(PERSONAL_KEY, { auto_compaction: true })
    await local.info()
    const handle = {
      changes: null,
      flockId: null,
      local,
      localName: PERSONAL_KEY,
      remote: null,
      sync: null,
    }
    handles.set(PERSONAL_KEY, handle)
    wireChanges(handle)
    logHandles()
    return handle
  }

  async function openSharedTripHandle(flockId, dbName) {
    const localName = `ternpike-${dbName}`
    if (handles.has(localName)) return handles.get(localName)
    const local = new PouchDB(localName, { auto_compaction: true })
    await local.info()
    const handle = {
      changes: null,
      dbName,
      flockId,
      local,
      localName,
      remote: null,
      sync: null,
    }
    handles.set(localName, handle)
    wireChanges(handle)
    logHandles()
    return handle
  }

  function startHandleSync(handle, dbName) {
    if (!credsCache) return
    if (handle.sync) handle.sync.cancel()
    if (handle.remote) try { handle.remote.close() } catch (_) {}
    const { email, password } = credsCache
    handle.remote = makeRemote(dbName, email, password)
    handle.sync = handle.local.sync(handle.remote, { live: true, retry: true })
      .on('change', () => emitSync('syncing'))
      .on('paused', err => {
        if (handle.localName === PERSONAL_KEY && !firstSyncSettled) {
          firstSyncSettled = true
          // Reading user:flocks after the first paused event avoids racing
          // the initial replication pull. We hydrate on the first pause
          // *regardless of whether sync succeeded*: a freshly logged-in
          // client with a working remote will have pulled the doc by now,
          // and a client without a reachable remote (offline, dev without
          // CouchDB) still has whatever user:flocks doc was put locally —
          // gating on `!err` would silently hide flocks from those users.
          hydrateSharedTripsFromPersonal().catch(e =>
            console.error('[pouch] hydrateSharedTrips:', e))
        }
        emitSync(err ? 'error' : 'synced')
      })
      .on('active', () => emitSync('syncing'))
      .on('denied', () => emitSync('error'))
      .on('error', err =>
        emitSync(err && (err.status === 401 || err.status === 403) ? 'auth_error' : 'error')
      )
  }

  async function hydrateSharedTripsFromPersonal() {
    const personal = handles.get(PERSONAL_KEY)
    if (!personal) return
    let doc
    try {
      doc = await personal.local.get('user:sharedtrips')
    } catch (e) {
      if (e.status === 404) return
      throw e
    }
    await reconcileFlocks(doc)
  }

  async function reconcileFlocks(flocksDoc) {
    if (!credsCache) return
    const entries = Array.isArray(flocksDoc && flocksDoc.flocks)
      ? flocksDoc.flocks
      : []
    const wanted = new Map()
    for (const entry of entries) {
      const flockId = entry.flockId ?? entry.id ?? entry.flock_id
      const dbName  = entry.dbName  ?? entry.db   ?? entry.db_name
      if (!flockId || !dbName) continue
      wanted.set(`ternpike-${dbName}`, { flockId, dbName })
    }

    for (const [localName, handle] of Array.from(handles.entries())) {
      if (localName === PERSONAL_KEY) continue
      if (!wanted.has(localName)) {
        if (handle.sync) handle.sync.cancel()
        if (handle.changes) handle.changes.cancel()
        try { if (handle.remote) handle.remote.close() } catch (_) {}
        try { await handle.local.close() } catch (_) {}
        handles.delete(localName)
        logHandles()
      }
    }

    for (const [localName, { flockId, dbName }] of wanted.entries()) {
      if (!handles.has(localName)) {
        const handle = await openSharedTripHandle(flockId, dbName)
        startHandleSync(handle, dbName)
      }
    }

    // Tell Elm which shared trips the user belongs to right now so it can drop
    // any cached entries for shared trips they've left.
    app.ports.pouchIn.send({
      tag: 'SharedTripsReconciled',
      flockIds: Array.from(wanted.values()).map(w => w.flockId),
    })

    // Best-effort initial hydration of sharedtrip:meta from each shared trip's local DB.
    // The live-changes feed will keep them up to date afterwards.
    for (const [localName, { flockId }] of wanted.entries()) {
      const handle = handles.get(localName)
      if (!handle) continue
      handle.local.get('sharedtrip:meta').then(meta => {
        const { _rev, ...doc } = meta
        app.ports.pouchIn.send({ tag: 'SharedTripMeta', doc })
      }).catch(err => {
        if (err && err.status === 404) return
        console.warn('[pouch] sharedtrip:meta get failed', flockId, err)
      })
    }
  }

  async function startSync({ email, password, dbName }) {
    credsCache = { dbName, email, password }
    firstSyncSettled = false
    emitSync('syncing')
    const personal = await openPersonalHandle()
    startHandleSync(personal, dbName)
    // Local-first early render: hand Elm whatever trips are already on disk
    // immediately, WITHOUT waiting for the first sync round-trip to settle.
    // On a weak connection the initial replication can take many seconds; the
    // user's trips are already local, so blocking the list behind the wire
    // defeats the point of an offline-first app. The authoritative
    // `GetAllTrips` (fired by Elm on the first settled sync edge) follows and
    // folds in anything pulled from remote, plus shared-trip handles.
    //
    // Deferred one macrotask so we don't stack a cursor scan onto the freshly
    // opened IndexedDB connection on the same tick it wired changes + sync —
    // that op-pileup is exactly the Safari `indexed_db_went_bad` abort
    // openPersonalHandle was restructured to avoid (see its comment).
    setTimeout(() => {
      sendTrips('TripsPrefetched').catch(err =>
        console.error('[pouch] early trips read:', err))
    }, 0)
    // Eagerly hydrate shared trips from whatever's already in local PouchDB.
    // The paused-event handler will also call this when initial sync
    // settles — that's the canonical path for fresh sign-ins where
    // user:sharedtrips arrives via replication. This early call handles
    // already-seeded users (offline, dev-without-remote, returning
    // sessions) so shared trips render even when sync can't reach the wire.
    hydrateSharedTripsFromPersonal().catch(e =>
      console.error('[pouch] hydrateSharedTrips (eager):', e))
  }

  function stopSync() {
    for (const handle of handles.values()) {
      if (handle.sync) { handle.sync.cancel(); handle.sync = null }
      if (handle.changes) { handle.changes.cancel(); handle.changes = null }
      try { if (handle.remote) handle.remote.close() } catch (_) {}
      handle.remote = null
    }
    emitSync('not_enabled')
  }

  async function teardownAll({ destroy }) {
    const list = Array.from(handles.values())
    handles.clear()
    for (const handle of list) {
      if (handle.sync) { try { handle.sync.cancel() } catch (_) {} }
      if (handle.changes) { try { handle.changes.cancel() } catch (_) {} }
      try { if (handle.remote) handle.remote.close() } catch (_) {}
      try {
        if (destroy) await handle.local.destroy()
        else await handle.local.close()
      } catch (e) {
        console.warn('[pouch] teardown:', e)
      }
    }
    credsCache = null
    firstSyncSettled = false
    emitSync('not_enabled')
    logHandles()
  }

  function targetHandle(target) {
    if (!target || target.kind === 'Personal' || target.kind === 'personal') {
      return handles.get(PERSONAL_KEY)
    }
    if (target.kind === 'InFlock' || target.kind === 'inFlock') {
      for (const handle of handles.values()) {
        if (handle.flockId != null && handle.flockId === target.flockId) {
          return handle
        }
      }
    }
    // Elm hasn't been updated yet (lands in #60); default writes/reads to
    // the personal handle so existing solo behaviour is preserved.
    return handles.get(PERSONAL_KEY)
  }

  function allHandles() {
    return Array.from(handles.values())
  }

  // Read one handle's expense/amend/void docs with key-range scans instead
  // of a whole-database `allDocs`. Doc ids are prefixed (`expense::`,
  // `amend::expense::`, `void::expense::`), so a startkey/endkey range is a
  // bounded cursor seek over the by-id index rather than a full scan that
  // also deserializes every trip and singleton doc. `￰` is the same
  // high sentinel the GetExpense range below uses.
  //
  // Amendments and voids are returned UN-scoped by trip — exactly as the
  // legacy per-trip path did — because an `amend`/`void` doc carries only a
  // `targetId` (the expense id), not a `tripId`. Callers broadcast the full
  // amend/void maps to every trip and let Elm resolve which apply. Only
  // expenses are bucketed, by their `tripId` field.
  async function readExpenseBundle(handle) {
    const [expRows, amendRows, voidRows] = await Promise.all([
      handle.local.allDocs({ include_docs: true, startkey: 'expense::', endkey: 'expense::￰' }),
      handle.local.allDocs({ include_docs: true, startkey: 'amend::expense::', endkey: 'amend::expense::￰' }),
      handle.local.allDocs({ include_docs: true, startkey: 'void::expense::', endkey: 'void::expense::￰' }),
    ])

    const amendments = {}
    for (const row of amendRows.rows) {
      const d = row.doc
      if (!d || d.type !== 'amend') continue
      const { _rev, ...doc } = d
      amendments[d._id] = doc
    }

    const voids = {}
    for (const row of voidRows.rows) {
      const d = row.doc
      if (!d || d.type !== 'void') continue
      const { _rev, ...doc } = d
      voids[d._id] = doc
    }

    const expensesByTrip = new Map()
    for (const row of expRows.rows) {
      const d = row.doc
      if (!d || d.type !== 'expense') continue
      const { _rev, ...doc } = d
      let bucket = expensesByTrip.get(d.tripId)
      if (!bucket) {
        bucket = {}
        expensesByTrip.set(d.tripId, bucket)
      }
      bucket[d._id] = doc
    }

    return { amendments, expensesByTrip, voids }
  }

  // Read every open handle's trip docs (range-scoped to `trip::`) and send
  // them to Elm under `tag`. Used twice: the authoritative `GetAllTrips`
  // (tag 'TripsLoaded') fired by Elm on the first settled sync edge, and the
  // local-first early read (tag 'TripsPrefetched') fired from startSync
  // before sync settles, so the list renders from on-disk data without
  // waiting on the network. `flockId` is sourced from the handle, never the
  // doc (the personal handle's is null).
  async function sendTrips(tag) {
    const trips = {}
    const responses = await Promise.all(
      allHandles().map(async (handle) => {
        const result = await handle.local.allDocs({
          include_docs: true,
          startkey: 'trip::',
          endkey: 'trip::￰',
        })
        return { handle, rows: result.rows }
      })
    )
    for (const { handle, rows } of responses) {
      for (const row of rows) {
        const d = row.doc
        if (!d || d.type !== 'trip') continue
        const { _rev, ...doc } = d
        trips[d._id] = { ...doc, flockId: handle.flockId }
      }
    }
    app.ports.pouchIn.send({ tag, trips })
  }

  async function upsertDoc(handle, doc) {
    try {
      const existing = await handle.local.get(doc._id)
      await handle.local.put({ ...doc, _rev: existing._rev })
    } catch (e) {
      if (e.status === 404) {
        await handle.local.put(doc)
      } else {
        throw e
      }
    }
  }

  app.ports.pouchOut.subscribe(async (msg) => {
    try {
      switch (msg.tag) {

        case 'GetAllTrips': {
          await sendTrips('TripsLoaded')
          break
        }

        case 'OpenSharedTrip': {
          // Targeted open used by the New Trip form when the user creates a
          // brand-new shared trip: we open the sharedtrip-local PouchDB
          // immediately rather than waiting for reconcileFlocks to fire off
          // the personal-DB sync round-trip. Idempotent — openSharedTripHandle
          // no-ops on a name already in `handles`.
          if (msg.flockId && msg.dbName) {
            const handle = await openSharedTripHandle(msg.flockId, msg.dbName)
            if (handle && !handle.sync) {
              startHandleSync(handle, msg.dbName)
            }
          }
          break
        }

        case 'GetTripExpenses': {
          const handle = targetHandle(msg.target)
          if (!handle) break
          const { amendments, expensesByTrip, voids } = await readExpenseBundle(handle)
          app.ports.pouchIn.send({
            tag: 'TripExpensesFetched',
            tripId: msg.tripId,
            amendments,
            expenses: expensesByTrip.get(msg.tripId) || {},
            voids,
          })
          break
        }

        case 'GetAllTripExpenses': {
          // One-time startup load of every trip's expenses (backs milepost
          // evaluation). Group the requested trips by their backing handle
          // so each PouchDB is scanned ONCE, then reply with one
          // `TripExpensesFetched` per requested trip — including an empty
          // bundle for trips with no expenses, so Elm's `loadingTrips`
          // quiescence accounting drains for every requested trip.
          const byHandle = new Map()
          for (const req of msg.requests || []) {
            const handle = targetHandle(req.target)
            if (!handle) continue
            let ids = byHandle.get(handle)
            if (!ids) {
              ids = new Set()
              byHandle.set(handle, ids)
            }
            ids.add(req.tripId)
          }

          await Promise.all(
            Array.from(byHandle.entries()).map(async ([handle, tripIds]) => {
              const { amendments, expensesByTrip, voids } = await readExpenseBundle(handle)
              for (const tripId of tripIds) {
                app.ports.pouchIn.send({
                  tag: 'TripExpensesFetched',
                  tripId,
                  amendments,
                  expenses: expensesByTrip.get(tripId) || {},
                  voids,
                })
              }
            })
          )
          break
        }

        case 'GetExpense': {
          const handle = targetHandle(msg.target)
          if (!handle) break
          const id = msg.expenseId
          let expense = null
          let voidDoc = null

          try {
            const exp = await handle.local.get(id)
            const { _rev, ...doc } = exp
            expense = doc
          } catch (e) {
            if (e.status !== 404) throw e
          }

          const amendRows = await handle.local.allDocs({
            startkey: `amend::${id}`,
            endkey:   `amend::${id}￰`,
            include_docs: true,
          })
          const amendments = {}
          for (const row of amendRows.rows) {
            if (!row.doc) continue
            const { _rev, ...doc } = row.doc
            amendments[row.id] = doc
          }

          try {
            const v = await handle.local.get(`void::${id}::del`)
            const { _rev, ...doc } = v
            voidDoc = doc
          } catch (e) {
            if (e.status !== 404) throw e
          }

          app.ports.pouchIn.send({
            tag: 'ExpenseFetched',
            expenseId: id,
            amendments,
            expense,
            void: voidDoc,
          })
          break
        }

        case 'SaveTrip':
        case 'SaveExpense':
        case 'SaveAmend':
        case 'SaveVoid': {
          const handle = targetHandle(msg.target)
          if (!handle) break
          await upsertDoc(handle, msg.doc)
          break
        }

        case 'SaveMilepostProgress': {
          // Singleton in the personal DB (no TripTarget). upsertDoc resolves
          // the current `_rev` itself, so a stale/absent `_rev` on msg.doc is
          // harmless. Saved doc echoes back through the change feed (with
          // `_rev`) as a milepostProgress DbChange.
          const handle = handles.get(PERSONAL_KEY)
          if (!handle) break
          await upsertDoc(handle, msg.doc)
          break
        }

        default:
          console.warn('Unknown pouchOut tag:', msg.tag)
      }
    } catch (err) {
      console.error('pouchOut error:', err)
      app.ports.pouchIn.send({ tag: 'DbError', message: String(err) })
    }
  })

  app.ports.startSync.subscribe(c =>
    startSync(c).catch(err => console.error('[pouch] startSync:', err)))
  app.ports.stopSync.subscribe(stopSync)
  app.ports.clearStorage.subscribe(() => {
    teardownAll({ destroy: true }).catch(err =>
      console.error('[pouch] clearStorage teardown:', err))
  })
  app.ports.clearAllStorage.subscribe(() => {
    teardownAll({ destroy: true }).catch(err =>
      console.error('[pouch] clearAllStorage teardown:', err))
  })

  if (creds) startSync(creds).catch(err =>
    console.error('[pouch] initial startSync:', err))
}
