/***
Minimal typed bindings for the global `fetch` + `Response`. `body` is optional
so GET/DELETE can omit it. No `%raw`, no escape hatches. JSON read is done by
the caller (`Req`) via `text` + `JSON.parseExn`.
*/

type response

type requestInit = {
  body?: string,
  headers: Dict.t<string>,
  method: string,
}

@val external fetch: (string, requestInit) => promise<response> = "fetch"

@send external text: response => promise<string> = "text"
@get external status: response => int = "status"
