/*** User detail — STUB (ported in Phase B). Full record view; t tier, e edit record, s seed, Enter browse. */

@react.component
let make = (
  ~email: string,
  ~onBack: unit => unit,
  ~onBrowse: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let _ = (email, onBack, onBrowse, setStatus, setError)
  <Ink.Text color="gray"> {React.string("User detail — porting in progress")} </Ink.Text>
}
