/***
Confirm dialog, ported from Confirm.tsx. With `expectedAnswer` it requires
typing the phrase then Enter; otherwise y / n / Esc.
*/

@react.component
let make = (
  ~prompt: string,
  ~expectedAnswer: option<string>=?,
  ~onConfirm: unit => unit,
  ~onCancel: unit => unit,
) => {
  let (value, setValue) = React.useState(() => "")

  Ink.useInput((input, key) =>
    if key.escape {
      onCancel()
    } else {
      switch expectedAnswer {
      | None =>
        if key.return || input === "y" {
          onConfirm()
        } else if input === "n" {
          onCancel()
        }
      | Some(_) => ()
      }
    }
  )

  switch expectedAnswer {
  | Some(expected) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text color="yellow"> {React.string(prompt)} </Ink.Text>
      <Ink.Text color="gray">
        {React.string(`type "${expected}" then Enter (Esc cancels)`)}
      </Ink.Text>
      <Ink.TextInput
        value
        onChange={v => setValue(_ => v)}
        onSubmit={v => v === expected ? onConfirm() : onCancel()}
      />
    </Ink.Box>
  | None =>
    <Ink.Box flexDirection=#column>
      <Ink.Text color="yellow"> {React.string(prompt)} </Ink.Text>
      <Ink.Text color="gray">
        {React.string("[ y ] yes · [ n ] no · [ Esc ] cancel")}
      </Ink.Text>
    </Ink.Box>
  }
}
