// [Invite] #336 — guest scan rate-limit unit tests (no CouchDB, no Anthropic).
//
// Pure coverage for the three-gate `/scan-guest` rate decision. The live
// endpoint (KV reads/writes + Anthropic proxy) is exercised only against the
// real bindings in CI; here we pin the boundary logic that decides 429.

import { describe, test } from 'node:test'
import assert from 'node:assert/strict'

import {
  SCAN_GUEST_GLOBAL_PER_DAY,
  SCAN_GUEST_PER_IP_PER_DAY,
  SCAN_GUEST_PER_TOKEN_PER_DAY,
  scanGuestRateDecision,
} from '../inviteFunnel.js'

describe('[Invite] scanGuestRateDecision — three-gate rate limit (#336)', () => {
  test('allows a first scan and reports remaining', () => {
    const d = scanGuestRateDecision({ tokenCount: 0, ipCount: 0, globalCount: 0 })
    assert.equal(d.ok, true)
    assert.equal(d.remaining, SCAN_GUEST_PER_TOKEN_PER_DAY - 1)
  })

  test('denies when the per-token cap is reached', () => {
    const d = scanGuestRateDecision({
      tokenCount: SCAN_GUEST_PER_TOKEN_PER_DAY,
      ipCount: 0,
      globalCount: 0,
    })
    assert.equal(d.ok, false)
  })

  test('denies when the per-IP cap is reached (token still under)', () => {
    const d = scanGuestRateDecision({
      tokenCount: 0,
      ipCount: SCAN_GUEST_PER_IP_PER_DAY,
      globalCount: 0,
    })
    assert.equal(d.ok, false)
  })

  test('denies when the global circuit-breaker is reached', () => {
    const d = scanGuestRateDecision({
      tokenCount: 0,
      ipCount: 0,
      globalCount: SCAN_GUEST_GLOBAL_PER_DAY,
    })
    assert.equal(d.ok, false)
  })

  test('last allowed per-token scan reports remaining 0', () => {
    const d = scanGuestRateDecision({
      tokenCount: SCAN_GUEST_PER_TOKEN_PER_DAY - 1,
      ipCount: 0,
      globalCount: 0,
    })
    assert.equal(d.ok, true)
    assert.equal(d.remaining, 0)
  })

  test('non-numeric counts coerce to 0 (allow)', () => {
    const d = scanGuestRateDecision({
      tokenCount: undefined,
      ipCount: null,
      globalCount: NaN,
    })
    assert.equal(d.ok, true)
  })
})
