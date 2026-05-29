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

import { signJwt } from './jwt.js'
import {
  readSharedTripMeta,
  sharedTripDbName,
} from './sharedTrips.js'

const encoder = new TextEncoder()

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

// Register the funnel's routes. The redacted-preview, scan-guest, and
// magic-link handlers themselves land in later issues (Wave 1+); this issue
// only wires the module in so the import in index.js resolves and so the CORS
// + route registration ordering is established now. Intentionally a no-op body
// for the moment.
export function registerInviteFunnelRoutes(_app) {
  // Handlers added in #329+ (/invite/resolve, /scan-guest, magic-link).
}
