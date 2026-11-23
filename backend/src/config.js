/**
 * Reads settings from environment variables (the .env file in development)
 * and fails fast at start-up if something required is missing, instead of
 * failing later on the first request.
 */

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`Missing required environment variable ${name}. Copy .env.example to .env and fill it in.`);
  }
  return value;
}

function list(name, fallback = '') {
  return (process.env[name] ?? fallback)
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

export const config = Object.freeze({
  port: Number(process.env.PORT ?? 3000),
  env: process.env.NODE_ENV ?? 'development',

  supabaseUrl: required('SUPABASE_URL').replace(/\/+$/, ''),
  // Publishable key: safe to share. Every database call is made "as the
  // user" (with their JWT), so Row Level Security decides what is allowed.
  supabasePublishableKey: required('SUPABASE_PUBLISHABLE_KEY'),
  // OPTIONAL secret key. Only used for the one thing that needs admin
  // rights: permanently deleting the user's account. Never ship it in the app.
  supabaseSecretKey: process.env.SUPABASE_SECRET_KEY?.trim() || null,

  // Browser origins allowed to call the API (only matters for Flutter web).
  corsOrigins: list('CORS_ORIGINS'),
  // Set to 1 when running behind a proxy / load balancer (Render, Railway…)
  trustProxy: Number(process.env.TRUST_PROXY ?? 0),
});

export const isProduction = config.env === 'production';
