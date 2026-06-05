/***
Minimal typed bindings for the global `fetch` + `Response`. Only the slice the
admin API client uses is bound (a POST with a string body, plus reading the
status and text of the response). No `%raw`, no escape hatches.

The full TUI rewrite will widen `requestInit` (optional body for GET/DELETE,
query strings) and add `json`/`headers` readers — bind on first use.
*/

type response

type requestInit = {
  body: string,
  headers: Dict.t<string>,
  method: string,
}

@val external fetch: (string, requestInit) => promise<response> = "fetch"

@send external text: response => promise<string> = "text"
@get external status: response => int = "status"
