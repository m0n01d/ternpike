// Demo runtime for /demo — replaces attachPouch.
//
// Subscribes to pouchOut and answers the two reads Elm makes on boot
// (GetAllTrips, GetTripExpenses) from the in-memory seed in demo-data.js.
// All writes (PutDoc, ChangeOptions, sync, etc.) are silently dropped:
// the demo is read-only. The first SyncState push triggers Elm's
// "first-settle" handler, which fires GetAllTrips.

import { demoSeed } from './demo-data.js'

export function attachDemo(app) {
  app.ports.pouchOut.subscribe((msg) => {
    switch (msg && msg.tag) {
      case 'GetAllTrips': {
        app.ports.pouchIn.send({ tag: 'TripsLoaded', trips: demoSeed.trips })
        break
      }
      case 'GetTripExpenses': {
        const expenses = demoSeed.expensesByTrip[msg.tripId] || {}
        app.ports.pouchIn.send({
          tag: 'TripExpensesFetched',
          tripId: msg.tripId,
          expenses,
          amendments: {},
          voids: {},
        })
        break
      }
      default:
        // Writes (PutDoc/UpdateDoc/DeleteDoc), sync setup, shared-trip
        // ops — all no-ops in demo mode.
        break
    }
  })

  // Kick off the first-settle handler. Elm uses this to trigger
  // GetAllTrips for the personal handle. queueMicrotask ensures the
  // subscriber on pouchIn is wired before we send.
  queueMicrotask(() => {
    app.ports.pouchIn.send({ tag: 'SyncState', state: 'synced' })
  })
}
