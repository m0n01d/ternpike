/***
Typed bindings for the Node builtins the admin CLI needs (process, fs, path,
os, child_process). Only the slice in use is bound; extend with the same
no-`%raw`, no-escape-hatch rule.
*/

module Process = {
  @val @scope("process") external env: Dict.t<string> = "env"
  @val @scope("process") external argv: array<string> = "argv"
  @val @scope("process") external cwd: unit => string = "cwd"
  @val @scope("process") external exit: int => unit = "exit"
}

module Fs = {
  // Throws if the file is missing — callers wrap in a `switch | exception _`.
  @module("node:fs")
  external readFileSync: (string, string) => string = "readFileSync"
  @module("node:fs")
  external writeFileSync: (string, string, string) => unit = "writeFileSync"
  @module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
}

module Path = {
  @module("node:path") external join: (string, string) => string = "join"
}

module Os = {
  @module("node:os") external tmpdir: unit => string = "tmpdir"
}

module ChildProcess = {
  type options = {stdio: string}
  type result = {status: Nullable.t<int>}
  // Synchronous spawn — blocks until the child (e.g. $EDITOR) exits. Simpler
  // than the async event-emitter form for a CLI that wants to wait anyway.
  @module("node:child_process")
  external spawnSync: (string, array<string>, options) => result = "spawnSync"
}
