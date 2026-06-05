/***
Typed bindings for the Node builtins the admin CLI needs (process, fs, path).
Only the slice in use is bound; extend with the same no-`%raw`, no-escape-hatch
rule. Every value crosses the JS boundary through a typed `external`.
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
}

module Path = {
  @module("node:path") external join: (string, string) => string = "join"
}
