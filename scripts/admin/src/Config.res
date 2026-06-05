/***
Config + `.env` loading for the admin CLI, ported from `src/api.ts`. Reads keys
(`TERNPIKE_API`, `ADMIN_SECRET`, `DEV_SEED_BASE`, …) from the process env first,
then falls back to the first readable `.env` — the path in `TERNPIKE_ADMIN_ENV`,
then `<cwd>/.env`, then `<cwd>/scripts/admin/.env`.
*/

let stripQuotes = (s: string): string =>
  if String.length(s) >= 2 && String.startsWith(s, "\"") && String.endsWith(s, "\"") {
    String.slice(s, ~start=1, ~end=String.length(s) - 1)
  } else {
    s
  }

let parseEnvFile = (raw: string): Dict.t<string> => {
  let out = Dict.make()
  raw
  ->String.split("\n")
  ->Array.forEach(line => {
    let trimmed = String.trim(line)
    if String.length(trimmed) > 0 && !String.startsWith(trimmed, "#") {
      switch String.indexOf(trimmed, "=") {
      | -1 => ()
      | eq =>
        let key = String.slice(trimmed, ~start=0, ~end=eq)->String.trim
        let value =
          String.slice(trimmed, ~start=eq + 1, ~end=String.length(trimmed))
          ->String.trim
          ->stripQuotes
        if String.length(key) > 0 {
          Dict.set(out, key, value)
        }
      }
    }
  })
  out
}

let loadEnvFile = (): Dict.t<string> => {
  let candidates =
    [
      Node.Process.env->Dict.get("TERNPIKE_ADMIN_ENV"),
      Some(Node.Path.join(Node.Process.cwd(), ".env")),
      Some(Node.Path.join(Node.Process.cwd(), "scripts/admin/.env")),
    ]->Array.filterMap(x => x)
  let result = ref(Dict.make())
  let found = ref(false)
  candidates->Array.forEach(path =>
    if !found.contents {
      switch Node.Fs.readFileSync(path, "utf8") {
      | content =>
        result := parseEnvFile(content)
        found := true
      | exception _ => ()
      }
    }
  )
  result.contents
}

let fileEnv = loadEnvFile()

let get = (key: string): option<string> =>
  switch Node.Process.env->Dict.get(key) {
  | Some(v) if String.length(v) > 0 => Some(v)
  | _ => fileEnv->Dict.get(key)
  }

let apiUrl: string = get("TERNPIKE_API")->Option.getOr("http://localhost:4000")
let adminSecret: string = get("ADMIN_SECRET")->Option.getOr("")
