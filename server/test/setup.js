// Global lifecycle helpers consumed by every `[Flock-Sec]` spec.
//
// Use:
//   import { setupHarness, teardownHarness } from '../setup.js'
//   let harness
//   before(async () => { harness = await setupHarness() })
//   after(async () => { await teardownHarness(harness) })
//
// `harness` exposes `{ couch, resend, buildEnv }` so each spec can build a
// fresh env per `beforeEach` (so KV state doesn't leak between tests) while
// reusing the single docker container for the whole suite.

import { startCouch } from './fixtures/couch.js'
import { buildEnv, installResendCapture } from './fixtures/env.js'

export async function setupHarness() {
  const couch = await startCouch()
  const resend = installResendCapture()
  return {
    couch,
    resend,
    buildEnv: (overrides) => buildEnv(couch, overrides),
  }
}

export async function teardownHarness(harness) {
  if (!harness) return
  if (harness.resend) harness.resend.uninstall()
  if (harness.couch) await harness.couch.stop()
}
