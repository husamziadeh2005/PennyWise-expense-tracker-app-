import { z } from 'zod';
import {
  amount, isoDate, month, nonEmpty, optionalText, transactionType, uuid,
} from './common.js';

export { idParams } from './common.js';

// ---------------------------------------------------------------- categories
const categoryName = z
  .string({ message: 'Name is required' })
  .trim()
  .min(1, 'Name is required')
  .max(40, 'Name must be at most 40 characters');
const icon = z.string().regex(/^[a-z_]{1,40}$/, 'Invalid icon name');
const color = z.string().regex(/^#[0-9A-Fa-f]{6}$/, 'Color must look like #A1B2C3');

export const categorySchemas = {
  list: z.object({ type: transactionType.optional() }),
  create: z.object({
    name: categoryName,
    type: transactionType,
    icon: icon.default('category'),
    color: color.default('#607D8B'),
  }),
  // type is not editable: existing transactions depend on it
  update: nonEmpty(z.object({
    name: categoryName.optional(),
    icon: icon.optional(),
    color: color.optional(),
  })),
  remove: z.object({ reassignTo: uuid.optional() }),
};

// -------------------------------------------------------------- transactions
const categoryId = uuid.nullish().transform((v) => v ?? null);

export const transactionSchemas = {
  list: z
    .object({
      from: isoDate.optional(),
      to: isoDate.optional(),
      type: transactionType.optional(),
      // a category id, or "none" for uncategorised transactions
      categoryId: z.union([uuid, z.literal('none')]).optional(),
      q: z.string().trim().max(100).optional(),
      limit: z.coerce.number().int().min(1).max(100).default(50),
      offset: z.coerce.number().int().min(0).max(100000).default(0),
    })
    .refine((v) => !v.from || !v.to || v.from <= v.to, {
      message: '"from" must be before "to"',
      path: ['from'],
    }),
  create: z.object({
    type: transactionType,
    amount,
    categoryId,
    note: optionalText(500),
    occurredOn: isoDate.optional(),
  }),
  update: nonEmpty(z.object({
    type: transactionType.optional(),
    amount: amount.optional(),
    categoryId: uuid.nullable().optional(),
    note: optionalText(500).optional(),
    occurredOn: isoDate.optional(),
  })),
};

// ------------------------------------------------------------------- budgets
export const budgetSchemas = {
  create: z.object({ categoryId, amount }),
  update: z.object({ amount }),
};

// ------------------------------------------------------------------- profile
export const profileSchemas = {
  update: nonEmpty(z.object({
    fullName: z.string().trim().min(2, 'Name is too short').max(80, 'Name is too long').optional(),
    country: optionalText(60).optional(),
    gender: z.enum(['Male', 'Female']).nullable().optional(),
    currency: z
      .string()
      .trim()
      .regex(/^[A-Za-z]{3}$/, 'Currency must be a 3-letter code like USD')
      .transform((v) => v.toUpperCase())
      .optional(),
  })),
};

// --------------------------------------------------------------------- stats
export const statsSchemas = {
  summary: z.object({
    month: month.optional(),
    // the phone's local date, so "today" matches the user's time zone
    today: isoDate.optional(),
  }),
};
