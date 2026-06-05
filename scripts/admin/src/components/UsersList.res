/*** Users screen — STUB (ported in Phase B). Lists users; t tier, n new, d delete, / filter, r refresh. */

@react.component
let make = (
  ~onPick: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let _ = (onPick, setStatus, setError)
  <Ink.Text color="gray"> {React.string("Users — porting in progress")} </Ink.Text>
}
