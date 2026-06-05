/*** Notifications screen — STUB (ported in Phase B). Push subscribers + per-device prefs; test-push. */

@react.component
let make = (~setStatus: string => unit, ~setError: option<string> => unit) => {
  let _ = (setStatus, setError)
  <Ink.Text color="gray"> {React.string("Notifications — porting in progress")} </Ink.Text>
}
