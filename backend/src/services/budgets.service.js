import { ApiError, unwrap } from '../lib/errors.js';
import { BUDGET_COLUMNS, toBudget } from './mappers.js';

/**
 * A budget is a monthly spending limit. categoryId = null means the
 * overall limit for all expenses; otherwise it is for one expense
 * category. How much of it is used is calculated in the stats service.
 */

export async function listBudgets(supabase) {
  const rows = await unwrap(
    supabase.from('budgets').select(BUDGET_COLUMNS).order('category_id', { ascending: true, nullsFirst: true }),
  );
  return rows.map(toBudget);
}

export async function createBudget(supabase, { categoryId, amount }) {
  const row = await unwrap(
    supabase.from('budgets').insert({ category_id: categoryId, amount }).select(BUDGET_COLUMNS).single(),
    {
      conflictMessage: categoryId
        ? 'This category already has a budget. Edit it instead.'
        : 'You already have an overall budget. Edit it instead.',
    },
  );
  return toBudget(row);
}

export async function updateBudget(supabase, id, { amount }) {
  const row = await unwrap(
    supabase.from('budgets').update({ amount }).eq('id', id).select(BUDGET_COLUMNS).maybeSingle(),
  );
  if (!row) throw ApiError.notFound('Budget');
  return toBudget(row);
}

export async function deleteBudget(supabase, id) {
  const row = await unwrap(supabase.from('budgets').delete().eq('id', id).select('id').maybeSingle());
  if (!row) throw ApiError.notFound('Budget');
  return { deleted: true, id: row.id };
}
