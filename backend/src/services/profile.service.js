import { ApiError, unwrap } from '../lib/errors.js';
import { BUCKETS } from '../lib/supabase.js';
import { storagePath } from '../lib/files.js';
import { PROFILE_COLUMNS, pickDefined, toProfile } from './mappers.js';
import { listFolder, publicUrl, removeFilesQuietly, uploadFile } from './storage.service.js';

export async function getProfile(supabase, userId) {
  const row = await unwrap(supabase.from('profiles').select(PROFILE_COLUMNS).eq('id', userId).maybeSingle());
  if (!row) throw ApiError.notFound('Profile');
  return toProfile(row);
}

export async function updateProfile(supabase, userId, input) {
  const changes = pickDefined(input, {
    fullName: 'full_name',
    country: 'country',
    gender: 'gender',
    currency: 'currency',
  });
  const row = await unwrap(
    supabase.from('profiles').update(changes).eq('id', userId).select(PROFILE_COLUMNS).maybeSingle(),
  );
  if (!row) throw ApiError.notFound('Profile');
  return toProfile(row);
}

/** True when the URL points to a file in OUR avatars bucket. */
const isOurAvatar = (supabase, url) => Boolean(url) && url.startsWith(publicUrl(supabase, BUCKETS.avatars, ''));

/**
 * Upload new photo -> save its URL on the profile -> delete older photos.
 * If saving the URL fails, the new upload is removed again.
 */
export async function uploadAvatar(supabase, userId, file) {
  const path = await uploadFile(
    supabase, BUCKETS.avatars, storagePath(userId, 'avatar', file.extension), file.buffer, file.mimeType,
  );
  let profile;
  try {
    profile = await updateProfileAvatar(supabase, userId, publicUrl(supabase, BUCKETS.avatars, path));
  } catch (err) {
    await removeFilesQuietly(supabase, BUCKETS.avatars, [path]);
    throw err;
  }
  const old = (await listFolder(supabase, BUCKETS.avatars, userId).catch(() => [])).filter((p) => p !== path);
  await removeFilesQuietly(supabase, BUCKETS.avatars, old);
  return profile;
}

export async function removeAvatar(supabase, userId) {
  const current = await getProfile(supabase, userId);
  const profile = await updateProfileAvatar(supabase, userId, null);
  if (isOurAvatar(supabase, current.avatarUrl)) {
    const files = await listFolder(supabase, BUCKETS.avatars, userId).catch(() => []);
    await removeFilesQuietly(supabase, BUCKETS.avatars, files);
  }
  return profile;
}

async function updateProfileAvatar(supabase, userId, url) {
  const row = await unwrap(
    supabase.from('profiles').update({ avatar_url: url }).eq('id', userId).select(PROFILE_COLUMNS).maybeSingle(),
  );
  if (!row) throw ApiError.notFound('Profile');
  return toProfile(row);
}
