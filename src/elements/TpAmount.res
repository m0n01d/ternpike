// TpAmount — the logic core of the <tp-amount> accessible currency element.
//
// The imperative `class extends HTMLElement` skeleton ReScript 12 cannot
// express lives in the sibling `tp-amount.js` shell, which holds NO logic — it
// only forwards the three lifecycle callbacks into the functions exposed here
// (`observedAttributes`, `connected`, `attributeChanged`). Everything else —
// attribute parsing, locale resolution, Intl formatting, the a11y contract — is
// here, typed, with no `%raw` and no escape hatches.
//
// A11y contract (the whole point of the element, preserved byte-for-byte from
// the JS original):
//   - host carries role="text" so a screen reader reads the amount as one
//     phrase, and aria-label carries the verbose spoken form ("12 dollars and
//     34 cents", "negative 5 dollars", "0 dollars").
//   - the visible "$" symbol lives in a Shadow-DOM <span aria-hidden="true"> so
//     it isn't double-announced after the aria-label fires.
//   - negative amounts start the spoken form with the word "negative", never a
//     hyphen a screen reader might swallow.

let defaultCurrency = "USD"

type formatted = {
  spoken: string,
  visible: string,
}

// Map a parsed integer to the standard library's strict `zeroTo20` digit
// variant. Out-of-range inputs yield `None`, so Intl falls back to the
// currency's own default precision (2 for USD) — matching the JS original's
// `Number.isFinite` guard.
let zeroTo20OfInt = (n: int): option<Intl.Common.zeroTo20> =>
  switch n {
  | 0 => Some(#0)
  | 1 => Some(#1)
  | 2 => Some(#2)
  | 3 => Some(#3)
  | 4 => Some(#4)
  | 5 => Some(#5)
  | 6 => Some(#6)
  | 7 => Some(#7)
  | 8 => Some(#8)
  | 9 => Some(#9)
  | 10 => Some(#10)
  | 11 => Some(#11)
  | 12 => Some(#12)
  | 13 => Some(#13)
  | 14 => Some(#14)
  | 15 => Some(#15)
  | 16 => Some(#16)
  | 17 => Some(#17)
  | 18 => Some(#18)
  | 19 => Some(#19)
  | 20 => Some(#20)
  | _ => None
  }

// Build an Intl formatter for `locale`, falling back to "en-US" if the tag is
// structurally invalid (Intl.NumberFormat throws a RangeError on malformed
// tags). This is the only place an exception can arise, and it is contained.
let makeFormatter = (locale: string, options: Intl.NumberFormat.options): Intl.NumberFormat.t =>
  try {
    Intl.NumberFormat.make(~locales=[locale], ~options)
  } catch {
  | _ => Intl.NumberFormat.make(~locales=["en-US"], ~options)
  }

// Leading minus glyph (ASCII hyphen or U+2212) plus any whitespace.
let leadingMinus = RegExp.fromString("^[-−]\\s*")

// Pure: given a resolved locale, currency, an optional numeric value, and an
// optional max-fraction-digits override, produce the visible and spoken forms.
// `value == None` (a missing/non-finite `value` attribute) renders an em dash.
let format = (
  ~locale: string,
  ~currency: string,
  ~value: option<float>,
  ~maxFrac: option<int>,
): formatted =>
  switch value {
  | None => {visible: "—", spoken: ""}
  | Some(v) =>
    let maximumFractionDigits = maxFrac->Option.flatMap(zeroTo20OfInt)
    // Intl requires min <= max; mirror the JS `Math.min(mfd, 2)`.
    let minimumFractionDigits = maxFrac->Option.flatMap(m => zeroTo20OfInt(Math.Int.min(m, 2)))

    let visibleOpts: Intl.NumberFormat.options = {
      style: #currency,
      currency,
      maximumFractionDigits: ?maximumFractionDigits,
      minimumFractionDigits: ?minimumFractionDigits,
    }
    let visible = makeFormatter(locale, visibleOpts)->Intl.NumberFormat.format(v)

    // Spoken form: same options but the currency rendered as its name, so Intl
    // handles plural agreement ("dollar"/"dollars", "cent"/"cents").
    let spokenOpts = {...visibleOpts, currencyDisplay: #name}
    let spokenRaw = makeFormatter(locale, spokenOpts)->Intl.NumberFormat.format(v)
    let spoken = spokenRaw->String.replaceRegExp(leadingMinus, "negative ")

    {visible, spoken}
  }

// ── Attribute reading ──────────────────────────────────────────────────────

let parseValue = (raw: option<string>): option<float> =>
  switch raw {
  | None => None
  | Some(s) =>
    let n = Float.parseFloat(s)
    Float.isFinite(n) ? Some(n) : None
  }

let readCurrency = (host: Dom.element): string =>
  switch host->WebApi.getAttribute("currency")->Null.toOption {
  | Some("") | None => defaultCurrency
  | Some(c) => c
  }

let readMaxFrac = (host: Dom.element): option<int> =>
  host
  ->WebApi.getAttribute("maximumfractiondigits")
  ->Null.toOption
  ->Option.flatMap(s => Int.fromString(s))

// Resolve the locale: explicit `locale` attribute wins; otherwise walk up the
// ancestor chain for the nearest `lang`; finally fall back to the document's
// `lang` property, then "en-US".
let rec nearestLang = (cursor: Null.t<Dom.element>): option<string> =>
  switch cursor->Null.toOption {
  | None => None
  | Some(el) =>
    switch el->WebApi.getAttribute("lang")->Null.toOption {
    | Some(lang) if lang !== "" => Some(lang)
    | _ => nearestLang(el->WebApi.parentElement)
    }
  }

let resolveLocale = (host: Dom.element): string =>
  switch host->WebApi.getAttribute("locale")->Null.toOption {
  | Some(explicit) if explicit !== "" => explicit
  | _ =>
    switch nearestLang(Null.make(host)) {
    | Some(lang) => lang
    | None =>
      let docLang = WebApi.document->WebApi.documentElement->WebApi.lang
      docLang === "" ? "en-US" : docLang
    }
  }

// ── Rendering ───────────────────────────────────────────────────────────────

let render = (host: Dom.element, visible: Dom.element): unit => {
  let {visible: visibleText, spoken} = format(
    ~locale=resolveLocale(host),
    ~currency=readCurrency(host),
    ~value=parseValue(host->WebApi.getAttribute("value")->Null.toOption),
    ~maxFrac=readMaxFrac(host),
  )

  host->WebApi.setAttribute("role", "text")
  if spoken === "" {
    host->WebApi.removeAttribute("aria-label")
  } else {
    host->WebApi.setAttribute("aria-label", spoken)
  }
  visible->WebApi.setTextContent(visibleText)
}

// ── Lifecycle (called by the JS shell) ──────────────────────────────────────

let observedAttributes = ["value", "currency", "locale", "maximumfractiondigits"]

// The Shadow-DOM <span> that holds the visible text is stashed on the host as a
// private property so it survives across attribute changes without re-creating
// the shadow root. Per the custom-element spec a constructor must not touch the
// host, so the shadow is built lazily on first connect.
// Unset, the property reads back `undefined` (not `null`), so it must be modelled
// as `Nullable` — `Null` would only catch `null` and leak `undefined` through.
@get external visibleSpan: Dom.element => Nullable.t<Dom.element> = "_tpVisible"
@set external setVisibleSpan: (Dom.element, Dom.element) => unit = "_tpVisible"

let ensureVisibleSpan = (host: Dom.element): Dom.element =>
  switch host->visibleSpan->Nullable.toOption {
  | Some(span) => span
  | None =>
    let shadow = host->WebApi.attachShadow({mode: "open"})
    let span = WebApi.document->WebApi.createElement("span")
    span->WebApi.setAttribute("aria-hidden", "true")
    shadow->WebApi.appendChild(span)
    host->setVisibleSpan(span)
    span
  }

let connected = (host: Dom.element): unit => render(host, ensureVisibleSpan(host))

// Skip if the shadow isn't built yet — connectedCallback will catch up.
let attributeChanged = (host: Dom.element): unit =>
  switch host->visibleSpan->Nullable.toOption {
  | None => ()
  | Some(span) => render(host, span)
  }
