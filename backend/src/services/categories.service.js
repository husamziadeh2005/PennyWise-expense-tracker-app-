import { ApiError, unwrap } from '../lib/errors.js';
import { CATEGORY_COLUMNS, pickDefined, toCategory } from './mappers.js';

const DUPLICATE = 'You already have a category with this name.';

export async function listCategories(supabase, { type } = {}) {
  let query = supabase.from('categories').select(CATEGORY_COLUMNS).order('type').order('name');
  if (type) query = query.eq('type', type);
  const rows = await unwrap(query);
  return rows.map(toCategory);
}

export async function createCategory(supabase, input) {
  // user_id is NOT sent: the database fills it from the JWT (auth.uid()).
  const row = await unwrap(
    supabase
      .from('categories')
      .insert({ name: input.name, type: input.type, icon: input.icon, color: input.color })
      .select(CATEGORY_COLUMNS)
      .single(),
    { conflictMessage: DUPLICATE },
  );
  return toCategory(row);
}

export async function updateCategory(supabase, id, input) {
  const changes = pickDefined(input, { name: 'name', icon: 'icon', color: 'color' });
  const row = await unwrap(
    supabase.from('categories').update(changes).eq('id', id).select(CATEGORY_COLUMNS).maybeSingle(),
    { conflictMessage: DUPLICATE },
  );
  if (!row) throw ApiError.notFound('Category');
  return toCategory(row);
}

/**
 * Deletes a category. Runs as ONE database transaction (the
 * delete_category SQL function), so it either fully succeeds or nothing
 * changes:
 *   - with reassignTo: its transactions move to that category first
 *   - without: its transactions stay, just without a category
 * Budgets for the category are removed with it.
 */
export async function deleteCategory(supabase, id, reassignTo) {
  const affected = await unwrap(
    supabase.rpc('delete_category', { p_category_id: id, p_reassign_to: reassignTo ?? null }),
  );
  return { deleted: true, affectedTransactions: affected ?? 0 };
}
