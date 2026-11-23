import { ApiError, unwrap } from '../lib/errors.js';
import { BUCKETS } from '../lib/supabase.js';
import { storagePath } from '../lib/files.js';
import { toIsoDate } from '../lib/dates.js';
import { TRANSACTION_COLUMNS, pickDefined, toTransaction } from './mappers.js';
import { removeFilesQuietly, signedUrl, uploadFile } from './storage.service.js';

const FIELD_MAP = {
  type: 'type',
  amount: 'amount',
  categoryId: 'category_id',
  note: 'note',
  occurredOn: 'occurred_on',
};

/** Escapes % and _ so a search for "50%" is literal, not a wildcard. */
const escapeLike = (text) => text.replace(/[\\%_]/g, (c) => `\\${c}`);

/**
 * Lists transactions, newest first, with filters and paging.
 * Returns { items, total, limit, offset, hasMore }.
 */
export async function listTransactions(supabase, filters) {
  const { from, to, type, categoryId, q, limit, offset } = filters;

  let query = supabase
    .from('transactions')
    .select(TRANSACTION_COLUMNS, { count: 'exact' })
    .order('occurred_on', { ascending: false })
    .order('created_at', { ascending: false })
    .order('id', { ascending: false }) // stable order when dates are equal
    .range(offset, offset + limit - 1);

  if (from) query = query.gte('occurred_on', from);
  if (to) query = query.lte('occurred_on', to);
  if (type) query = query.eq('type', type);
  if (categoryId === 'none') query = query.is('category_id', null);
  else if (categoryId) query = query.eq('category_id', categoryId);
  if (q) query = query.ilike('note', `%${escapeLike(q)}%`);

  const { data, error, count } = await query;
  // Asking for a page past the end is not an error, just an empty page.
  if (error?.code === 'PGRST103') return { items: [], total: count ?? 0, limit, offset, hasMore: false };
  if (error) throw error;

  const total = count ?? data.length;
  return { items: data.map(toTransaction), total, limit, offset, hasMore: offset + data.length < total };
}

async function getRow(supabase, id, columns = TRANSACTION_COLUMNS) {
  const row = await unwrap(supabase.from('transactions').select(columns).eq('id', id).maybeSingle());
  if (!row) throw ApiError.notFound('Transaction');
  return row;
}

export async function getTransaction(supabase, id) {
  return toTransaction(await getRow(supabase, id));
}

export async function createTransaction(supabase, input) {
  const values = pickDefined(input, FIELD_MAP);
  values.occurred_on ??= toIsoDate(new Date());
  const row = await unwrap(
    supabase.from('transactions').insert(values).select(TRANSACTION_COLUMNS).single(),
  );
  return toTransaction(row);
}

export async function updateTransaction(supabase, id, input) {
  const changes = pickDefined(input, FIELD_MAP);

  // Switching income <-> expense without choosing a new category: the old
  // category no longer fits, so clear it instead of failing.
  if (changes.type && changes.category_id === undefined) {
    const current = await getRow(supabase, id, 'type, category:categories(type)');
    if (current.category && current.category.type !== changes.type) changes.category_id = null;
  }

  const row = await unwrap(
    supabase.from('transactions').update(changes).eq('id', id).select(TRANSACTION_COLUMNS).maybeSingle(),
  );
  if (!row) throw ApiError.notFound('Transaction');
  return toTransaction(row);
}

/** Deletes the row first, then its receipt file (if any). */
export async function deleteTransaction(supabase, id) {
  const row = await unwrap(
    supabase.from('transactions').delete().eq('id', id).select('id, receipt_path').maybeSingle(),
  );
  if (!row) throw ApiError.notFound('Transaction');
  if (row.receipt_path) await removeFilesQuietly(supabase, BUCKETS.receipts, [row.receipt_path]);
  return { deleted: true, id: row.id };
}

/**
 * Attaches (or replaces) a receipt. This is an orchestration across two
 * systems — Storage and the database — that cannot share one transaction,
 * so each step undoes the previous one if it fails:
 *
 *   1. make sure the transaction exists and is ours
 *   2. upload the new file
 *   3. point the row at the new file — only if nobody changed the receipt
 *      meanwhile (optimistic lock on the old path)
 *        - on failure: delete the uploaded file again (no orphans)
 *   4. delete the old file
 */
export async function attachReceipt(supabase, userId, id, file) {
  const current = await getRow(supabase, id, 'id, receipt_path');
  const oldPath = current.receipt_path;

  const newPath = await uploadFile(
    supabase, BUCKETS.receipts, storagePath(userId, id, file.extension), file.buffer, file.mimeType,
  );

  let row;
  try {
    let query = supabase.from('transactions').update({ receipt_path: newPath }).eq('id', id);
    query = oldPath ? query.eq('receipt_path', oldPath) : query.is('receipt_path', null);
    row = await unwrap(query.select(TRANSACTION_COLUMNS).maybeSingle());
    if (!row) {
      throw ApiError.conflict('The receipt was changed at the same time. Please try again.', 'receipt_conflict');
    }
  } catch (err) {
    await removeFilesQuietly(supabase, BUCKETS.receipts, [newPath]);
    throw err;
  }

  if (oldPath) await removeFilesQuietly(supabase, BUCKETS.receipts, [oldPath]);
  return toTransaction(row);
}

export async function removeReceipt(supabase, id) {
  const current = await getRow(supabase, id, 'id, receipt_path');
  if (!current.receipt_path) return getTransaction(supabase, id);
  const row = await unwrap(
    supabase.from('transactions').update({ receipt_path: null }).eq('id', id).select(TRANSACTION_COLUMNS).single(),
  );
  await removeFilesQuietly(supabase, BUCKETS.receipts, [current.receipt_path]);
  return toTransaction(row);
}

/** Receipts are private: the app gets a link that works for 5 minutes. */
export async function getReceiptUrl(supabase, id) {
  const { receipt_path: path } = await getRow(supabase, id, 'id, receipt_path');
  if (!path) throw ApiError.notFound('Receipt');
  return signedUrl(supabase, BUCKETS.receipts, path, 300);
}
