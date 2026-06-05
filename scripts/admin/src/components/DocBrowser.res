/*** Doc browser — STUB (ported in Phase B). Lists docs in a db; e edit ($EDITOR), v void, d hard-delete. */

@react.component
let make = (
  ~db: string,
  ~onBack: unit => unit,
  ~setStatus: string => unit,
  ~setError: option<string> => unit,
) => {
  let _ = (db, onBack, setStatus, setError)
  <Ink.Text color="gray"> {React.string("Doc browser — porting in progress")} </Ink.Text>
}
