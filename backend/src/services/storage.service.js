import { unwrap } from '../lib/errors.js';

/**
 * Thin wrappers around Supabase Storage. They use the user's client, so
 * the Storage policies (files live in "<user id>/...") are enforced.
 */

export async function uploadFile(supabase, bucket, path, buffer, contentType) {
  await unwrap(
    supabase.storage.from(bucket).upload(path, buffer, { contentType, upsert: false, cacheControl: '3600' }),
  );
  return path;
}

/**
 * Best-effort delete used for clean-up. A failure here must never break
 * the main operation (the row change already succeeded), so we only log.
 */
export async function removeFilesQuietly(supabase, bucket, paths) {
  const list = paths.filter(Boolean);
  for (let i = 0; i < list.length; i += 100) {
    const chunk = list.slice(i, i + 100);
    try {
      const { error } = await supabase.storage.from(bucket).remove(chunk);
      if (error) console.warn(`Storage clean-up failed in "${bucket}":`, error.message);
    } catch (err) {
      console.warn(`Storage clean-up failed in "${bucket}":`, err.message);
    }
  }
}

/** Lists every file name inside "<folder>/" (paged, Storage returns max 1000). */
export async function listFolder(supabase, bucket, folder) {
  const names = [];
  for (let offset = 0; ; offset += 1000) {
    const data = await unwrap(supabase.storage.from(bucket).list(folder, { limit: 1000, offset }));
    names.push(...data.filter((f) => f.id).map((f) => `${folder}/${f.name}`));
    if (data.length < 1000) return names;
  }
}

export async function signedUrl(supabase, bucket, path, expiresIn = 300) {
  const data = await unwrap(supabase.storage.from(bucket).createSignedUrl(path, expiresIn));
  return { url: data.signedUrl, expiresIn };
}

export function publicUrl(supabase, bucket, path) {
  return supabase.storage.from(bucket).getPublicUrl(path).data.publicUrl;
}
