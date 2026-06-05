// <tp-amount> — thin custom-element shell. ALL logic lives in TpAmount.res;
// this file exists only because ReScript 12 cannot express `class extends
// HTMLElement`. Every lifecycle callback forwards straight into the compiled
// ReScript core — no logic, no branching, no formatting here.
//
// Usage and the full a11y contract are documented in TpAmount.res.
import * as Core from './TpAmount.res.mjs'

class TpAmount extends HTMLElement {
  static get observedAttributes() {
    return Core.observedAttributes
  }

  connectedCallback() {
    Core.connected(this)
  }

  attributeChangedCallback() {
    Core.attributeChanged(this)
  }
}

customElements.define('tp-amount', TpAmount)
