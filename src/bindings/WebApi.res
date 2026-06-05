// WebApi — hand-written bindings to the small slice of the DOM the ReScript
// custom-element cores actually touch. Real `external`s over the abstract
// types in the standard library's `Dom` module; no `%raw`, no escape hatches.
//
// Methods bind as functions taking the instance as the first argument
// (`el->WebApi.getAttribute("value")`), the idiomatic ReScript way of modelling
// a JS object's methods.

type element = Dom.element
type document = Dom.document
type shadowRoot = Dom.shadowRoot

// ── Attributes ────────────────────────────────────────────────────────────
// getAttribute returns `null` when the attribute is absent, hence `Null.t`.
@send external getAttribute: (element, string) => Null.t<string> = "getAttribute"
@send external setAttribute: (element, string, string) => unit = "setAttribute"
@send external removeAttribute: (element, string) => unit = "removeAttribute"

// ── Traversal ─────────────────────────────────────────────────────────────
@get external parentElement: element => Null.t<element> = "parentElement"

// `lang` reflects as a property (empty string when unset), unlike the
// attribute accessor above — used only for the document-level locale fallback.
@get external lang: element => string = "lang"

// ── Document ──────────────────────────────────────────────────────────────
@val external document: document = "document"
@get external documentElement: document => element = "documentElement"
@send external createElement: (document, string) => element = "createElement"

// ── Content ───────────────────────────────────────────────────────────────
@set external setTextContent: (element, string) => unit = "textContent"

// ── Shadow DOM ────────────────────────────────────────────────────────────
type shadowInit = {mode: string}
@send external attachShadow: (element, shadowInit) => shadowRoot = "attachShadow"
@send external appendChild: (shadowRoot, element) => unit = "appendChild"
