// Durable Object that owns the Trailblazer slot counter (1..500). DOs are
// single-threaded by design, which is what gives us the 500-cap atomicity
// guarantee for free — no transactions, no compare-and-swap, no race window.
//
// Stored state (single `state` key in DO storage):
//
//   {
//     confirmed: number,
//     // confirmed slots — count of permanently-claimed Trailblazer numbers.
//     // Monotonically non-decreasing. Once a slot is confirmed it's never
//     // released (Trailblazer is permanent by product rule).
//
//     confirmedNumbers: number[],
//     // sorted ascending list of confirmed slot numbers, used to allocate
//     // the next available number on /reserve.
//
//     reservations: { [token: string]: { email, expiresAt, number } },
//     // outstanding (unconfirmed) reservations. Each holds a slot number
//     // for 30 minutes before the lazy sweep on the next /reserve or
//     // /status reclaims it.
//   }
//
// Endpoints (POST = mutate, GET = read-only):
//   POST /reserve  { email }                       → reserve next slot
//   POST /confirm  { reservationToken, email }     → permanently claim it
//   GET  /status                                   → counts only

const STATE_KEY = 'state'
const TOTAL_SLOTS = 500
const RESERVATION_TTL_MS = 30 * 60 * 1000

const emptyState = () => ({
  confirmed: 0,
  confirmedNumbers: [],
  reservations: {},
})

function jsonResponse(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

// Drop any reservations whose expiresAt is in the past. Mutates `state`.
function sweepExpired(state, now) {
  for (const [token, r] of Object.entries(state.reservations)) {
    if (r.expiresAt <= now) delete state.reservations[token]
  }
}

// Pick the smallest 1..TOTAL_SLOTS not currently in `confirmedNumbers` or
// any active reservation. `confirmedNumbers` is kept sorted.
function nextAvailableNumber(state) {
  const reserved = new Set(state.confirmedNumbers)
  for (const r of Object.values(state.reservations)) reserved.add(r.number)
  for (let n = 1; n <= TOTAL_SLOTS; n++) {
    if (!reserved.has(n)) return n
  }
  return null
}

function activeReservationCount(state) {
  return Object.keys(state.reservations).length
}

function findExistingReservation(state, email) {
  for (const [token, r] of Object.entries(state.reservations)) {
    if (r.email === email) return { token, reservation: r }
  }
  return null
}

export class TrailblazerSlots {
  constructor(state, env) {
    this.state = state
    this.env = env
  }

  async loadState() {
    const stored = await this.state.storage.get(STATE_KEY)
    return stored || emptyState()
  }

  async saveState(next) {
    await this.state.storage.put(STATE_KEY, next)
  }

  async fetch(request) {
    const url = new URL(request.url)
    const path = url.pathname

    if (request.method === 'POST' && path === '/reserve') {
      return this.handleReserve(request)
    }
    if (request.method === 'POST' && path === '/confirm') {
      return this.handleConfirm(request)
    }
    if (request.method === 'GET' && path === '/status') {
      return this.handleStatus()
    }
    return jsonResponse(404, { ok: false, error: 'not_found' })
  }

  async handleReserve(request) {
    let body
    try {
      body = await request.json()
    } catch {
      return jsonResponse(400, { ok: false, error: 'invalid_json' })
    }
    const email =
      typeof body?.email === 'string' ? body.email.toLowerCase() : ''
    if (!email.includes('@')) {
      return jsonResponse(400, { ok: false, error: 'invalid_email' })
    }
    const state = await this.loadState()
    const now = Date.now()
    sweepExpired(state, now)

    const existing = findExistingReservation(state, email)
    if (existing) {
      await this.saveState(state)
      return jsonResponse(200, {
        ok: true,
        number: existing.reservation.number,
        reservationToken: existing.token,
      })
    }

    const taken = state.confirmed + activeReservationCount(state)
    if (taken >= TOTAL_SLOTS) {
      await this.saveState(state)
      return jsonResponse(200, {
        ok: false,
        reason: 'sold_out',
        remaining: 0,
      })
    }

    const number = nextAvailableNumber(state)
    if (number === null) {
      // Defensive — should be unreachable given the `taken >= TOTAL_SLOTS`
      // check above, but if it ever fires we'd rather fail closed than
      // hand out a duplicate slot.
      await this.saveState(state)
      return jsonResponse(200, {
        ok: false,
        reason: 'sold_out',
        remaining: 0,
      })
    }

    const token = crypto.randomUUID()
    state.reservations[token] = {
      email,
      expiresAt: now + RESERVATION_TTL_MS,
      number,
    }
    await this.saveState(state)
    return jsonResponse(200, { ok: true, number, reservationToken: token })
  }

  async handleConfirm(request) {
    let body
    try {
      body = await request.json()
    } catch {
      return jsonResponse(400, { ok: false, error: 'invalid_json' })
    }
    const token =
      typeof body?.reservationToken === 'string' ? body.reservationToken : ''
    const email =
      typeof body?.email === 'string' ? body.email.toLowerCase() : ''
    if (!token || !email.includes('@')) {
      return jsonResponse(400, { ok: false, error: 'invalid_request' })
    }
    const state = await this.loadState()
    const now = Date.now()
    sweepExpired(state, now)

    const reservation = state.reservations[token]
    if (!reservation) {
      await this.saveState(state)
      return jsonResponse(410, {
        ok: false,
        error: 'reservation_expired',
      })
    }
    if (reservation.email !== email) {
      await this.saveState(state)
      return jsonResponse(403, { ok: false, error: 'email_mismatch' })
    }

    delete state.reservations[token]
    state.confirmed += 1
    state.confirmedNumbers.push(reservation.number)
    state.confirmedNumbers.sort((a, b) => a - b)
    await this.saveState(state)
    return jsonResponse(200, { ok: true, number: reservation.number })
  }

  async handleStatus() {
    const state = await this.loadState()
    const now = Date.now()
    sweepExpired(state, now)
    const active = activeReservationCount(state)
    await this.saveState(state)
    return jsonResponse(200, {
      available: TOTAL_SLOTS - state.confirmed - active,
      total: TOTAL_SLOTS,
    })
  }
}
