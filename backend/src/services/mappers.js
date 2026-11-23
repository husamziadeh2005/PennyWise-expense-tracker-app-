/**
 * The database uses snake_case (occurred_on); the API speaks camelCase
 * (occurredOn), which is what Dart/JSON code expects. These functions are
 * the only place where that translation happens.
 */

export const CATEGORY_COLUMNS = 'id, name, type, icon, color, created_at, updated_at';

export const TRANSACTION_COLUMNS =
  'id, type, amount, category_id, note, occurred_on, receipt_path, created_at, updated_at, ' +
  'category:categories(id, name, type, icon, color)';

export const BUDGET_COLUMNS =
  'id, category_id, amount, created_at, updated_at, category:categories(id, name, type, icon, color)';

export const PROFILE_COLUMNS =
  'id, full_name, email, phone, country, gender, avatar_url, currency, provider, created_at, updated_at';

const shortCategory = (c) =>
  c ? { id: c.id, name: c.name, type: c.type, icon: c.icon, color: c.color } : null;

export const toCategory = (row) => ({
  id: row.id,
  name: row.name,
  type: row.type,
  icon: row.icon,
  color: row.color,
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export const toTransaction = (row) => ({
  id: row.id,
  type: row.type,
  amount: Number(row.amount),
  categoryId: row.category_id,
  category: shortCategory(row.category),
  note: row.note,
  occurredOn: row.occurred_on,
  hasReceipt: Boolean(row.receipt_path),
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export const toBudget = (row) => ({
  id: row.id,
  categoryId: row.category_id,
  category: shortCategory(row.category),
  amount: Number(row.amount),
  createdAt: row.created_at,
  updatedAt: row.updated_at,
});

export const toProfile = (row) =>
  row && {
    id: row.id,
    fullName: row.full_name,
    email: row.email,
    phone: row.phone,
    country: row.country,
    gender: row.gender,
    avatarUrl: row.avatar_url,
    currency: row.currency ?? 'USD',
    provider: row.provider,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };

/** Copies only the keys that are present (PATCH semantics). */
export function pickDefined(source, mapping) {
  const out = {};
  for (const [apiKey, dbKey] of Object.entries(mapping)) {
    if (source[apiKey] !== undefined) out[dbKey] = source[apiKey];
  }
  return out;
}
