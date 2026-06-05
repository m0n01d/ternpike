/***
Generic admin-API request helpers over `Fetch` + `Config`, with the
`x-admin-secret` header. Screens build their typed calls on `get`/`post`/`put`/
`delete` + `Decode`. A non-2xx response is an `Error` carrying the status + body
text; a thrown/network error is `status: 0`.
*/

type apiError = {
  message: string,
  status: int,
}

let adminHeaders = (): Dict.t<string> =>
  Dict.fromArray([
    ("Content-Type", "application/json"),
    ("x-admin-secret", Config.adminSecret),
  ])

let send = async (
  ~method: string,
  ~path: string,
  ~body: option<string>,
): result<JSON.t, apiError> => {
  try {
    let init: Fetch.requestInit = switch body {
    | Some(b) => {body: b, headers: adminHeaders(), method}
    | None => {headers: adminHeaders(), method}
    }
    let response = await Fetch.fetch(Config.apiUrl ++ path, init)
    let status = Fetch.status(response)
    let text = await Fetch.text(response)
    let json = text === "" ? JSON.Null : JSON.parseOrThrow(text)
    if status >= 200 && status < 300 {
      Ok(json)
    } else {
      Error({message: text, status})
    }
  } catch {
  | _ =>
    Error({
      message: `request failed (is the server running at ${Config.apiUrl}?)`,
      status: 0,
    })
  }
}

let get = (path: string): promise<result<JSON.t, apiError>> =>
  send(~method="GET", ~path, ~body=None)

let post = (path: string, body: JSON.t): promise<result<JSON.t, apiError>> =>
  send(~method="POST", ~path, ~body=Some(JSON.stringify(body)))

let put = (path: string, body: JSON.t): promise<result<JSON.t, apiError>> =>
  send(~method="PUT", ~path, ~body=Some(JSON.stringify(body)))

let delete = (path: string): promise<result<JSON.t, apiError>> =>
  send(~method="DELETE", ~path, ~body=None)
