/*** QR stickers screen — STUB (ported in Phase B). Slug scan stats; p print, shift-P print all, t template. */

@react.component
let make = (~setStatus: string => unit, ~setError: option<string> => unit) => {
  let _ = (setStatus, setError)
  <Ink.Text color="gray"> {React.string("QR stickers — porting in progress")} </Ink.Text>
}
