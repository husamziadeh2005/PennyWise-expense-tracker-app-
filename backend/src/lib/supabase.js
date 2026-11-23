import { createClient } from '@supabase/supabase-js';
import { config } from '../config.js';

const serverOptions = {
  auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false },
};

/**
 * Shared client used ONLY to verify access tokens (auth.getClaims).
 * It never reads or writes data.
 */
export const authClient = createClient(config.supabaseUrl, config.supabasePublishableKey, serverOptions);

/**
 * Creates a client that acts as the signed-in user.
 *
 * Every query sent with it carries the user's JWT, so Postgres knows who
 * they are (auth.uid()) and Row Level Security only lets them touch their
 * own rows. Even a bug in this API cannot leak another user's data.
 */
export function createUserClient(accessToken) {
  return createClient(config.supabaseUrl, config.supabasePublishableKey, {
    ...serverOptions,
    accessToken: async () => accessToken,
  });
}

/**
 * Admin client (bypasses RLS). Only exists when SUPABASE_SECRET_KEY is set
 * and is used for nothing except deleting an account.
 */
export const adminClient = config.supabaseSecretKey
  ? createClient(config.supabaseUrl, config.supabaseSecretKey, serverOptions)
  : null;

export const BUCKETS = Object.freeze({ receipts: 'receipts', avatars: 'avatars' });
