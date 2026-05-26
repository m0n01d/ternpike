// <tp-amount> — accessible currency display via Intl.NumberFormat.
//
// Usage:
//   <tp-amount value="12.34" currency="USD" locale="en-US"></tp-amount>
//   <tp-amount value="1234.56" currency="USD"></tp-amount>
//   <tp-amount value="1234" currency="USD" maximumfractiondigits="0"></tp-amount>
//
// Attributes (all observed):
//   value                    decimal amount (e.g. "12.34", "-5.00"). Required.
//   currency                 ISO 4217 code. Defaults to "USD".
//   locale                   BCP 47 tag. Defaults to closest ancestor `lang`,
//                            falling back to `document.documentElement.lang || "en-US"`.
//   maximumfractiondigits    integer, overrides currency default (2 for USD).
//
// Behaviour:
//   - Renders formatted text via Intl.NumberFormat(locale, { style: "currency", currency }).
//   - Uses Shadow DOM (constructed lazily on first connection) so Elm's
//     virtual-DOM reconciler does not overwrite the visible content. The host
//     element is Light-DOM-styleable via the usual `class` attribute — Tailwind
//     utilities applied to the host (font, color, size, layout) cascade into
//     the Shadow DOM children via standard CSS inheritance.
//   - First paint runs in connectedCallback. Per the custom-element spec, a
//     constructor MUST NOT set attributes or append children on the host —
//     attempting to do so throws "The result must not have attributes". We
//     defer all DOM mutation to connectedCallback / attributeChangedCallback.
//   - Re-renders on any observed attribute change.
//
// A11y contract — non-negotiable (the whole point of #38):
//
//   1. Host carries role="text" so the SR reads the amount as one phrase
//      ("twelve dollars and thirty-four cents") instead of "dollar sign one
//      two point three four".
//   2. Host carries aria-label with the verbose spoken form computed via
//      Intl.NumberFormat(locale, { style: "currency", currency,
//      currencyDisplay: "name" }). Plural agreement ("dollar"/"dollars",
//      "cent"/"cents") is handled by Intl. Examples: "12 dollars and 34 cents",
//      "1,200 dollars", "negative 5 dollars", "0 dollars".
//   3. The visible currency symbol ($) lives inside <span aria-hidden="true">
//      so it isn't double-announced after the aria-label fires.
//   4. Negative amounts use the real minus glyph ("−" U+2212, emitted by
//      Intl.NumberFormat) visually and start the aria-label with the word
//      "negative" — never "minus", never a hyphen the SR may swallow.
//   5. Zero amounts read as "0 dollars", not "zero".
//   6. No tabindex — read-only content, not interactive, must not appear in
//      the tab order.
//   7. `lang` inherits via the standard DOM mechanism (the closest ancestor's
//      lang attribute) so future locale changes flow without per-call-site
//      plumbing.

const DEFAULT_CURRENCY = 'USD'

function resolveLocale(el) {
  const explicit = el.getAttribute('locale')
  if (explicit) return explicit
  // Walk up looking for a lang attribute. document.documentElement.lang is
  // the final fallback; if that's empty we use en-US so commas / dollar
  // semantics are predictable.
  let cursor = el
  while (cursor) {
    const lang = cursor.getAttribute && cursor.getAttribute('lang')
    if (lang) return lang
    cursor = cursor.parentElement
  }
  return document.documentElement.lang || 'en-US'
}

function parseValue(raw) {
  if (raw == null) return NaN
  const n = parseFloat(raw)
  return Number.isFinite(n) ? n : NaN
}

class TpAmount extends HTMLElement {
  // Note: constructor intentionally empty. Per the custom-element spec
  // (and enforced by Chromium / WebKit), a constructor MUST NOT set
  // attributes or append children on the host element — doing so throws
  // "The result must not have attributes" and prevents upgrade. All DOM
  // mutation is deferred to connectedCallback / attributeChangedCallback.

  connectedCallback() {
    if (!this._shadow) {
      this._shadow = this.attachShadow({ mode: 'open' })
      this._visible = document.createElement('span')
      this._visible.setAttribute('aria-hidden', 'true')
      this._shadow.appendChild(this._visible)
    }
    this._render()
  }

  attributeChangedCallback() {
    // Skip if disconnected — connectedCallback will catch up on reconnect.
    if (!this._shadow) return
    this._render()
  }

  static get observedAttributes() {
    return ['value', 'currency', 'locale', 'maximumfractiondigits']
  }

  _render() {
    const value = parseValue(this.getAttribute('value'))
    const currency = this.getAttribute('currency') || DEFAULT_CURRENCY
    const locale = resolveLocale(this)
    const maxFracRaw = this.getAttribute('maximumfractiondigits')

    const fmtOpts = { style: 'currency', currency }
    if (maxFracRaw != null) {
      const mfd = parseInt(maxFracRaw, 10)
      if (Number.isFinite(mfd)) {
        fmtOpts.maximumFractionDigits = mfd
        fmtOpts.minimumFractionDigits = Math.min(mfd, 2)
      }
    }

    // Visible text.
    let visible
    let spoken
    if (Number.isNaN(value)) {
      visible = '—'
      spoken = ''
    } else {
      try {
        visible = new Intl.NumberFormat(locale, fmtOpts).format(value)
      } catch (_) {
        visible = new Intl.NumberFormat('en-US', fmtOpts).format(value)
      }
      // Spoken form: currency name + plural words + "negative" prefix.
      const spokenOpts = { ...fmtOpts, currencyDisplay: 'name' }
      try {
        spoken = new Intl.NumberFormat(locale, spokenOpts).format(value)
      } catch (_) {
        spoken = new Intl.NumberFormat('en-US', spokenOpts).format(value)
      }
      // Intl emits "-12 US dollars" or "−12 US dollars". Replace the
      // leading minus glyph (either form) with the spoken word.
      spoken = spoken.replace(/^[-−]\s*/, 'negative ')
    }

    // a11y attrs on the host. Idempotent.
    this.setAttribute('role', 'text')
    if (spoken) {
      this.setAttribute('aria-label', spoken)
    } else {
      this.removeAttribute('aria-label')
    }

    this._visible.textContent = visible
  }
}

customElements.define('tp-amount', TpAmount)
