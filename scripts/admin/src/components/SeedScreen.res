/*** Seed screen — STUB (ported in Phase B). Quick-seed users + the dev-tier action (SeedDevTiers). */

@react.component
let make = (~setStatus: string => unit, ~setError: option<string> => unit) => {
  let _ = (setStatus, setError)
  <Ink.Text color="gray"> {React.string("Seed — porting in progress")} </Ink.Text>
}
