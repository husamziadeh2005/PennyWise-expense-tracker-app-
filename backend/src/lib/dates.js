/**
 * Date helpers that work on plain "YYYY-MM-DD" strings.
 *
 * Transactions store a calendar date (no time, no time zone), so we never
 * convert them to JavaScript Date objects in local time. That avoids the
 * classic bug where an expense made late at night shows up on the next day.
 * All calculations below use UTC on purpose.
 */

const pad = (n) => String(n).padStart(2, '0');

export const toIsoDate = (d) =>
  `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;

/** True for a real calendar date such as 2026-02-28 (rejects 2026-02-30). */
export function isValidIsoDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && toIsoDate(d) === value;
}

export const isValidMonth = (value) =>
  typeof value === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(value);

export function daysInMonth(month) {
  const [y, m] = month.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}

/** "2026-11" -> { start: "2026-11-01", end: "2026-11-30" } */
export function monthRange(month) {
  return { start: `${month}-01`, end: `${month}-${pad(daysInMonth(month))}` };
}

export function shiftMonth(month, delta) {
  const [y, m] = month.split('-').map(Number);
  const d = new Date(Date.UTC(y, m - 1 + delta, 1));
  return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}`;
}

/** Every date of the month: ["2026-11-01", ..., "2026-11-30"] */
export function datesOfMonth(month) {
  return Array.from({ length: daysInMonth(month) }, (_, i) => `${month}-${pad(i + 1)}`);
}

export function addDays(isoDate, days) {
  const d = new Date(`${isoDate}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return toIsoDate(d);
}
