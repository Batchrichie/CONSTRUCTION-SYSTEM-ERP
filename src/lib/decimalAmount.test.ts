import { describe, expect, it } from 'vitest'
import { decimalUnits, exactUnits, isPositiveAmount, sumUnits, unitsToNumber, unitsToString } from './decimalAmount'

describe('decimalAmount', () => {
  it('adds decimal amounts without binary floating-point drift', () => {
    expect(unitsToString(sumUnits(['0.1', '0.2']))).toBe('0.3')
  })

  it('preserves the database precision of four decimal places', () => {
    expect(unitsToString(sumUnits(['12500.1250', '0.0001']))).toBe('12500.1251')
  })

  it('accepts leading-decimal input without losing precision', () => {
    expect(decimalUnits('.5')).toBe(5000n)
    expect(decimalUnits('.0001')).toBe(1n)
  })

  it('detects a one ten-thousandth over-allocation', () => {
    expect(exactUnits('10.0001') > exactUnits('10.0000')).toBe(true)
  })

  it('rejects values with more than four decimal places', () => {
    expect(decimalUnits('0.00001')).toBeNull()
    expect(isPositiveAmount('0.00001')).toBe(false)
  })

  it('supports exact negative differences for remaining-balance display', () => {
    expect(unitsToString(exactUnits('9.5') - exactUnits('10'))).toBe('-0.5')
  })

  it('converts to a number only for display formatting', () => {
    expect(unitsToNumber(exactUnits('123.4500'))).toBe(123.45)
  })

  it('rejects zero and negative expense inputs', () => {
    expect(isPositiveAmount('0')).toBe(false)
    expect(isPositiveAmount('-0.01')).toBe(false)
    expect(isPositiveAmount('0.0001')).toBe(true)
  })

  it('sums multiple BOQ line totals exactly at four-decimal precision', () => {
    expect(unitsToString(sumUnits(['12500.1250', '0.0001', '0.2000', '0.1000']))).toBe('12500.4251')
  })

  it('calculates estimate totals as subtotal less discount plus tax without floating-point drift', () => {
    const subtotal = sumUnits(['12500.1250', '0.0001', '0.2000', '0.1000'])
    const discount = exactUnits('250.0001')
    const tax = exactUnits('37.5001')

    expect(unitsToString(subtotal - discount + tax)).toBe('12287.9251')
  })

  it('allows a discount equal to the BOQ subtotal but detects a one-unit excess', () => {
    const subtotal = sumUnits(['12.3456', '0.0001'])

    expect(exactUnits('12.3457') > subtotal).toBe(false)
    expect(exactUnits('12.3458') > subtotal).toBe(true)
  })

  it('rejects blank and malformed commercial amount inputs', () => {
    expect(decimalUnits('')).toBeNull()
    expect(decimalUnits('1,000.00')).toBeNull()
    expect(decimalUnits('1e3')).toBeNull()
    expect(decimalUnits('1.23456')).toBeNull()
  })
})
