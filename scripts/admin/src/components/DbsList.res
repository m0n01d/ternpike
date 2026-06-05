/*** Databases screen — STUB (ported in Phase B). Lists CouchDB dbs; / filter, r refresh, Enter browse. */

@react.component
let make = (
  ~onPick: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let _ = (onPick, setStatus, setError)
  <Ink.Text color="gray"> {React.string("Databases — porting in progress")} </Ink.Text>
}
