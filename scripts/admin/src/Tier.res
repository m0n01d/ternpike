/***
The three subscription tiers, mirrored from `Data.Tier` (Elm) and the server's
`VALID_TIERS`. `label` is the wire string the API expects.
*/

type t =
  | Osprey
  | Tern
  | Trailblazer

let label = (tier: t): string =>
  switch tier {
  | Osprey => "osprey"
  | Tern => "tern"
  | Trailblazer => "trailblazer"
  }

// Iteration/seed order: free → paid → permanent.
let all: array<t> = [Tern, Osprey, Trailblazer]
