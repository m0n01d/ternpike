// Nest invite funnel — server scaffolding (#328).
//
// This module establishes the share-token shape (`typ: "share"`), the
// owner-only share-link mint endpoint, and the revocation primitives the
// downstream funnel issues (`/invite/resolve`, `/scan-guest`, the hardened
// magic-link endpoints) build on. See docs/nest-invite-funnel.md §A and §C.
//
// `verifyJwt` (server/jwt.js) only pins the HEADER `typ: "JWT"`; the PAYLOAD
// `typ` claim is NOT checked by the verifier. Every consumer of a share token
// must therefore assert `payload.typ === 'share'` itself. `assertSharePayload`
// below is the shared guard the funnel endpoints reuse so the pinning is done
// in exactly one place.

import { signJwt, verifyJwt } from './jwt.js'
import {
  readSharedTripDocs,
  readSharedTripMeta,
  sharedTripDbName,
} from './sharedTrips.js'
import {
  ANTHROPIC_BASE_URL,
  ANTHROPIC_VERSION,
  MAX_BASE64_BYTES,
  MAX_TOKENS,
  MODEL,
  SYSTEM_PROMPT,
  parseFirstReceipt,
  utcDateKey,
} from './scanDemo.js'

const encoder = new TextEncoder()

// The redacted-preview gate (docs/nest-invite-funnel.md §F). A single server
// constant for now; a later issue may make it per-trip via
// `sharedtrip:meta.previewGate`. Returned verbatim in the `/invite/resolve`
// teaser so the Elm `Data.GuestPreviewGate` decoder can branch the funnel
// (`view_scan_preview` → full S1→S4; unknown → `ViewOnly`).
export const GUEST_PREVIEW_GATE = 'view_scan_preview'

// Share tokens live 30 days. Long enough to forward around the crew, short
// enough that a leaked link eventually dies even without an explicit revoke.
export const SHARE_TOKEN_EXPIRY_SECONDS = 30 * 24 * 60 * 60

// Where the guest funnel lives on the app. The share token rides in the query
// string; `navigator.share` posts this URL.
const NEST_PREVIEW_URL = 'https://app.ternpike.com/nest'

const bytesToHex = (bytes) => {
  let s = ''
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i].toString(16).padStart(2, '0')
  }
  return s
}

// 12-hex nonce — same RNG style as `randomSharedTripId` in sharedTrips.js
// (6 random bytes → 12 hex chars). Used for the per-token `jti` so a single
// leaked link can be killed via the `INVITE_KV` deny-list without bumping the
// whole-trip epoch.
export const randomJti = () => {
  const bytes = crypto.getRandomValues(new Uint8Array(6))
  return bytesToHex(bytes)
}

// Mint a `typ: "share"` token. Recipient-agnostic (no `inviteeEmail`) — one
// link, anyone can open it. `epoch` is baked in from the trip's current
// `sharedtrip:meta.inviteEpoch` so an owner "reset links" action (which bumps
// the epoch) invalidates every outstanding token at once.
export async function mintShareToken({ env, flockId, inviter, epoch }) {
  const iat = Math.floor(Date.now() / 1000)
  const payload = {
    typ: 'share',
    flockId,
    inviter,
    epoch: typeof epoch === 'number' ? epoch : 0,
    jti: randomJti(),
    iat,
    exp: iat + SHARE_TOKEN_EXPIRY_SECONDS,
  }
  const token = await signJwt(payload, env.SERVER_SECRET)
  return { token, payload }
}

// Build the shareable funnel URL from a minted share token.
export const shareLinkUrl = (token) =>
  `${NEST_PREVIEW_URL}?token=${encodeURIComponent(token)}`

// Magic (passwordless-signup) tokens live 5 minutes (#333). Short-lived,
// single-use, and email-confirmed at redemption — see docs/nest-invite-funnel.md
// §A "Magic token" and §C. The short lifetime is a deliberate hardening (the
// security review called for 5m, not 15m) to shrink the link-interception window.
export const MAGIC_TOKEN_EXPIRY_SECONDS = 5 * 60

// Mint a `typ: "magic"` token. Carries ONLY the recipient email + a per-token
// `jti` nonce for the single-use deny-list. Does NOT carry the invite — the
// share token rides through the magic-link round-trip via the `next` param
// (docs/nest-invite-funnel.md §D) and drives auto-join after signup.
export async function mintMagicToken({ env, email }) {
  const iat = Math.floor(Date.now() / 1000)
  const payload = {
    typ: 'magic',
    email: String(email).toLowerCase(),
    jti: randomJti(),
    iat,
    exp: iat + MAGIC_TOKEN_EXPIRY_SECONDS,
  }
  const token = await signJwt(payload, env.SERVER_SECRET)
  return { token, payload }
}

// Build the magic-link URL the email points at. `appBaseUrl` is the app origin
// (e.g. https://app.ternpike.com); the magic token rides in `token` and the
// opaque share token (or any client continuation) rides in `next`. Both are
// url-encoded. `next` is opaque to the server — the client consumes it.
export function magicLinkUrl(appBaseUrl, token, next) {
  const base = `${appBaseUrl}/auth/magic?token=${encodeURIComponent(token)}`
  if (typeof next === 'string' && next) {
    return `${base}&next=${encodeURIComponent(next)}`
  }
  return base
}

// PURE redemption guard for the magic-link verify path (#333). Takes the raw
// `verifyJwt` result plus the caller-submitted `bodyEmail` and returns a tagged
// outcome the route maps to a status. Factored out so the security-critical
// rules (typ-pinning, email-confirm) are unit-testable without CouchDB:
//
//   verified.ok === false, reason 'expired'  → { ok:false, status:410, error:'expired' }
//   verified.ok === false (any other reason) → { ok:false, status:401, error:'invalid_token' }
//   payload.typ !== 'magic'                   → { ok:false, status:401, error:'invalid_token' }
//   payload.email missing                     → { ok:false, status:401, error:'invalid_token' }
//   bodyEmail missing / mismatched            → { ok:false, status:403, error:'email_mismatch' }
//   otherwise                                 → { ok:true, email, jti, exp }
//
// The email-confirm (`bodyEmail === payload.email`, case-insensitive) is THE
// mitigation for the forwarding login-CSRF (docs/nest-invite-funnel.md §A): a
// forwarded link must not let a third party create an account under the
// original recipient's address. The single-use `jti` deny-list check + write
// happen in the route (they need KV + the env), not here.
export function checkMagicRedemption(verified, bodyEmail) {
  if (!verified || verified.ok !== true) {
    if (verified && verified.reason === 'expired') {
      return { ok: false, status: 410, error: 'expired' }
    }
    return { ok: false, status: 401, error: 'invalid_token' }
  }
  const payload = verified.payload
  if (!payload || payload.typ !== 'magic') {
    return { ok: false, status: 401, error: 'invalid_token' }
  }
  if (typeof payload.email !== 'string' || !payload.email) {
    return { ok: false, status: 401, error: 'invalid_token' }
  }
  if (typeof bodyEmail !== 'string' || !bodyEmail) {
    return { ok: false, status: 403, error: 'email_mismatch' }
  }
  if (bodyEmail.toLowerCase() !== payload.email.toLowerCase()) {
    return { ok: false, status: 403, error: 'email_mismatch' }
  }
  return {
    ok: true,
    email: payload.email,
    jti: typeof payload.jti === 'string' ? payload.jti : null,
    exp: typeof payload.exp === 'number' ? payload.exp : null,
  }
}

// Tagged error consumers throw and the route layer maps to a JSON response.
// `{ status, error }` mirrors the shape every other sharedtrips endpoint
// returns (`c.json({ ok: false, error }, status)`).
export class InviteFunnelError extends Error {
  constructor(status, error) {
    super(error)
    this.status = status
    this.error = error
  }
}

// Pin the payload `typ` claim. `verifyJwt` already checked the header typ and
// the signature/exp; this is the payload-level guard each consumer must run.
// Treating an absent `typ` here as invalid is correct for the SHARE surface —
// legacy email invites (absent typ) flow through `/sharedtrips/join`, not the
// share-token endpoints.
export function assertSharePayload(payload) {
  if (!payload || payload.typ !== 'share') {
    throw new InviteFunnelError(403, 'invalid_token')
  }
  if (typeof payload.flockId !== 'string' || !payload.flockId) {
    throw new InviteFunnelError(403, 'invalid_token')
  }
  return payload
}

// PURE classification of a verified `/sharedtrips/join` token payload into the
// branch the route should run (docs/nest-invite-funnel.md §A/§C). Decides which
// `typ` ⇒ which checks WITHOUT any CouchDB / KV / env access, so the
// branch-selection logic is unit-testable in isolation.
//
//   payload.typ === 'share'                  → recipient-agnostic: NO email
//                                              match; run assertPreviewable
//                                              (epoch/jti revocation + frozen).
//   payload.typ === 'invite' OR absent       → legacy email-bound (incl. 7-day
//                                              tokens in the wild): keep the
//                                              `inviteeEmail === caller.email`
//                                              check + reject frozen.
//   anything else                            → 401 invalid_token_type.
//
// Returns a tagged outcome:
//   { kind: 'share',  flockId }
//   { kind: 'invite', flockId, inviteeEmail }
//   { kind: 'error',  status, error }
//
// The route maps `kind:'error'` to `c.json({ ok:false, error }, status)` and
// runs the membership add for the other two kinds.
export function classifyJoinToken(payload) {
  if (!payload || typeof payload !== 'object') {
    return { kind: 'error', status: 401, error: 'invalid_token' }
  }

  const flockId = payload.flockId
  if (typeof flockId !== 'string' || !flockId) {
    return { kind: 'error', status: 401, error: 'invalid_token' }
  }

  const typ = payload.typ

  if (typ === 'share') {
    return { flockId, kind: 'share' }
  }

  // Legacy email-bound invites: explicit `typ:"invite"` OR an absent `typ`
  // (the 7-day tokens already in the wild carry no payload typ — treat absent
  // as "invite" so they keep working, per docs §A back-compat).
  if (typ === 'invite' || typ === undefined || typ === null) {
    const inviteeEmail = payload.inviteeEmail
    if (typeof inviteeEmail !== 'string' || !inviteeEmail) {
      // A legacy/invite token MUST carry an inviteeEmail to email-match against.
      return { kind: 'error', status: 401, error: 'invalid_token' }
    }
    return { flockId, inviteeEmail, kind: 'invite' }
  }

  // Magic tokens and any future/unknown typ are not valid at the join surface.
  return { kind: 'error', status: 401, error: 'invalid_token_type' }
}

// PURE construction of the 409 already-member response body
// (docs/nest-invite-funnel.md §C). Includes `flockId`, `dbName`, and the trip
// `name` so the client can deep-link straight into the already-joined trip
// instead of dead-ending. `meta.name` may be absent on a legacy trip doc — fall
// back to `null` rather than emitting `undefined` (which JSON.stringify drops).
export function buildAlreadyMemberBody(flockId, dbName, meta) {
  const name = meta && typeof meta.name === 'string' ? meta.name : null
  return {
    dbName,
    error: 'already_member',
    flockId,
    name,
    ok: false,
  }
}

// Resolve a shared trip's meta for an UNAUTHENTICATED funnel caller, mapping a
// missing/nonexistent trip to 403 (not 404) so an attacker cannot enumerate
// trip ids through the public resolve endpoint. Any 404 from CouchDB — or a
// read failure — collapses to a 403 `revoked`, indistinguishable from a real
// revocation. (Distinct from the authenticated `/sharedtrips/*` endpoints,
// which return 404-not-403 to non-members; there the caller is already
// authenticated, so existence-leak is bounded differently.)
export async function readMetaForPreview(env, flockId) {
  const dbName = sharedTripDbName(flockId)
  try {
    return await readSharedTripMeta(env, dbName)
  } catch (err) {
    if (err && err.status === 404) {
      // Anti-enumeration: deleted/nonexistent trip looks identical to a
      // revoked one.
      throw new InviteFunnelError(403, 'revoked')
    }
    // Any other read failure is opaque to the unauthenticated caller too.
    throw new InviteFunnelError(403, 'revoked')
  }
}

// Gate a previewable action (resolve / scan-guest) behind the revocation +
// frozen checks. Throws `InviteFunnelError` on any failure; returns silently
// when the token is still good.
//
//   - epoch mismatch (token epoch ≠ live meta.inviteEpoch) → 403 `revoked`
//   - jti on the KV deny-list (`revoked:<jti>`)            → 403 `revoked`
//   - meta.billingStatus === 'frozen'                      → 403 `trip_frozen`
//
// `meta` is the live `sharedtrip:meta` (read via `readMetaForPreview`, which
// already turned a missing trip into a 403). `tokenEpoch` and `jti` come from
// the verified share-token payload.
export async function assertPreviewable(meta, tokenEpoch, jti, env) {
  if (!meta) {
    // Defense in depth — callers should pass a real meta, but a null here is
    // treated as a nonexistent trip (anti-enumeration).
    throw new InviteFunnelError(403, 'revoked')
  }

  const liveEpoch = typeof meta.inviteEpoch === 'number' ? meta.inviteEpoch : 0
  const claimedEpoch = typeof tokenEpoch === 'number' ? tokenEpoch : 0
  if (claimedEpoch !== liveEpoch) {
    throw new InviteFunnelError(403, 'revoked')
  }

  if (typeof jti === 'string' && jti && env.INVITE_KV) {
    const denied = await env.INVITE_KV.get(`revoked:${jti}`)
    if (denied) {
      throw new InviteFunnelError(403, 'revoked')
    }
  }

  if (meta.billingStatus === 'frozen') {
    throw new InviteFunnelError(403, 'trip_frozen')
  }
}

// Keep the encoder reference alive for the (downstream) endpoints that will
// hash IP / build rate-limit keys; harmless to retain here so the module's
// shape matches the sibling server files that all keep a module-level encoder.
void encoder

// Derive a non-email display name for the inviter. The teaser surfaces a first
// name / friendly handle but NEVER the email (docs/nest-invite-funnel.md §C —
// "first name / display name — NOT the email"). Order of preference:
//   1. an explicit non-email `meta.createdByName` (future-proofing; absent today)
//   2. the local-part of `meta.createdBy`, else `meta.billingOwner`, else the
//      token `inviter` — title-cased, dropping any `+tag`, `.`/`_`/`-` split to
//      the first segment so "alice.smith@x.com" → "Alice".
// Falls back to a generic "A crewmate" when nothing usable is present, so the
// teaser never renders an empty or email-looking inviter.
export function deriveInviterName(meta, tokenInviter) {
  const explicit =
    meta && typeof meta.createdByName === 'string' ? meta.createdByName.trim() : ''
  if (explicit && !explicit.includes('@')) {
    return explicit
  }

  const email =
    (meta && (meta.createdBy || meta.billingOwner)) ||
    tokenInviter ||
    ''
  const local = String(email).split('@')[0] || ''
  // First token before any separator, tag stripped.
  const first = local.split('+')[0].split(/[._-]/)[0] || ''
  if (!first) {
    return 'A crewmate'
  }
  return first.charAt(0).toUpperCase() + first.slice(1)
}

// PURE aggregation: turn the raw shared-trip docs + meta into the redacted
// teaser body (docs/nest-invite-funnel.md §C). No CouchDB, no env, no I/O — so
// it is unit-testable in isolation. `tripDocs` is the flat array of live docs
// (`trip` / `expense` / `amend` / `void`) as returned by `readSharedTripDocs`.
//
// Aggregation mirrors the client's `Data.Entry.resolve` semantics EXACTLY:
//   - voided expenses (a `void` doc whose `targetId` is the expense `_id`) are
//     excluded entirely;
//   - amendments (`amend` docs by `targetId`) are folded newest-wins per field,
//     so the EFFECTIVE `amount`/`date` drive the totals — sorted by `createdAt`.
// `totalSpent` is Float dollars (Money wire shape — the same `amount` units the
// expense doc stores). `entryCount` is the count of effective entries.
// `dayCount` is the number of DISTINCT effective `date` values. `startDate` /
// `endDate` come from the trip doc when non-empty, else the min/max effective
// entry date; when neither is available they are `""` (the DateField "unset"
// wire shape the client decoder maps to epoch).
//
// REDACTION: the output contains ONLY counts/totals/names/date-range +
// `memberCount`. No per-entry rows, merchant, note/longNote, lat/lon, or any
// member email ever appear.
export function buildTeaser(tripDocs, meta) {
  const docs = Array.isArray(tripDocs) ? tripDocs : []
  const trip = docs.find((d) => d && d.type === 'trip') || null

  const expenses = docs.filter((d) => d && d.type === 'expense')
  const amends = docs.filter((d) => d && d.type === 'amend')
  const voids = docs.filter((d) => d && d.type === 'void')

  const voidedIds = new Set(
    voids.map((v) => v && v.targetId).filter((id) => typeof id === 'string'),
  )

  // targetId → amendments, sorted oldest→newest by createdAt (lexicographic on
  // the ISO string == chronological; matches the client's posix sort).
  const amendsByTarget = new Map()
  for (const a of amends) {
    if (!a || typeof a.targetId !== 'string') continue
    if (!amendsByTarget.has(a.targetId)) amendsByTarget.set(a.targetId, [])
    amendsByTarget.get(a.targetId).push(a)
  }
  for (const list of amendsByTarget.values()) {
    list.sort((x, y) => String(x.createdAt).localeCompare(String(y.createdAt)))
  }

  let totalSpent = 0
  let entryCount = 0
  const dates = new Set()

  for (const e of expenses) {
    if (!e || typeof e._id !== 'string') continue
    if (voidedIds.has(e._id)) continue

    // Fold amendments newest-wins (last in the chronological list wins each
    // field it carries). Only amount + date matter for the aggregates.
    let amount = typeof e.amount === 'number' ? e.amount : 0
    let date = typeof e.date === 'string' ? e.date : ''
    const chain = amendsByTarget.get(e._id) || []
    for (const a of chain) {
      if (typeof a.amount === 'number') amount = a.amount
      if (typeof a.date === 'string' && a.date) date = a.date
    }

    totalSpent += amount
    entryCount += 1
    if (date) dates.add(date)
  }

  const sortedDates = Array.from(dates).sort()
  const tripStart =
    trip && typeof trip.startDate === 'string' && trip.startDate
      ? trip.startDate
      : ''
  const tripEnd =
    trip && typeof trip.endDate === 'string' && trip.endDate ? trip.endDate : ''

  const startDate = tripStart || (sortedDates.length ? sortedDates[0] : '')
  const endDate =
    tripEnd || (sortedDates.length ? sortedDates[sortedDates.length - 1] : '')

  const tripName =
    (trip && typeof trip.name === 'string' && trip.name) ||
    (meta && typeof meta.name === 'string' && meta.name) ||
    ''

  const members = meta && Array.isArray(meta.members) ? meta.members : []

  return {
    dayCount: dates.size,
    endDate,
    entryCount,
    gate: GUEST_PREVIEW_GATE,
    inviterName: deriveInviterName(meta, meta && meta.inviter),
    memberCount: members.length,
    startDate,
    // Round to cents so floating-point folds (0.1 + 0.2) don't leak noise.
    totalSpent: Math.round(totalSpent * 100) / 100,
    tripName,
  }
}

// Register the funnel's routes. `/invite/resolve` (this issue, #331) returns
// the redacted teaser. `/scan-guest` and the magic-link handlers land in later
// issues (Wave 1+).
// Per-day caps for the unauthenticated guest scan (#336). Three gates, since a
// share token carries no email to key on: per-token (the link), per-IP, and a
// global circuit-breaker that caps total spend on Ternpike's Anthropic key.
export const SCAN_GUEST_PER_TOKEN_PER_DAY = 3
export const SCAN_GUEST_PER_IP_PER_DAY = 30
export const SCAN_GUEST_GLOBAL_PER_DAY = 500

// PURE rate-limit decision (#336). Given the current daily counts, decide
// whether this scan is allowed. Returns `{ ok:true, remaining }` (remaining =
// per-token scans left AFTER this one) or `{ ok:false }`. No KV/IO — the route
// reads/writes the counters; this only decides, so it is unit-testable.
export function scanGuestRateDecision({ tokenCount, ipCount, globalCount }) {
  const t = Number(tokenCount) || 0
  const i = Number(ipCount) || 0
  const g = Number(globalCount) || 0
  if (t >= SCAN_GUEST_PER_TOKEN_PER_DAY) return { ok: false }
  if (i >= SCAN_GUEST_PER_IP_PER_DAY) return { ok: false }
  if (g >= SCAN_GUEST_GLOBAL_PER_DAY) return { ok: false }
  return { ok: true, remaining: SCAN_GUEST_PER_TOKEN_PER_DAY - t - 1 }
}

// The four funnel stages the Elm client tracks (#340). Exported so unit tests
// can assert the allowlist without spinning up the full Hono router.
export const FUNNEL_STAGE_ALLOWLIST = new Set([
  'convert_requested',
  'join_succeeded',
  'nest_preview_viewed',
  'scan_try_succeeded',
])

// PURE allowlist check for `POST /invite/track`. Returns true when `stage` is
// a non-empty string matching one of the four known funnel stages. Exported so
// the stage-validation logic is unit-testable without I/O.
export function isAllowedFunnelStage(stage) {
  return typeof stage === 'string' && stage.length > 0 && FUNNEL_STAGE_ALLOWLIST.has(stage)
}

export function registerInviteFunnelRoutes(app) {
  // POST /invite/resolve — unauthenticated. The share token rides in the body.
  // Returns ONLY the redacted teaser (docs/nest-invite-funnel.md §C).
  //
  // Status contract:
  //   400 token_required          — missing/empty `token`
  //   401 invalid_token           — bad signature / malformed / wrong payload typ
  //   410 expired                 — token past its `exp`
  //   403 revoked | trip_frozen   — epoch/jti revocation, frozen billing,
  //                                 or a missing/nonexistent trip (anti-enumeration)
  //   200 { ok, ...teaser }
  app.post('/invite/resolve', async (c) => {
    const env = c.env

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const token = body && typeof body.token === 'string' ? body.token : ''
    if (!token) {
      return c.json({ ok: false, error: 'token_required' }, 400)
    }

    const verified = await verifyJwt(token, env.SERVER_SECRET)
    if (!verified.ok) {
      // Expired tokens are a distinct, recoverable state for the client (S6 vs
      // a re-fetch). Everything else (signature/alg/malformed) is a flat 401.
      if (verified.reason === 'expired') {
        return c.json({ ok: false, error: 'expired' }, 410)
      }
      return c.json({ ok: false, error: 'invalid_token' }, 401)
    }

    const payload = verified.payload

    // Pin the payload `typ: "share"` claim. The shared `assertSharePayload`
    // throws a 403 `invalid_token`, but for the resolve surface a bad/absent typ
    // is an authentication failure (401), so we check it here and map.
    if (!payload || payload.typ !== 'share') {
      return c.json({ ok: false, error: 'invalid_token' }, 401)
    }
    if (typeof payload.flockId !== 'string' || !payload.flockId) {
      return c.json({ ok: false, error: 'invalid_token' }, 401)
    }

    try {
      const meta = await readMetaForPreview(env, payload.flockId)
      await assertPreviewable(meta, payload.epoch, payload.jti, env)

      const dbName = sharedTripDbName(payload.flockId)
      const docs = await readSharedTripDocs(env, dbName)
      const teaser = buildTeaser(docs, meta)

      return c.json({ ok: true, ...teaser }, 200)
    } catch (err) {
      if (err instanceof InviteFunnelError) {
        return c.json({ ok: false, error: err.error }, err.status)
      }
      // An unexpected read failure is opaque to the unauthenticated caller —
      // collapse to 403 revoked rather than leaking a 500/trip existence.
      console.error('invite/resolve:', err)
      return c.json({ ok: false, error: 'revoked' }, 403)
    }
  })

  // POST /scan-guest — unauthenticated guest receipt scan (#336). Authorized by
  // a share token; rate-limited per-token + per-IP + global; proxied to
  // Ternpike's Anthropic key SERVER-SIDE (the key never reaches the browser —
  // CLAUDE.md critical rule). The parsed result is returned inline and NEVER
  // persisted.
  //
  // Status: 200 { ok, ocr, remaining } | 200 { ok:false, no_receipt }
  //   400 token_required | bad_request ; 401 invalid_token ; 410 expired
  //   403 revoked | trip_frozen ; 413 too_large ; 429 rate_limited ; 502 upstream
  app.post('/scan-guest', async (c) => {
    const env = c.env

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }
    const token = body && typeof body.token === 'string' ? body.token : ''
    const base64 = body && typeof body.base64 === 'string' ? body.base64 : ''
    const mimeType =
      body && typeof body.mimeType === 'string' ? body.mimeType : ''
    if (!token) {
      return c.json({ ok: false, error: 'token_required' }, 400)
    }
    if (!base64 || !mimeType || !mimeType.startsWith('image/')) {
      return c.json({ ok: false, error: 'bad_request' }, 400)
    }
    if (base64.length > MAX_BASE64_BYTES) {
      return c.json({ ok: false, error: 'too_large' }, 413)
    }

    const verified = await verifyJwt(token, env.SERVER_SECRET)
    if (!verified.ok) {
      if (verified.reason === 'expired') {
        return c.json({ ok: false, error: 'expired' }, 410)
      }
      return c.json({ ok: false, error: 'invalid_token' }, 401)
    }
    const payload = verified.payload
    if (
      !payload ||
      payload.typ !== 'share' ||
      typeof payload.flockId !== 'string' ||
      !payload.flockId
    ) {
      return c.json({ ok: false, error: 'invalid_token' }, 401)
    }

    // Revocation / frozen gate — identical to /invite/resolve.
    try {
      const meta = await readMetaForPreview(env, payload.flockId)
      await assertPreviewable(meta, payload.epoch, payload.jti, env)
    } catch (err) {
      if (err instanceof InviteFunnelError) {
        return c.json({ ok: false, error: err.error }, err.status)
      }
      console.error('scan-guest gate:', err)
      return c.json({ ok: false, error: 'revoked' }, 403)
    }

    // Three-gate daily rate limit (no invitee email to key on).
    const date = utcDateKey()
    const jti =
      typeof payload.jti === 'string' && payload.jti ? payload.jti : 'nojti'
    const ip =
      c.req.header('cf-connecting-ip') ||
      c.req.header('x-forwarded-for') ||
      'unknown'
    const kv = env.INVITE_KV
    const tokenKey = `scan-guest:${jti}:${date}`
    const ipKey = `scan-guest-ip:${ip}:${date}`
    const globalKey = `scan-guest:global:${date}`

    let tokenCount = 0
    let ipCount = 0
    let globalCount = 0
    if (kv) {
      const [t, i, g] = await Promise.all([
        kv.get(tokenKey),
        kv.get(ipKey),
        kv.get(globalKey),
      ])
      tokenCount = parseInt(t || '0', 10) || 0
      ipCount = parseInt(i || '0', 10) || 0
      globalCount = parseInt(g || '0', 10) || 0
    }
    const decision = scanGuestRateDecision({ tokenCount, ipCount, globalCount })
    if (!decision.ok) {
      return c.json({ ok: false, error: 'rate_limited' }, 429)
    }

    // Proxy to Anthropic with the SERVER-SIDE key.
    const anthropicBase = env.ANTHROPIC_BASE_URL || ANTHROPIC_BASE_URL
    let res
    try {
      res = await fetch(`${anthropicBase}/v1/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': env.ANTHROPIC_API_KEY,
          'anthropic-version': ANTHROPIC_VERSION,
        },
        body: JSON.stringify({
          max_tokens: MAX_TOKENS,
          messages: [
            {
              role: 'user',
              content: [
                {
                  type: 'image',
                  source: {
                    type: 'base64',
                    media_type: mimeType,
                    data: base64,
                  },
                },
                {
                  type: 'text',
                  text: 'Extract expense info from every receipt visible in this image.',
                },
              ],
            },
          ],
          model: MODEL,
          system: SYSTEM_PROMPT,
        }),
      })
    } catch (err) {
      console.error('scan-guest upstream fetch error:', err)
      return c.json({ ok: false, error: 'upstream' }, 502)
    }
    if (!res.ok) {
      console.error('scan-guest upstream non-ok:', res.status)
      return c.json({ ok: false, error: 'upstream' }, 502)
    }

    const anthropicBody = await res.json()
    const ocr = parseFirstReceipt(anthropicBody)
    if (!ocr) {
      // Quota not consumed — nothing useful came back.
      return c.json({ ok: false, error: 'no_receipt' }, 200)
    }

    // Consume one scan against all three counters (best-effort).
    if (kv) {
      await Promise.all([
        kv.put(tokenKey, String(tokenCount + 1), { expirationTtl: 86400 }),
        kv.put(ipKey, String(ipCount + 1), { expirationTtl: 86400 }),
        kv.put(globalKey, String(globalCount + 1), { expirationTtl: 86400 }),
      ])
    }

    return c.json({ ok: true, ocr, remaining: Math.max(0, decision.remaining) })
  })

  // POST /invite/track — unauthenticated funnel analytics beacon (#340).
  // Body: { stage, flockId }.  No PII — `stage` is validated against
  // `FUNNEL_STAGE_ALLOWLIST`; unknown stages are silently ignored. `flockId`
  // is received but not stored in the counter key (future use for per-trip
  // breakdowns). Counters are per-stage-per-day, cookie-free.
  //
  // Counter key: `funnel:<stage>:<utcDate>` in `INVITE_KV`, incremented by 1.
  // TTL: 90 days (enough for trend reporting; not indefinite storage).
  // Always returns { ok: true } — failures are swallowed client-side; this
  // endpoint must never block or degrade the funnel.
  app.post('/invite/track', async (c) => {
    const env = c.env

    let body
    try {
      body = await c.req.json()
    } catch {
      body = {}
    }

    const stage = body && typeof body.stage === 'string' ? body.stage.trim() : ''

    // Unknown or missing stages are silently ignored — the server never
    // errors on a beacon so the client funnel is never disrupted.
    if (!isAllowedFunnelStage(stage)) {
      return c.json({ ok: true })
    }

    const kv = env.INVITE_KV
    if (kv) {
      const date = utcDateKey()
      const key = `funnel:${stage}:${date}`
      // Best-effort increment: read → add → write. A race between two
      // simultaneous beacons may drop one count, which is acceptable for
      // analytics (exact precision not required). KV transactions aren't
      // available in Workers.
      const current = parseInt((await kv.get(key)) || '0', 10) || 0
      await kv.put(key, String(current + 1), { expirationTtl: 90 * 24 * 60 * 60 })
    }

    return c.json({ ok: true })
  })
}
