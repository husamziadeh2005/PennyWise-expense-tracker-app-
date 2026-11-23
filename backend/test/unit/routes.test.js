import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';

process.env.SUPABASE_URL ??= 'https://example.supabase.co';
process.env.SUPABASE_PUBLISHABLE_KEY ??= 'sb_publishable_test';

const { createApp } = await import('../../src/app.js');
const { requireAuth } = await import('../../src/middleware/auth.js');
const { fakeSupabase, has } = await import('./fakeSupabase.js');

const USER = { id: '11111111-1111-4111-8111-111111111111' };
const TX_ID = '22222222-2222-4222-8222-222222222222';
const CAT_ID = '33333333-3333-4333-8333-333333333333';

/** App whose "logged in user" uses the given fake Supabase client. */
function appWith(supabase) {
  return createApp({
    silent: true,
    authenticate: (req, res, next) => {
      req.user = USER;
      req.supabase = supabase;
      next();
    },
  });
}

const txRow = (over = {}) => ({
  id: TX_ID, type: 'expense', amount: '12.50', category_id: CAT_ID, note: null,
  occurred_on: '2026-11-19', receipt_path: null, created_at: 'x', updated_at: 'x',
  category: { id: CAT_ID, name: 'Food', type: 'expense', icon: 'restaurant', color: '#E57373' },
  ...over,
});

describe('authentication', () => {
  const app = createApp({ silent: true }); // the REAL requireAuth

  test('no token -> 401', async () => {
    const res = await request(app).get('/api/transactions');
    assert.equal(res.status, 401);
    assert.equal(res.body.error.code, 'missing_token');
  });

  test('malformed tokens -> 401, never 500/503', async () => {
    for (const token of ['abc.def.ghi', 'garbage', 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.x']) {
      const res = await request(app).get('/api/transactions').set('Authorization', `Bearer ${token}`);
      assert.equal(res.status, 401, token);
      assert.equal(res.body.error.code, 'invalid_token');
    }
  });

  test('wrong scheme -> 401', async () => {
    const res = await request(app).get('/api/transactions').set('Authorization', 'Basic abc');
    assert.equal(res.status, 401);
  });

  test('CORS: Flutter web on any localhost port is allowed, other sites are not', async () => {
    const ok = await request(app).options('/api/transactions')
      .set('Origin', 'http://localhost:61234').set('Access-Control-Request-Method', 'GET');
    assert.equal(ok.headers['access-control-allow-origin'], 'http://localhost:61234');
    const evil = await request(app).get('/api/health').set('Origin', 'https://evil.example');
    assert.equal(evil.headers['access-control-allow-origin'], undefined);
  });

  test('health is public', async () => {
    const res = await request(app).get('/api/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
  });

  test('requireAuth sets req.user from verified claims', async () => {
    // Swap the verifier for this one test
    const { authClient } = await import('../../src/lib/supabase.js');
    const original = authClient.auth.getClaims;
    authClient.auth.getClaims = async () => ({
      data: { claims: { sub: USER.id, role: 'authenticated', email: 'a@b.co', app_metadata: { provider: 'email' } } },
      error: null,
    });
    try {
      const req = { get: () => 'Bearer good.token.here' };
      await new Promise((resolve, reject) => requireAuth(req, {}, (err) => (err ? reject(err) : resolve())));
      assert.equal(req.user.id, USER.id);
      assert.equal(req.user.email, 'a@b.co');
      assert.ok(req.supabase);

      // the anon role (no user) must be rejected
      authClient.auth.getClaims = async () => ({ data: { claims: { role: 'anon' } }, error: null });
      const req2 = { get: () => 'Bearer anon.token.here' };
      const err = await new Promise((resolve) => requireAuth(req2, {}, resolve));
      assert.equal(err.status, 401);
    } finally {
      authClient.auth.getClaims = original;
    }
  });
});

describe('transactions', () => {
  test('create: validation errors never reach the database', async () => {
    const sb = fakeSupabase();
    const res = await request(appWith(sb)).post('/api/transactions').send({ type: 'expense', amount: -3 });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'validation_failed');
    assert.equal(res.body.error.details[0].field, 'amount');
    assert.equal(sb.calls.length, 0);
  });

  test('create: user_id from the body is ignored, response is camelCase', async () => {
    const sb = fakeSupabase(() => ({ data: txRow(), error: null }));
    const res = await request(appWith(sb))
      .post('/api/transactions')
      .send({ type: 'expense', amount: '12.50', categoryId: CAT_ID, user_id: 'evil', occurredOn: '2026-11-19' });
    assert.equal(res.status, 201);
    const [, inserted] = has(sb.calls[0], 'insert');
    assert.deepEqual(inserted, { type: 'expense', amount: 12.5, category_id: CAT_ID, note: null, occurred_on: '2026-11-19' });
    assert.equal(res.body.amount, 12.5);
    assert.equal(res.body.occurredOn, '2026-11-19');
    assert.equal(res.body.category.name, 'Food');
    assert.equal(res.body.hasReceipt, false);
  });

  test('create: category type mismatch from the DB trigger -> 400 with clear code', async () => {
    const sb = fakeSupabase(() => ({ data: null, error: { code: '23514', hint: 'category_type_mismatch' } }));
    const res = await request(appWith(sb)).post('/api/transactions').send({ type: 'income', amount: 1, categoryId: CAT_ID });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'category_type_mismatch');
  });

  test('get: invalid id -> 400, unknown id -> 404', async () => {
    const sb = fakeSupabase(() => ({ data: null, error: null }));
    assert.equal((await request(appWith(sb)).get('/api/transactions/123')).status, 400);
    const res = await request(appWith(sb)).get(`/api/transactions/${TX_ID}`);
    assert.equal(res.status, 404);
    assert.equal(res.body.error.message, 'Transaction not found.');
  });

  test('list: filters and paging are passed to the query', async () => {
    const sb = fakeSupabase(() => ({ data: [txRow()], error: null, count: 41 }));
    const res = await request(appWith(sb)).get(
      '/api/transactions?type=expense&from=2026-11-01&to=2026-11-30&q=50%25_off&limit=20&offset=20',
    );
    assert.equal(res.status, 200);
    assert.equal(res.body.total, 41);
    assert.equal(res.body.hasMore, true);
    const q = sb.calls[0];
    assert.deepEqual(has(q, 'range').slice(1), [20, 39]);
    assert.deepEqual(has(q, 'eq').slice(1), ['type', 'expense']);
    assert.deepEqual(has(q, 'ilike').slice(1), ['note', '%50\\%\\_off%']); // wildcards escaped
  });

  test('update: switching type clears a category of the wrong type', async () => {
    const sb = fakeSupabase(({ ops }) =>
      has({ ops }, 'update')
        ? { data: txRow({ type: 'income', category_id: null, category: null }), error: null }
        : { data: { type: 'expense', category: { type: 'expense' } }, error: null });
    const res = await request(appWith(sb)).patch(`/api/transactions/${TX_ID}`).send({ type: 'income' });
    assert.equal(res.status, 200);
    const [, changes] = has(sb.calls[1], 'update');
    assert.deepEqual(changes, { type: 'income', category_id: null });
  });

  test('update: empty body -> 400', async () => {
    const res = await request(appWith(fakeSupabase())).patch(`/api/transactions/${TX_ID}`).send({});
    assert.equal(res.status, 400);
  });

  test('delete also removes the receipt file', async () => {
    const sb = fakeSupabase(({ table }) =>
      table === 'transactions'
        ? { data: { id: TX_ID, receipt_path: `${USER.id}/r.jpg` }, error: null }
        : { data: [], error: null });
    const removed = [];
    const realStorage = sb.storage.from;
    sb.storage.from = (bucket) => ({ ...realStorage(bucket), remove: async (p) => { removed.push(...p); return { error: null }; } });
    const res = await request(appWith(sb)).delete(`/api/transactions/${TX_ID}`);
    assert.equal(res.status, 200);
    assert.deepEqual(removed, [`${USER.id}/r.jpg`]);
  });

  test('receipt upload: rejects files that are not images/PDF by content', async () => {
    const sb = fakeSupabase(() => ({ data: { id: TX_ID, receipt_path: null }, error: null }));
    const res = await request(appWith(sb))
      .put(`/api/transactions/${TX_ID}/receipt`)
      .attach('file', Buffer.from('<html><script>alert(1)</script></html>'), { filename: 'x.jpg', contentType: 'image/jpeg' });
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'unsupported_file_type');
  });

  test('receipt upload: if saving fails, the uploaded file is deleted again', async () => {
    const removed = [];
    const sb = fakeSupabase(({ ops }) =>
      has({ ops }, 'update') ? { data: null, error: { code: 'XX000' } } : { data: { id: TX_ID, receipt_path: null }, error: null });
    const realStorage = sb.storage.from;
    sb.storage.from = (bucket) => ({
      ...realStorage(bucket),
      upload: async () => ({ data: {}, error: null }),
      remove: async (p) => { removed.push(...p); return { error: null }; },
    });
    const png = Buffer.concat([Buffer.from('89504e470d0a1a0a0000000d49484452', 'hex'), Buffer.alloc(20)]);
    const res = await request(appWith(sb)).put(`/api/transactions/${TX_ID}/receipt`).attach('file', png, 'r.png');
    assert.equal(res.status, 500);
    assert.equal(removed.length, 1);
    assert.match(removed[0], new RegExp(`^${USER.id}/${TX_ID}-.+\\.png$`));
  });
});

describe('categories, budgets, misc', () => {
  test('duplicate category -> 409 with friendly message', async () => {
    const sb = fakeSupabase(() => ({ data: null, error: { code: '23505' } }));
    const res = await request(appWith(sb)).post('/api/categories').send({ name: 'Food', type: 'expense' });
    assert.equal(res.status, 409);
    assert.equal(res.body.error.message, 'You already have a category with this name.');
  });

  test('delete category calls the transactional RPC', async () => {
    const sb = fakeSupabase(() => ({ data: 3, error: null }));
    const res = await request(appWith(sb)).delete(`/api/categories/${CAT_ID}?reassignTo=${TX_ID}`);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { deleted: true, affectedTransactions: 3 });
    assert.deepEqual(sb.calls[0].ops[0][1], { p_category_id: CAT_ID, p_reassign_to: TX_ID });
  });

  test('duplicate overall budget -> 409', async () => {
    const sb = fakeSupabase(() => ({ data: null, error: { code: '23505' } }));
    const res = await request(appWith(sb)).post('/api/budgets').send({ amount: 100 });
    assert.equal(res.status, 409);
    assert.match(res.body.error.message, /overall budget/);
  });

  test('bad JSON -> 400', async () => {
    const res = await request(appWith(fakeSupabase()))
      .post('/api/categories').set('Content-Type', 'application/json').send('{"name":');
    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'invalid_json');
  });

  test('unknown database errors return a generic message + request id', async () => {
    const sb = fakeSupabase(() => ({ data: null, error: { code: 'XX000', message: 'secret internals' } }));
    const res = await request(appWith(sb)).get('/api/categories');
    assert.equal(res.status, 500);
    assert.equal(res.body.error.message, 'Something went wrong. Please try again.');
    assert.ok(res.body.error.requestId);
  });

  test('account deletion is disabled without a secret key', async () => {
    const res = await request(appWith(fakeSupabase())).delete('/api/account');
    assert.equal(res.status, 501);
  });
});
