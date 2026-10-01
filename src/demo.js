// Demo runtime for /demo — replaces attachPouch.
//
// Subscribes to pouchOut and answers the reads Elm makes (GetAllTrips,
// GetAllTripExpenses, GetTripExpenses) from the in-memory seed in
// demo-data.js. Every read that marks a trip as loading must get a
// TripExpensesFetched reply, or that trip stays on "LOADING…" forever.
// All writes (PutDoc, ChangeOptions, sync, etc.) are silently dropped:
// the demo is read-only. The first SyncState push triggers Elm's
// "first-settle" handler, which fires GetAllTrips.

import { demoSeed } from './demo-data.js'

export function attachDemo(app) {
  const sendTripExpenses = (tripId) => {
    app.ports.pouchIn.send({
      tag: 'TripExpensesFetched',
      tripId,
      expenses: demoSeed.expensesByTrip[tripId] || {},
      amendments: {},
      voids: {},
    })
  }

  app.ports.pouchOut.subscribe((msg) => {
    switch (msg && msg.tag) {
      case 'GetAllTrips': {
        app.ports.pouchIn.send({ tag: 'TripsLoaded', trips: demoSeed.trips })
        break
      }
      case 'GetTripExpenses': {
        sendTripExpenses(msg.tripId)
        break
      }
      case 'GetAllTripExpenses': {
        // Bulk startup load (#445). Mirrors pouch.js: one reply per
        // requested trip, empty bundle included, so Elm's loadingTrips
        // set drains for every trip.
        for (const req of msg.requests || []) {
          sendTripExpenses(req.tripId)
        }
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
