import PouchDB from 'pouchdb'

const COUCH_BASE = 'https://couch.ternpike.com'

export function attachPouch(app, { creds = null } = {}) {
  const db = new PouchDB('ternpike', { auto_compaction: true })
  db.compact().catch(err => console.warn('compact:', err))

  let syncHandle = null

  const emitSync = state =>
    app.ports.pouchIn.send({ tag: 'SyncState', state })

  function startSync({ email, password, dbName }) {
    if (syncHandle) syncHandle.cancel()
    emitSync('syncing')
    const url   = `${COUCH_BASE}/${dbName}`
    const basic = 'Basic ' + btoa(`${email}:${password}`)
    const remote = new PouchDB(url, {
      skip_setup: true,
      fetch: (u, opts) => {
        const o = { ...opts }
        o.headers = new Headers(o.headers || {})
        o.headers.set('Authorization', basic)
        return PouchDB.fetch(u, o)
      },
    })
    syncHandle = db.sync(remote, { live: true, retry: true })
      .on('change',  () => emitSync('syncing'))
      .on('paused',  err => emitSync(err ? 'error' : 'synced'))
      .on('active',  () => emitSync('syncing'))
      .on('denied',  () => emitSync('error'))
      .on('error',   err =>
        emitSync(err && (err.status === 401 || err.status === 403) ? 'auth_error' : 'error')
      )
  }

  function stopSync() {
    if (syncHandle) { syncHandle.cancel(); syncHandle = null }
    emitSync('not_enabled')
  }

  // ── Live changes feed: per-doc updates ─────────────────────────────────
  // Drops _rev and forwards the doc; the Elm DocChange decoder discriminates
  // on doc.type to produce a typed variant.
  db.changes({
    since: 'now',
    live: true,
    include_docs: true,
  }).on('change', change => {
    if (change.deleted) {
      app.ports.pouchIn.send({ tag: 'DbDeleted', id: change.id })
    } else if (change.doc) {
      const { _rev, ...doc } = change.doc
      app.ports.pouchIn.send({ tag: 'DbChange', doc })
    }
  }).on('error', err => {
    app.ports.pouchIn.send({ tag: 'DbError', message: String(err) })
  })

  // ── Outbound port: batched fetches & saves ─────────────────────────────
  app.ports.pouchOut.subscribe(async (msg) => {
    try {
      switch (msg.tag) {

        case 'GetAllTrips': {
          // Group all trip docs into one dict keyed by _id; emit one message.
          const result = await db.allDocs({ include_docs: true })
          const trips = {}
          for (const row of result.rows) {
            const d = row.doc
            if (!d || d.type !== 'trip') continue
            const { _rev, ...doc } = d
            trips[d._id] = doc
          }
          app.ports.pouchIn.send({ tag: 'TripsLoaded', trips })
          break
        }

        case 'GetTripExpenses': {
          // Group expenses (for this trip) + amendments + voids targeting any
          // expense into three dicts; emit one message. Elm decodes straight
          // into Dicts via D.dict.
          const result = await db.allDocs({ include_docs: true })
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
            tag: 'TripExpensesLoaded',
            tripId: msg.tripId,
            amendments, expenses, voids,
          })
          break
        }

        case 'GetExpense': {
          // Targeted single-doc fetch + range-query amendments + lookup void.
          // App-written amend IDs are `amend::expense::<id>::<ts>`, so the
          // range scan finds them. (Seed data must match this scheme.)
          const id = msg.expenseId
          let expense = null
          let voidDoc = null

          try {
            const exp = await db.get(id)
            const { _rev, ...doc } = exp
            expense = doc
          } catch (e) {
            if (e.status !== 404) throw e
          }

          const amendRows = await db.allDocs({
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
            const v = await db.get(`void::${id}::del`)
            const { _rev, ...doc } = v
            voidDoc = doc
          } catch (e) {
            if (e.status !== 404) throw e
          }

          app.ports.pouchIn.send({
            tag: 'ExpenseLoaded',
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
          const doc = msg.doc
          try {
            const existing = await db.get(doc._id)
            await db.put({ ...doc, _rev: existing._rev })
          } catch (e) {
            if (e.status === 404) {
              await db.put(doc)
            } else {
              throw e
            }
          }
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

  app.ports.startSync.subscribe(startSync)
  app.ports.stopSync.subscribe(stopSync)

  if (creds) startSync(creds)
}
