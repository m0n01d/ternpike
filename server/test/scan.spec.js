// node:test unit tests for the server-side needsReview utility in server/scan.js
import { describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { needsReview } from '../scan.js'

describe('needsReview', () => {
  it('returns false when all structural fields are present', () => {
    assert.equal(
      needsReview({ amount: 45.00, merchant: 'Summit Fuel Stop', date: '2024-07-04', category: 'fuel' }),
      false,
    )
  })

  it('returns true when amount is missing', () => {
    assert.equal(
      needsReview({ merchant: 'Trattoria Roma', date: '2024-07-04', category: 'food' }),
      true,
    )
  })

  it('returns true when merchant is missing', () => {
    assert.equal(
      needsReview({ amount: 45.00, date: '2024-07-04', category: 'fuel' }),
      true,
    )
  })

  it('returns true when date is missing', () => {
    assert.equal(
      needsReview({ amount: 45.00, merchant: 'Summit Fuel Stop', category: 'fuel' }),
      true,
    )
  })

  it('returns true when amount is undefined (not just null)', () => {
    assert.equal(
      needsReview({ amount: undefined, merchant: 'Summit Fuel Stop', date: '2024-07-04' }),
      true,
    )
  })

  it('does not flag when only non-structural fields are absent', () => {
    assert.equal(
      needsReview({ amount: 12.50, merchant: 'Corner Cafe', date: '2024-08-01' }),
      false,
    )
  })
})
