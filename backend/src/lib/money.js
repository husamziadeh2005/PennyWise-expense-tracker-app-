/**
 * Money helpers.
 *
 * Computers store decimals in binary, so 0.1 + 0.2 = 0.30000000000000004.
 * To avoid that, all sums in this API are done in CENTS (whole numbers)
 * and converted back to a decimal only at the end.
 */

export const toCents = (amount) => Math.round(Number(amount) * 100);

export const fromCents = (cents) => Math.round(cents) / 100;

/** Percentage of part/whole rounded to 1 decimal, or null if whole is 0. */
export function percent(part, whole) {
  if (!whole) return null;
  return Math.round((part / whole) * 1000) / 10;
}
