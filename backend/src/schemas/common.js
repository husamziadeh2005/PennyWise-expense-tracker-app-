import { z } from 'zod';
import { isValidIsoDate, isValidMonth } from '../lib/dates.js';

export const uuid = z.uuid({ message: 'Must be a valid id' });

export const idParams = z.object({ id: uuid });

export const transactionType = z.enum(['income', 'expense'], {
  message: 'Type must be "income" or "expense"',
});

/** Calendar date "YYYY-MM-DD" that really exists, between 2000 and 2100. */
export const isoDate = z
  .string({ message: 'Date must be in YYYY-MM-DD format' })
  .refine(isValidIsoDate, 'Date must be a real date in YYYY-MM-DD format')
  .refine((d) => d >= '2000-01-01' && d <= '2100-12-31', 'Date must be between 2000 and 2100');

export const month = z
  .string()
  .refine(isValidMonth, 'Month must be in YYYY-MM format');

/**
 * Money amount. Accepts 12, 12.5, "12.50"; rejects 0, negatives,
 * more than 2 decimals, and anything above 9,999,999,999.99.
 */
export const amount = z
  .union([z.number(), z.string().trim()], { message: 'Amount is required' })
  .refine(
    (v) => /^\d{1,10}(\.\d{1,2})?$/.test(String(v)),
    'Amount must be a positive number with at most 2 decimals',
  )
  .transform(Number)
  .refine((n) => n > 0, 'Amount must be greater than 0');

/** Optional free text: trimmed, "" becomes null. */
export const optionalText = (max) =>
  z
    .string()
    .trim()
    .max(max, `Must be at most ${max} characters`)
    .nullish()
    .transform((v) => (v ? v : null));

/** Rejects an empty PATCH body like {}. */
export const nonEmpty = (schema) =>
  schema.refine((obj) => Object.values(obj).some((v) => v !== undefined), {
    message: 'Send at least one field to update',
  });
