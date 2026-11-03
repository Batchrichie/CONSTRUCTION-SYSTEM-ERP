export type DecimalInput = string | number | null | undefined

/** Parse a decimal value into 1/10,000 currency units without binary floating-point arithmetic. */
export function decimalUnits(value: DecimalInput): bigint | null {
  const match = /^([+-]?)(\d+)(?:\.(\d{0,4}))?$/.exec(String(value ?? '0').trim())
  if (!match) return null
  const units = BigInt(match[2]) * 10000n + BigInt((match[3] ?? '').padEnd(4, '0') || '0')
  return match[1] === '-' ? -units : units
}

export function exactUnits(value: DecimalInput): bigint {
  return decimalUnits(value) ?? 0n
}

export function sumUnits(values: DecimalInput[]): bigint {
  return values.reduce((sum, value) => sum + exactUnits(value), 0n)
}

export function unitsToString(units: bigint): string {
  const negative = units < 0n
  const absolute = negative ? -units : units
  const whole = absolute / 10000n
  const fraction = (absolute % 10000n).toString().padStart(4, '0').replace(/0+$/, '')
  return (negative ? '-' : '') + whole.toString() + (fraction ? '.' + fraction : '')
}

/** Convert only for display formatting; never use this number for accounting validation or RPC payloads. */
export function unitsToNumber(units: bigint): number {
  return Number(unitsToString(units))
}

export function isPositiveAmount(value: DecimalInput): boolean {
  const units = decimalUnits(value)
  return units !== null && units > 0n
}
