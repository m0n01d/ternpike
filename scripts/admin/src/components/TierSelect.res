/***
Tier picker, ported from TierSelect.tsx. Values cross the SelectInput boundary
as the wire string; `onSelect` maps back to `Tier.t`.
*/

let items: array<Ink.SelectInput.item> = [
  {label: "Tern (free)", value: "tern"},
  {label: "Osprey ($2.99/mo)", value: "osprey"},
  {label: "Trailblazer ($79 one-time)", value: "trailblazer"},
]

let parse = (value: string): Tier.t =>
  switch value {
  | "osprey" => Tier.Osprey
  | "trailblazer" => Tier.Trailblazer
  | _ => Tier.Tern
  }

@react.component
let make = (~current: option<Tier.t>=?, ~onSelect: Tier.t => unit) => {
  let initialIndex = switch current {
  | Some(tier) =>
    let want = Tier.label(tier)
    let idx = items->Array.findIndex(i => i.value === want)
    idx < 0 ? 0 : idx
  | None => 0
  }
  <Ink.SelectInput items initialIndex onSelect={item => onSelect(parse(item.value))} />
}
