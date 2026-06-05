/***
Minimal admin-API client — the slice the dev-tier seeder needs. Talks to the
Hono admin routes with the `x-admin-secret` header (see `server/admin.js`). The
full TUI rewrite will grow this into the complete client (list/get/update/delete
+ dbs + sharedtrips), reusing `Fetch` + `Config`.
*/

type createResult =
  | Created
  | Failed(string)
  | TrailblazerSkip

/* POST /admin/users — provision a user at `tier`. Idempotent: a 201 means the
   record was (re)written; a 409 means the target is already a permanent
   Trailblazer (upsertUser refused the downgrade), which we treat as a benign
   skip rather than an error. */
let createUser = async (email: string, tier: Tier.t): createResult => {
  let headers = Dict.fromArray([
    ("Content-Type", "application/json"),
    ("x-admin-secret", Config.adminSecret),
  ])
  let body = JSON.stringify(
    JSON.Object(
      Dict.fromArray([
        ("email", JSON.String(email)),
        ("tier", JSON.String(Tier.label(tier))),
      ]),
    ),
  )
  try {
    let response = await Fetch.fetch(Config.apiUrl ++ "/admin/users", {
      body,
      headers,
      method: "POST",
    })
    let status = Fetch.status(response)
    if status === 201 {
      Created
    } else if status === 409 {
      TrailblazerSkip
    } else {
      let text = await Fetch.text(response)
      Failed(`HTTP ${Int.toString(status)}: ${text}`)
    }
  } catch {
  // Network / thrown error (e.g. server not running). HTTP-level failures are
  // reported with status + body via the non-2xx branch above.
  | _ => Failed(`request failed (is the server running at ${Config.apiUrl}?)`)
  }
}
