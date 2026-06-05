/***
QR stickers screen — ported from QrList.tsx.

Fetches `GET /admin/qr` → `{ slugs, templates }`. Displays slug scan stats in a
table. Keys: `p` print selected, `shift-P` print all, `t` cycle template,
`n` new slug, `r` refresh, `enter/esc` back from opened/new sub-views.

Browser-open: uses a local `spawn` external (detached, stdio ignored) so the
print URL opens in the default browser without blocking.
*/

// ---------------------------------------------------------------------------
// Local bindings (async spawn not in shared Node.res)
// ---------------------------------------------------------------------------

type spawnOptions = {
  detached: bool,
  stdio: string,
}

type childProcess

@module("node:child_process")
external spawnDetached: (string, array<string>, spawnOptions) => childProcess = "spawn"

@send external unref: childProcess => unit = "unref"

@module("node:os") external platform: unit => string = "platform"

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type qrSlug = {
  byCity: JSON.t,
  byCountry: JSON.t,
  byRegion: JSON.t,
  count: int,
  firstAt: option<string>,
  lastAt: option<string>,
  slug: string,
}

type template = string // "trailhead" | "sign" | "minimal"

// Named record types for mode payloads (avoids inline-record escape restriction).
type listData = {cursor: int, slugs: array<qrSlug>, template: template}
type newData = {newSlugs: array<qrSlug>, newTemplate: template, value: string}
type openedData = {openedSlugs: array<qrSlug>, openedTemplate: template, url: string}

type mode =
  | Loading
  | List(listData)
  | New(newData)
  | Opened(openedData)

type state = {
  mode: mode,
  reloadTick: int,
}

type msg =
  | FetchDone(array<qrSlug>)
  | FetchFailed(string)
  | MoveCursor(int)
  | SetTemplate(template)
  | EnterNew
  | SetNewValue(string)
  | OpenPrint(string) // url
  | BackToList
  | Reload

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

let defaultTemplates: array<template> = ["trailhead", "sign", "minimal"]

let qrPrintUrl = (slugs: array<string>, tmpl: template): string => {
  let joined = slugs->Array.join(",")
  `${Config.apiUrl}/qr/print?slugs=${joined}&template=${tmpl}`
}

let openInBrowser = (url: string): unit => {
  let p = platform()
  let (cmd, args) = if p === "darwin" {
    ("open", [url])
  } else if p === "win32" {
    ("cmd", ["/c", "start", "", url])
  } else {
    ("xdg-open", [url])
  }
  let child = spawnDetached(cmd, args, {detached: true, stdio: "ignore"})
  unref(child)
}

// Decode a qrSlug from JSON.t
let decodeSlug = (json: JSON.t): option<qrSlug> => {
  switch json {
  | JSON.Object(_) =>
    switch (Decode.stringField(json, "slug"), Decode.intField(json, "count")) {
    | (Some(s), Some(c)) =>
      Some({
        slug: s,
        count: c,
        firstAt: Decode.stringField(json, "firstAt"),
        lastAt: Decode.stringField(json, "lastAt"),
        byRegion: Decode.field(json, "byRegion")->Option.getOr(JSON.Object(Dict.make())),
        byCountry: Decode.field(json, "byCountry")->Option.getOr(JSON.Object(Dict.make())),
        byCity: Decode.field(json, "byCity")->Option.getOr(JSON.Object(Dict.make())),
      })
    | _ => None
    }
  | _ => None
  }
}

// Extract top N entries from a JSON Object (dict of string->number), sorted desc.
let topN = (json: JSON.t, n: int): string => {
  switch json {
  | JSON.Object(d) =>
    let entries =
      Dict.toArray(d)
      ->Array.filterMap(((k, v)) =>
        switch v {
        | JSON.Number(num) => Some((k, Float.toInt(num)))
        | _ => None
        }
      )
      ->Array.toSorted(((_, a), (_, b)) => Int.compare(b, a))
    if Array.length(entries) === 0 {
      "\xe2\x80\x94"
    } else {
      entries
      ->Array.slice(~start=0, ~end=n)
      ->Array.map(((k, v)) => `${k}:${Int.toString(v)}`)
      ->Array.join(" ")
    }
  | _ => "\xe2\x80\x94"
  }
}

let dateOnly = (iso: option<string>): string =>
  switch iso {
  | None => "\xe2\x80\x94"
  | Some(s) => String.slice(s, ~start=0, ~end=10)
  }

let padEnd = (s: string, n: int): string => {
  let len = String.length(s)
  if len >= n {
    s
  } else {
    s ++ String.repeat(" ", n - len)
  }
}

let padStart = (s: string, n: int): string => {
  let len = String.length(s)
  if len >= n {
    s
  } else {
    String.repeat(" ", n - len) ++ s
  }
}

let slugRe = %re("/^[a-z0-9-]{1,32}$/")

// ---------------------------------------------------------------------------
// Reducer
// ---------------------------------------------------------------------------

let init: state = {mode: Loading, reloadTick: 0}

let update = (state: state, msg: msg): state =>
  switch msg {
  | FetchDone(slugs) => {
      ...state,
      mode: List({cursor: 0, slugs, template: "trailhead"}),
    }
  | FetchFailed(_) => {
      ...state,
      mode: List({cursor: 0, slugs: [], template: "trailhead"}),
    }
  | MoveCursor(c) =>
    switch state.mode {
    | List(m) => {...state, mode: List({...m, cursor: c})}
    | _ => state
    }
  | SetTemplate(tmpl) =>
    switch state.mode {
    | List(m) => {...state, mode: List({...m, template: tmpl})}
    | _ => state
    }
  | EnterNew =>
    switch state.mode {
    | List(m) =>
      {...state, mode: New({newSlugs: m.slugs, newTemplate: m.template, value: ""})}
    | _ => state
    }
  | SetNewValue(v) =>
    switch state.mode {
    | New(m) => {...state, mode: New({...m, value: v})}
    | _ => state
    }
  | OpenPrint(url) =>
    switch state.mode {
    | List(m) =>
      {...state, mode: Opened({openedSlugs: m.slugs, openedTemplate: m.template, url})}
    | New(m) =>
      {...state, mode: Opened({openedSlugs: m.newSlugs, openedTemplate: m.newTemplate, url})}
    | _ => state
    }
  | BackToList =>
    switch state.mode {
    | Opened(m) =>
      {...state, mode: List({cursor: 0, slugs: m.openedSlugs, template: m.openedTemplate})}
    | New(m) =>
      {...state, mode: List({cursor: 0, slugs: m.newSlugs, template: m.newTemplate})}
    | _ => state
    }
  | Reload => {mode: Loading, reloadTick: state.reloadTick + 1}
  }

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

@react.component
let make = (~setStatus: string => unit, ~setError: option<string> => unit) => {
  let (state, dispatch) = React.useReducer(update, init)

  // Fetch whenever mode transitions to Loading
  React.useEffect(() => {
    switch state.mode {
    | Loading =>
      let cancelled = ref(false)
      let _ = Req.get("/admin/qr")->Promise.then(result => {
        if !cancelled.contents {
          switch result {
          | Ok(json) =>
            let slugsRaw = Decode.arrayField(json, "slugs")->Option.getOr([])
            let slugs = slugsRaw->Array.filterMap(decodeSlug)
            let n = Array.length(slugs)
            setStatus(`${Int.toString(n)} slug${n === 1 ? "" : "s"}`)
            setError(None)
            dispatch(FetchDone(slugs))
          | Error(e) =>
            setError(Some(e.message))
            dispatch(FetchFailed(e.message))
          }
        }
        Promise.resolve()
      })
      Some(() => {
        cancelled := true
      })
    | _ => None
    }
  }, [state.reloadTick])

  Ink.useInput((input, key) =>
    switch state.mode {
    | List(m) =>
      let n = Array.length(m.slugs)
      if key.upArrow && n > 0 {
        dispatch(MoveCursor(Int.clamp(m.cursor - 1, ~min=0, ~max=n - 1)))
      } else if key.downArrow && n > 0 {
        dispatch(MoveCursor(Int.clamp(m.cursor + 1, ~min=0, ~max=n - 1)))
      } else if input === "r" {
        dispatch(Reload)
      } else if input === "t" {
        let i = defaultTemplates->Array.indexOf(m.template)
        let next =
          defaultTemplates
          ->Array.get(mod(i + 1, Array.length(defaultTemplates)))
          ->Option.getOr("trailhead")
        dispatch(SetTemplate(next))
        setStatus(`template: ${next}`)
      } else if input === "n" {
        dispatch(EnterNew)
      } else if input === "p" && n > 0 {
        switch Array.get(m.slugs, m.cursor) {
        | Some(s) =>
          let url = qrPrintUrl([s.slug], m.template)
          openInBrowser(url)
          setStatus(`opened print page for ${s.slug}`)
          dispatch(OpenPrint(url))
        | None => ()
        }
      } else if key.shift && input === "P" && n > 0 {
        let all = m.slugs->Array.map(s => s.slug)
        let url = qrPrintUrl(all, m.template)
        openInBrowser(url)
        setStatus(`opened print page for ${Int.toString(Array.length(all))} slugs`)
        dispatch(OpenPrint(url))
      }
    | Opened(_) =>
      if key.return || key.escape {
        dispatch(BackToList)
      }
    | New(_) =>
      if key.escape {
        dispatch(BackToList)
      }
    | Loading => ()
    }
  )

  switch state.mode {
  | Loading =>
    <Ink.Text>
      <Ink.Spinner type_="dots" />
      {React.string(" loading QR slugs\xe2\x80\xa6")}
    </Ink.Text>

  | New(m) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text>
        {React.string("New slug (template: ")}
        <Ink.Text color="cyan"> {React.string(m.newTemplate)} </Ink.Text>
        {React.string("):")}
      </Ink.Text>
      <Ink.TextInput
        value={m.value}
        onChange={v => dispatch(SetNewValue(v))}
        onSubmit={v => {
          let slug = v->String.toLowerCase->String.trim
          if RegExp.test(slugRe, slug) {
            let url = qrPrintUrl([slug], m.newTemplate)
            openInBrowser(url)
            setStatus(`opened print page for ${slug} (first scan creates it)`)
            setError(None)
            dispatch(OpenPrint(url))
          } else {
            setError(Some("slug must match [a-z0-9-]{1,32}"))
          }
        }}
      />
      <Ink.Text color="gray">
        {React.string(
          "[ enter ] open print page \xc2\xb7 [ esc ] cancel \xc2\xb7 pattern: [a-z0-9-]{1,32}",
        )}
      </Ink.Text>
    </Ink.Box>

  | Opened(m) =>
    <Ink.Box flexDirection=#column>
      <Ink.Text color="green"> {React.string("opened in default browser:")} </Ink.Text>
      <Ink.Text color="gray"> {React.string(m.url)} </Ink.Text>
      <Ink.Box marginTop=1>
        <Ink.Text color="gray">
          {React.string(
            "[ enter / esc ] back \xc2\xb7 paste this URL into your phone to print from there",
          )}
        </Ink.Text>
      </Ink.Box>
    </Ink.Box>

  | List(m) =>
    let n = Array.length(m.slugs)
    if n === 0 {
      <Ink.Box flexDirection=#column>
        <Ink.Text color="gray">
          {React.string("no slugs yet \xe2\x80\x94 first scan creates one.")}
        </Ink.Text>
        <Ink.Text color="gray">
          {React.string(`[ n ] new \xc2\xb7 [ t ] template (${m.template}) \xc2\xb7 [ r ] refresh`)}
        </Ink.Text>
      </Ink.Box>
    } else {
      let visible = m.slugs->Array.slice(~start=0, ~end=30)
      <Ink.Box flexDirection=#column>
        <Ink.Text color="gray">
          {React.string(`${Int.toString(n)} slug${n === 1 ? "" : "s"} \xc2\xb7 template: `)}
          <Ink.Text color="cyan"> {React.string(m.template)} </Ink.Text>
        </Ink.Text>
        <Ink.Box marginTop=1 flexDirection=#column>
          <Ink.Text color="gray">
            {React.string(
              "  " ++
              padEnd("slug", 22) ++
              padStart("count", 6) ++
              "  " ++
              padEnd("first", 11) ++
              padEnd("last", 11) ++
              "top regions",
            )}
          </Ink.Text>
          {visible
          ->Array.mapWithIndex((s, i) =>
            <Ink.Text key={s.slug}>
              {React.string(i === m.cursor ? "\xe2\x80\xba " : "  ")}
              {React.string(padEnd(s.slug, 22))}
              <Ink.Text color="yellow">
                {React.string(padStart(Int.toString(s.count), 6))}
              </Ink.Text>
              {React.string("  ")}
              <Ink.Text color="gray">
                {React.string(padEnd(dateOnly(s.firstAt), 11))}
              </Ink.Text>
              <Ink.Text color="gray">
                {React.string(padEnd(dateOnly(s.lastAt), 11))}
              </Ink.Text>
              <Ink.Text color="green"> {React.string(topN(s.byRegion, 3))} </Ink.Text>
            </Ink.Text>
          )
          ->React.array}
        </Ink.Box>
        <Ink.Box marginTop=1>
          <Ink.Text color="gray">
            {React.string(
              "[ p ] print selected \xc2\xb7 [ shift-P ] print all \xc2\xb7 [ n ] new slug \xc2\xb7 [ t ] template \xc2\xb7 [ r ] refresh",
            )}
          </Ink.Text>
        </Ink.Box>
      </Ink.Box>
    }
  }
}
