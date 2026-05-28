#!/usr/bin/env bash
# Wipe one user's server-side state so they restart as a fresh Tern on
# next login. Use during billing-flow testing to reset back to an
# unpaid, untouched account.
#
# Wipes:
#   - TIERS_KV  user:<email>      (user record: tier, stripeCustomerId, etc.)
#   - TIERS_KV  slug:user-<hash>  (referral / QR reverse index)
#   - TIERS_KV  <email>           (legacy raw-string tier key, if any)
#   - CouchDB   ternpike-<sanitized-email>  (synced trip data)
#   - CouchDB   _users/org.couchdb.user:<email>  (sync credentials)
#
# Does NOT wipe:
#   - Browser IndexedDB (PouchDB local docs, auth_creds, BYO API keys).
#     Clear separately via DevTools -> Application -> Clear site data.
#   - Stripe customer / subscription. Use the Stripe Dashboard if needed;
#     in test mode you can just leave them orphaned.
#   - PUSH_KV subscriptions. Add manual deletes here if you enabled push
#     notifications on this account.
#
# Usage:
#   scripts/nuke-user.sh <email>
#
# Requires COUCH_ADMIN_USER + COUCH_ADMIN_PASS in env, or in server/.dev.vars.

set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <email>" >&2
  exit 1
fi

repo_root=$(cd "$(dirname "$0")/.." && pwd)
email=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')

# Mirror server/index.js sanitizeDb(): lowercase, then replace anything
# outside [a-z0-9_$()+/-] with '-'.
db_suffix=$(printf '%s' "$email" | sed 's/[^a-z0-9_$()+/-]/-/g')
db_name="ternpike-${db_suffix}"

# Mirror server/users.js shortHash() + slugFor(): FNV-1a 32-bit hex,
# padded to 8 chars, sliced to first 4, prefixed with 'user-'.
slug=$(node -e '
  const FNV_OFFSET = 2166136261;
  const FNV_PRIME = 16777619;
  let h = FNV_OFFSET;
  const s = process.argv[1];
  for (let i = 0; i < s.length; i++) {
    const xored = (h ^ s.charCodeAt(i)) | 0;
    let m = (xored * FNV_PRIME) % 4294967296;
    if (m < 0) m += 4294967296;
    h = m;
  }
  process.stdout.write("user-" + Math.floor(h).toString(16).padStart(8, "0").slice(0, 4));
' "$email")

# Load CouchDB admin creds if not already in env.
if [ -z "${COUCH_ADMIN_USER:-}" ] || [ -z "${COUCH_ADMIN_PASS:-}" ]; then
  if [ -f "${repo_root}/server/.dev.vars" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${repo_root}/server/.dev.vars"
    set +a
  fi
fi
COUCH_URL="${COUCH_URL:-https://couch.ternpike.com}"

if [ -z "${COUCH_ADMIN_USER:-}" ] || [ -z "${COUCH_ADMIN_PASS:-}" ]; then
  echo "Missing COUCH_ADMIN_USER / COUCH_ADMIN_PASS." >&2
  echo "Set them in env, or in server/.dev.vars, before running." >&2
  exit 1
fi

echo "Target email: ${email}"
echo "  CouchDB db: ${db_name}"
echo "  slug key:   slug:${slug}"
echo

run_kv_delete() {
  local key="$1"
  echo "  TIERS_KV   ${key}"
  (cd "${repo_root}/server" && wrangler kv key delete --binding=TIERS_KV --remote "${key}") \
    >/dev/null 2>&1 \
    && echo "    deleted" \
    || echo "    (not found or already gone)"
}

echo "Wiping TIERS_KV entries..."
run_kv_delete "user:${email}"
run_kv_delete "slug:${slug}"
run_kv_delete "${email}"

echo
echo "Wiping CouchDB database..."
http_status=$(curl -s -o /dev/null -w '%{http_code}' \
  -X DELETE \
  -u "${COUCH_ADMIN_USER}:${COUCH_ADMIN_PASS}" \
  "${COUCH_URL}/${db_name}")
case "$http_status" in
  200|202) echo "  deleted ${db_name}" ;;
  404)     echo "  (${db_name} did not exist)" ;;
  *)       echo "  DELETE ${db_name} returned HTTP ${http_status}" >&2 ;;
esac

echo
echo "Wiping CouchDB sync user..."
user_doc=$(curl -fsS \
  -u "${COUCH_ADMIN_USER}:${COUCH_ADMIN_PASS}" \
  "${COUCH_URL}/_users/org.couchdb.user:${email}" 2>/dev/null || true)
if [ -n "$user_doc" ] && printf '%s' "$user_doc" | grep -q '"_rev"'; then
  rev=$(printf '%s' "$user_doc" | sed -n 's/.*"_rev":"\([^"]*\)".*/\1/p')
  http_status=$(curl -s -o /dev/null -w '%{http_code}' \
    -X DELETE \
    -u "${COUCH_ADMIN_USER}:${COUCH_ADMIN_PASS}" \
    "${COUCH_URL}/_users/org.couchdb.user:${email}?rev=${rev}")
  case "$http_status" in
    200|202) echo "  deleted org.couchdb.user:${email}" ;;
    *)       echo "  DELETE _users returned HTTP ${http_status}" >&2 ;;
  esac
else
  echo "  (org.couchdb.user:${email} did not exist)"
fi

echo
echo "Server-side state nuked. Final step:"
echo "  1. Open app.ternpike.com in your browser"
echo "  2. DevTools -> Application -> Storage -> 'Clear site data'"
echo "  3. Reload and sign in: you will be a fresh Tern."
