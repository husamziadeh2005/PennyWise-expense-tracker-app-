#!/usr/bin/env node
/**
 * Google sign-in setup + diagnosis for PennyWise.
 *
 *   node scripts/google-login.mjs check    # what works, what is missing (no secrets needed)
 *   node scripts/google-login.mjs enable   # switch Google on in Supabase + add redirect URLs
 *
 * `enable` asks for (hidden input, nothing is saved or printed):
 *   1. the Google OAuth Client ID + Client secret (from Google Cloud Console)
 *   2. a Supabase personal access token (https://supabase.com/dashboard/account/tokens),
 *      or set SUPABASE_ACCESS_TOKEN in your shell instead
 *
 * It uses the Supabase Management API: PATCH /v1/projects/{ref}/config/auth
 */
import readline from 'node:readline';

const PROJECT_REF = 'dwvqxftefejqxcopbvfz';
const SUPABASE_URL = `https://${PROJECT_REF}.supabase.co`;
const PUBLISHABLE_KEY = 'sb_publishable_hpxBvj-iG0YeP8xO25Lezw_W0kdhLPP';
const CALLBACK_URL = `${SUPABASE_URL}/auth/v1/callback`; // goes into Google Cloud Console
const REDIRECT_URLS = [
  'io.supabase.pennywise://login-callback/', // phone + desktop app
  'http://localhost:5000/**', //               Flutter web (scripts/dev.sh -d chrome)
];

const ok = (s) => console.log(`  \x1b[32m✔\x1b[0m ${s}`);
const bad = (s) => console.log(`  \x1b[31m✖\x1b[0m ${s}`);
const info = (s) => console.log(`    ${s}`);

// ------------------------------------------------------------------- check

async function check() {
  console.log('\nGoogle sign-in check\n');
  let allGood = true;

  // 1. Is Google switched on in Supabase?
  const settings = await fetch(`${SUPABASE_URL}/auth/v1/settings`, { headers: { apikey: PUBLISHABLE_KEY } })
    .then((r) => r.json());
  if (settings.external?.google) {
    ok('Google is enabled in Supabase');
  } else {
    bad('Google is turned OFF in Supabase');
    info('Fix: node scripts/google-login.mjs enable');
    return false; // nothing else can work yet
  }

  // 2. Does Supabase send the browser to Google with a client id?
  const authorize = await fetch(
    `${SUPABASE_URL}/auth/v1/authorize?provider=google&redirect_to=${encodeURIComponent(REDIRECT_URLS[0])}`,
    { redirect: 'manual' },
  );
  const location = authorize.headers.get('location') ?? '';
  if (authorize.status !== 302 || !location.startsWith('https://accounts.google.com/')) {
    bad(`Supabase did not redirect to Google (HTTP ${authorize.status})`);
    return false;
  }
  const googleUrl = new URL(location);
  const clientId = googleUrl.searchParams.get('client_id') ?? '';
  ok(`Supabase redirects to Google (client id ${clientId.slice(0, 12)}…)`);
  if (!clientId.endsWith('.apps.googleusercontent.com')) {
    bad('The Client ID does not look like a Google OAuth client id');
    info('It must end with .apps.googleusercontent.com, so re-run enable with the right value');
    allGood = false;
  }

  // 3. Does Google accept that client id and the Supabase callback URL?
  const verdict = await askGoogle(location);
  if (verdict.kind === 'redirect_uri_mismatch') {
    bad('Google rejects the callback URL (redirect_uri_mismatch)');
    info('Fix: Google Cloud Console → Credentials → your OAuth client → Authorised redirect URIs → add');
    info(`     ${CALLBACK_URL}`);
    allGood = false;
  } else if (verdict.kind === 'invalid_client') {
    bad('Google does not know this Client ID (invalid_client)');
    info('Fix: copy the Client ID again from Google Cloud Console and re-run enable');
    allGood = false;
  } else if (verdict.kind === 'error') {
    bad(`Google refused the request (${verdict.detail})`);
    info("Open this in a browser to see Google's explanation:");
    info(location);
    allGood = false;
  } else {
    ok('Google accepts the Client ID and the Supabase callback URL');
  }

  console.log(allGood
    ? '\n  Google sign-in is ready. Tap the G button in the app.\n'
    : '\n  Fix the ✖ items above, then run this check again.\n');
  info('Also needed (the check cannot see it): Supabase → Authentication → URL Configuration →');
  info(`Redirect URLs must include: ${REDIRECT_URLS.join('  and  ')}`);
  info('("enable" adds them for you.) While the Google consent screen is in "Testing",');
  info('only accounts listed as Test users can sign in.\n');
  return allGood;
}

/**
 * Asks Google whether it accepts an authorize URL, without logging in.
 * Google reports problems by redirecting to /signin/oauth/error with the
 * reason base64-encoded in "authError" (e.g. "invalid_client …").
 * Returns { kind: 'ok' | 'redirect_uri_mismatch' | 'invalid_client' | 'error', detail }.
 */
export async function askGoogle(authorizeUrl) {
  const res = await fetch(authorizeUrl, { redirect: 'manual' });
  const next = res.headers.get('location') ?? '';
  let text = '';
  if (next.includes('/signin/oauth/error')) {
    const encoded = new URL(next, 'https://accounts.google.com').searchParams.get('authError') ?? '';
    text = Buffer.from(encoded, 'base64url').toString('latin1');
  } else if (res.status >= 400) {
    text = await res.text();
  } else {
    return { kind: 'ok', detail: '' };
  }
  const detail = text.replace(/[^\x20-\x7e]+/g, ' ').trim().slice(0, 200) || `HTTP ${res.status}`;
  if (/redirect_uri_mismatch/i.test(text)) return { kind: 'redirect_uri_mismatch', detail };
  if (/invalid_client|OAuth client was not found|deleted_client/i.test(text)) return { kind: 'invalid_client', detail };
  return { kind: 'error', detail };
}

// ------------------------------------------------------------------ enable

function ask(question, { hidden = false } = {}) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout, terminal: true });
    if (hidden) {
      // print the question, then swallow every typed character
      rl._writeToOutput = (s) => { if (s.startsWith(question)) rl.output.write(s); };
    }
    rl.question(question, (answer) => {
      rl.close();
      if (hidden) process.stdout.write('\n');
      resolve(answer.trim());
    });
  });
}

async function managementApi(token, method, body) {
  const res = await fetch(`https://api.supabase.com/v1/projects/${PROJECT_REF}/config/auth`, {
    method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (res.status === 401 || res.status === 403) {
    throw new Error('Supabase rejected the access token. Create one at https://supabase.com/dashboard/account/tokens');
  }
  if (!res.ok) throw new Error(`Supabase Management API ${method} failed (HTTP ${res.status}): ${text.slice(0, 300)}`);
  return text ? JSON.parse(text) : {};
}

async function enable() {
  console.log(`
Before you start, in Google Cloud Console (https://console.cloud.google.com):
  APIs & Services → Credentials → Create credentials → OAuth client ID
    • Application type: Web application
    • Authorised redirect URIs: ${CALLBACK_URL}
  Then copy the Client ID and Client secret.
`);
  const clientId = await ask('Google Client ID: ');
  if (!/^[\w-]+\.apps\.googleusercontent\.com$/.test(clientId)) {
    throw new Error('That is not a Google OAuth Client ID (it ends with .apps.googleusercontent.com).');
  }
  const secret = await ask('Google Client secret (hidden): ', { hidden: true });
  if (secret.length < 10) throw new Error('The Client secret looks too short.');
  const token = process.env.SUPABASE_ACCESS_TOKEN?.trim()
    || await ask('Supabase access token, sbp_… (hidden): ', { hidden: true });
  if (!token) throw new Error('A Supabase access token is required.');

  // Merge our redirect URLs into the existing list (never drop yours).
  const current = await managementApi(token, 'GET');
  const existing = (current.uri_allow_list ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  const merged = [...new Set([...existing, ...REDIRECT_URLS])];

  await managementApi(token, 'PATCH', {
    external_google_enabled: true,
    external_google_client_id: clientId,
    external_google_secret: secret,
    uri_allow_list: merged.join(','),
  });
  ok('Google enabled in Supabase');
  ok(`Redirect URLs: ${merged.join(', ')}`);

  // Auth settings can take a few seconds to apply.
  for (let i = 0; i < 10; i++) {
    const s = await fetch(`${SUPABASE_URL}/auth/v1/settings`, { headers: { apikey: PUBLISHABLE_KEY } }).then((r) => r.json());
    if (s.external?.google) break;
    await new Promise((r) => setTimeout(r, 2000));
  }
  return check();
}

// -------------------------------------------------------------------- main

const isMain = import.meta.url === `file://${process.argv[1]}`;
const command = process.argv[2] ?? 'check';
const run = { check, enable }[command];
if (isMain && !run) {
  console.error('Usage: node scripts/google-login.mjs [check|enable]');
  process.exit(2);
}
if (isMain) run()
  .then((good) => process.exit(good ? 0 : 1))
  .catch((err) => {
    console.error(`\n  \x1b[31m✖ ${err.message}\x1b[0m\n`);
    process.exit(1);
  });
