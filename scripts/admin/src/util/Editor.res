/***
$EDITOR-based JSON editing, ported from `util/editor.ts`. Writes the value to a
temp file, opens `$EDITOR` (then `$VISUAL`, then `vi`) via a blocking
`spawnSync` with inherited stdio, and re-parses the result. Returns a `result`
so callers can surface parse/exit failures.

Callers running under Ink should suspend rendering (unmount / `useApp().exit`
boundary or a stdin pause) around this, since the editor takes over the TTY.
*/

let editorCmd = (): string =>
  switch Node.Process.env->Dict.get("EDITOR") {
  | Some(e) if e !== "" => e
  | _ =>
    switch Node.Process.env->Dict.get("VISUAL") {
    | Some(v) if v !== "" => v
    | _ => "vi"
    }
  }

let editJson = (initial: JSON.t, hint: string): result<JSON.t, string> => {
  let dir = Node.Fs.mkdtempSync(Node.Path.join(Node.Os.tmpdir(), "ternpike-admin-"))
  let file = Node.Path.join(dir, hint ++ ".json")
  Node.Fs.writeFileSync(file, JSON.stringify(initial, ~space=2) ++ "\n", "utf8")
  let res = Node.ChildProcess.spawnSync(editorCmd(), [file], {stdio: "inherit"})
  switch res.status->Nullable.toOption {
  | Some(0) =>
    switch Node.Fs.readFileSync(file, "utf8") {
    | content =>
      switch JSON.parseOrThrow(content) {
      | json => Ok(json)
      | exception _ => Error("invalid JSON after edit")
      }
    | exception _ => Error("could not read edited file")
    }
  | _ => Error("editor exited non-zero")
  }
}
