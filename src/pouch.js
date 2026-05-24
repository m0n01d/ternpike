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
          const trips = {}
          const responses = await Promise.all(
            allHandles().map(async (handle) => {
              const result = await handle.local.allDocs({ include_docs: true })
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
          app.ports.pouchIn.send({ tag: 'TripsLoaded', trips })
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
          const result = await handle.local.allDocs({ include_docs: true })
          const amendments = {}
          const expenses   = {}
          const voids      = {}
          for (const row of result.rows) {
            const d = row.doc
            if (!d) continue
            const { _rev, ...doc } = d
            if (d.type === 'expense' && d.tripId === msg.tripId) {
              expenses[d._id] = doc
            } else if (d.type === 'amend' && d.targetId && typeof d.targetId === 'string' && d.targetId.startsWith('expense::')) {
              amendments[d._id] = doc
            } else if (d.type === 'void' && d.targetId && typeof d.targetId === 'string' && d.targetId.startsWith('expense::')) {
              voids[d._id] = doc
            }
          }
          app.ports.pouchIn.send({
            tag: 'TripExpensesFetched',
            tripId: msg.tripId,
            amendments, expenses, voids,
          })
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
