/***
Build and create the three dev-tier accounts (`+tern`/`+osprey`/`+trailblazer`)
from one base gmail address. The `+tag` trick makes each a distinct server
account while every verification code still lands in the base inbox.
*/

/* Splice `+<tier>` before the `@` of `base`:
   addrFor("you@gmail.com", Osprey) == "you+osprey@gmail.com" */
let addrFor = (base: string, tier: Tier.t): string =>
  switch String.indexOf(base, "@") {
  | -1 => base
  | at =>
    let local = String.slice(base, ~start=0, ~end=at)
    let domain = String.slice(base, ~start=at, ~end=String.length(base))
    `${local}+${Tier.label(tier)}${domain}`
  }

type outcome = {
  email: string,
  result: AdminApi.createResult,
  tier: Tier.t,
}

/* Seed each tier sequentially (one provisioning call at a time — kinder to a
   local dev server than a burst). Returns one outcome per tier. */
let seedDevTiers = async (base: string): array<outcome> => {
  let outcomes = []
  for i in 0 to Array.length(Tier.all) - 1 {
    switch Tier.all->Array.get(i) {
    | Some(tier) =>
      let email = addrFor(base, tier)
      let result = await AdminApi.createUser(email, tier)
      outcomes->Array.push({email, result, tier})
    | None => ()
    }
  }
  outcomes
}
