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

  db.changes({
    since: 'now',
    live: true,
    include_docs: true,
  }).on('change', change => {
    const { _rev, ...doc } = change.doc || {}
    app.ports.pouchIn.send({
      tag:     'DbChange',
      id:      change.id,
      deleted: !!(change.deleted),
      doc,
    })
  }).on('error', err => {
    app.ports.pouchIn.send({ tag: 'DbError', message: String(err) })
  })

  app.ports.pouchOut.subscribe(async (msg) => {
    try {
      switch (msg.tag) {

        case 'GetAllTrips': {
          const result = await db.allDocs({ include_docs: true })
          result.rows.forEach(row => {
            if (!row.doc || row.doc.type !== 'trip') return
            const { _rev, ...doc } = row.doc
            app.ports.pouchIn.send({ tag: 'DbChange', id: row.id, deleted: false, doc })
          })
          app.ports.pouchIn.send({ tag: 'QueryComplete', queryType: 'trips' })
          break
        }

        case 'GetExpenses': {
          const result = await db.allDocs({ include_docs: true })
          result.rows.forEach(row => {
            const d = row.doc
            if (!d) return
            if (
              (d.type === 'expense' && d.tripId === msg.tripId) ||
              (d.type === 'amend'   && d.targetId && d.targetId.startsWith('expense::')) ||
              (d.type === 'void'    && d.targetId && d.targetId.startsWith('expense::'))
            ) {
              const { _rev, ...doc } = d
              app.ports.pouchIn.send({ tag: 'DbChange', id: row.id, deleted: false, doc })
            }
          })
          app.ports.pouchIn.send({ tag: 'QueryComplete', queryType: 'expenses' })
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
