import { ApiError, unwrap } from '../lib/errors.js';
import { BUCKETS, adminClient } from '../lib/supabase.js';
import { listFolder, removeFilesQuietly } from './storage.service.js';

export const accountDeletionEnabled = () => adminClient !== null;

/**
 * "Reset all data": deletes every transaction, budget and category and
 * restores the default categories. The database part is ONE transaction
 * (reset_my_data); afterwards the receipt files are cleaned up.
 */
export async function resetMyData(supabase, userId) {
  const receiptPaths = (await unwrap(supabase.rpc('reset_my_data'))) ?? [];
  // also catch any file that was not linked to a row anymore
  const leftovers = await listFolder(supabase, BUCKETS.receipts, userId).catch(() => []);
  await removeFilesQuietly(supabase, BUCKETS.receipts, [...new Set([...receiptPaths, ...leftovers])]);
  return { reset: true, removedReceipts: receiptPaths.length };
}

/**
 * Permanently deletes the account (required by the App Store / Play Store
 * for apps with sign-up). Needs SUPABASE_SECRET_KEY on the server.
 * Order: files first (they would otherwise be orphaned), then the auth
 * user — the database rows are removed by ON DELETE CASCADE.
 */
export async function deleteAccount(supabase, userId) {
  if (!adminClient) {
    throw new ApiError(501, 'not_configured', 'Account deletion is not enabled on this server.');
  }
  for (const bucket of [BUCKETS.receipts, BUCKETS.avatars]) {
    const files = await listFolder(supabase, bucket, userId).catch(() => []);
    await removeFilesQuietly(supabase, bucket, files);
  }
  const { error } = await adminClient.auth.admin.deleteUser(userId);
  if (error) {
    const err = new ApiError(500, 'delete_failed', 'Could not delete the account. Please try again.');
    err.cause = error;
    throw err;
  }
  return { deleted: true };
}
