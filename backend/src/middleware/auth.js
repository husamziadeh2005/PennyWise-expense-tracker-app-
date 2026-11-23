import { isAuthRetryableFetchError } from '@supabase/supabase-js';
import { authClient, createUserClient } from '../lib/supabase.js';
import { ApiError } from '../lib/errors.js';

const isNetworkError = (err) =>
  isAuthRetryableFetchError(err) ||
  (err instanceof TypeError && /fetch/i.test(err.message)) ||
  Number(err?.status) >= 500;

/**
 * requireAuth — protects every /api route except /api/health.
 *
 * How login works end to end:
 *   1. The Flutter app logs in with Supabase Auth (email, phone, Google…)
 *      and receives an access token (a signed JWT, valid ~1 hour) plus a
 *      refresh token. The Supabase SDK refreshes the token automatically.
 *   2. Every API request sends:  Authorization: Bearer <access token>
 *   3. This middleware VERIFIES the token's signature and expiry with
 *      Supabase's public keys (getClaims). A fake or expired token -> 401.
 *   4. On success we attach:
 *        req.user     -> { id, email, phone, role, sessionId }
 *        req.supabase -> a Supabase client acting AS this user, so Row
 *                        Level Security applies to every query.
 */
export async function requireAuth(req, res, next) {
  const header = req.get('authorization') ?? '';
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  if (!match) {
    return next(ApiError.unauthorized('Missing access token. Please log in.', 'missing_token'));
  }
  const token = match[1];

  const invalid = () =>
    ApiError.unauthorized('Your session has expired. Please log in again.', 'invalid_token');
  const unavailable = () =>
    new ApiError(503, 'auth_unavailable', 'Authentication service is unavailable. Please try again.');

  let claims;
  try {
    const { data, error } = await authClient.auth.getClaims(token);
    if (error) return next(isNetworkError(error) ? unavailable() : invalid());
    if (!data?.claims) return next(invalid());
    claims = data.claims;
  } catch (err) {
    // A garbled token makes the decoder throw -> 401. Only a real network
    // problem (Supabase unreachable while fetching its public keys) is 503.
    return next(isNetworkError(err) ? unavailable() : invalid());
  }

  // Only real signed-in users ("authenticated"), never the anon key itself.
  if (claims.role !== 'authenticated' || !claims.sub) {
    return next(ApiError.unauthorized('Please log in.', 'invalid_token'));
  }

  req.user = {
    id: claims.sub,
    email: claims.email || null,
    phone: claims.phone || null,
    role: claims.role,
    provider: claims.app_metadata?.provider ?? null,
    sessionId: claims.session_id ?? null,
    isAnonymous: claims.is_anonymous === true,
  };
  req.accessToken = token;
  req.supabase = createUserClient(token);
  return next();
}
