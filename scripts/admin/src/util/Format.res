/***
Display formatters ported from `util/format.ts` — byte sizes, tier color/badge,
and truncation. Color via the typed `Picocolors` binding.
*/

let pc = Picocolors.colors

let formatBytes = (n: option<int>): string =>
  switch n {
  | None => "—"
  | Some(b) =>
    if b < 1024 {
      `${Int.toString(b)} B`
    } else if b < 1024 * 1024 {
      `${Float.toFixed(Int.toFloat(b) /. 1024.0, ~digits=1)} KB`
    } else if b < 1024 * 1024 * 1024 {
      `${Float.toFixed(Int.toFloat(b) /. 1024.0 /. 1024.0, ~digits=1)} MB`
    } else {
      `${Float.toFixed(Int.toFloat(b) /. 1024.0 /. 1024.0 /. 1024.0, ~digits=2)} GB`
    }
  }

let tierColor = (tier: string): string =>
  switch tier {
  | "osprey" => pc.green(tier)
  | "trailblazer" => pc.yellow(tier)
  | _ => pc.gray(tier)
  }

let tierBadge = (tier: string): string =>
  switch tier {
  | "osprey" => pc.bgGreen(pc.black(" OSPREY "))
  | "trailblazer" => pc.bgYellow(pc.black(" TRAIL "))
  | _ => pc.inverse(pc.gray(" TERN "))
  }

let truncate = (s: string, n: int): string =>
  if String.length(s) <= n {
    s
  } else {
    String.slice(s, ~start=0, ~end=n - 1) ++ "…"
  }
