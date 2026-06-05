/*** Shared trips screen — STUB (ported in Phase B). Lists shared trips w/ billing status; Enter browse. */

@react.component
let make = (
  ~onPick: string => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let _ = (onPick, setStatus, setError)
  <Ink.Text color="gray"> {React.string("Shared trips — porting in progress")} </Ink.Text>
}
