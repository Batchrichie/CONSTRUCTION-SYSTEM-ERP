import { describe, expect, it } from 'vitest'
import { calculateBudgetVariance } from './budgetVsActual'

describe('budget versus actual calculations', () => {
  it('calculates remaining budget without floating-point drift', () => {
    expect(calculateBudgetVariance({ budget: '100.10', actual: '0.20' }).variance).toBe('99.9')
  })

  it('returns a negative variance when actual costs exceed budget', () => {
    expect(calculateBudgetVariance({ budget: '100', actual: '125.25' }).variance).toBe('-25.25')
  })

  it('supports negative actual costs from posted reversals', () => {
    expect(calculateBudgetVariance({ budget: '100', actual: '-10' }).variance).toBe('110')
  })

  it('preserves four-decimal accounting precision', () => {
    expect(calculateBudgetVariance({ budget: '1000.0001', actual: '0.0001' }).variance).toBe('1000')
  })
})
