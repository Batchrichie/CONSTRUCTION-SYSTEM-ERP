import { exactUnits, unitsToString } from './decimalAmount'

export type BudgetActualInput = {
  budget: string | number
  actual: string | number
}

export function calculateBudgetVariance(input: BudgetActualInput) {
  const budgetUnits = exactUnits(input.budget)
  const actualUnits = exactUnits(input.actual)
  return {
    budgetUnits,
    actualUnits,
    varianceUnits: budgetUnits - actualUnits,
    budget: unitsToString(budgetUnits),
    actual: unitsToString(actualUnits),
    variance: unitsToString(budgetUnits - actualUnits),
  }
}
