/***
CLI entry for `npm run seed:dev-tiers`. Reads the base email from
`DEV_SEED_BASE` (env or `scripts/admin/.env`) or the first CLI argument, then
provisions the three dev-tier accounts. Exit code is non-zero if any failed.
*/

let resultLabel = (r: AdminApi.createResult): string =>
  switch r {
  | Created => "created"
  | Failed(msg) => `FAILED — ${msg}`
  | TrailblazerSkip => "skipped (already trailblazer — permanent)"
  }

let usage =
  "seed:dev-tiers — create +tern/+osprey/+trailblazer dev accounts.\n" ++
  "  Set DEV_SEED_BASE=you@gmail.com (or pass it as the first argument).\n" ++
  "  Requires ADMIN_SECRET + TERNPIKE_API (env or scripts/admin/.env)."

let main = async () => {
  let base = switch Config.get("DEV_SEED_BASE") {
  | Some(b) => Some(b)
  | None => Node.Process.argv->Array.get(2)
  }
  switch base {
  | None | Some("") =>
    Console.error(usage)
    Node.Process.exit(1)
  | Some(base) =>
    if Config.adminSecret === "" {
      Console.error("ADMIN_SECRET is not set (env or scripts/admin/.env).")
      Node.Process.exit(1)
    } else {
      Console.log(`Seeding dev-tier accounts from ${base} via ${Config.apiUrl} …`)
      let outcomes = await SeedDevTiers.seedDevTiers(base)
      let anyFailed = ref(false)
      outcomes->Array.forEach(o => {
        switch o.result {
        | Created | TrailblazerSkip => ()
        | Failed(_) => anyFailed := true
        }
        Console.log(
          `  ${o.email} (${Tier.label(o.tier)}) → ${resultLabel(o.result)}`,
        )
      })
      Node.Process.exit(anyFailed.contents ? 1 : 0)
    }
  }
}

main()->ignore
