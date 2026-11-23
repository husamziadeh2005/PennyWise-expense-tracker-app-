/**
 * End-to-end tests against the REAL Supabase project.
 *
 * Needs two confirmed test accounts (email + password) in .env:
 *   E2E_EMAIL_A=...   E2E_PASSWORD_A=...
 *   E2E_EMAIL_B=...   E2E_PASSWORD_B=...
 *
 * WARNING: the test calls "reset data" for both accounts at the start and
 * the end. Never use your personal account here.
 *
 * Run:  npm run test:e2e
 */
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import { createClient } from '@supabase/supabase-js';

const { E2E_EMAIL_A, E2E_PASSWORD_A, E2E_EMAIL_B, E2E_PASSWORD_B } = process.env;
const configured = E2E_EMAIL_A && E2E_PASSWORD_A && E2E_EMAIL_B && E2E_PASSWORD_B;

const { createApp } = await import('../../src/app.js');
const app = createApp({ silent: true });

async function login(email, password) {
  const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_PUBLISHABLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await sb.auth.signInWithPassword({ email, password });
  if (error) throw new Error(`Login failed for ${email}: ${error.message}`);
  return data.session.access_token;
}

const PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  'base64',
);

describe('PennyWise API (live)', { skip: !configured && 'set E2E_* variables in .env to run' }, () => {
  let A; let B; // helpers bound to each user's token
  let categories;
  const month = '2026-11';

  before(async () => {
    const [tokenA, tokenB] = await Promise.all([login(E2E_EMAIL_A, E2E_PASSWORD_A), login(E2E_EMAIL_B, E2E_PASSWORD_B)]);
    const as = (token) => ({
      get: (url) => request(app).get(url).set('Authorization', `Bearer ${token}`),
      post: (url, body) => request(app).post(url).set('Authorization', `Bearer ${token}`).send(body),
      patch: (url, body) => request(app).patch(url).set('Authorization', `Bearer ${token}`).send(body),
      put: (url) => request(app).put(url).set('Authorization', `Bearer ${token}`),
      del: (url) => request(app).delete(url).set('Authorization', `Bearer ${token}`),
    });
    A = as(tokenA);
    B = as(tokenB);
    assert.equal((await A.post('/api/account/reset')).status, 200);
    assert.equal((await B.post('/api/account/reset')).status, 200);
  });

  after(async () => {
    if (A) await A.post('/api/account/reset');
    if (B) await B.post('/api/account/reset');
  });

  test('auth/me returns the user and profile', async () => {
    const res = await A.get('/api/auth/me');
    assert.equal(res.status, 200);
    assert.equal(res.body.user.email, E2E_EMAIL_A.toLowerCase());
    assert.ok(res.body.profile);
  });

  test('new accounts get 12 default categories', async () => {
    const res = await A.get('/api/categories');
    assert.equal(res.status, 200);
    categories = res.body.items;
    assert.equal(categories.length, 12);
    assert.equal((await A.get('/api/categories?type=income')).body.items.length, 4);
  });

  const cat = (name) => categories.find((c) => c.name === name);

  test('category CRUD + duplicate protection', async () => {
    const created = await A.post('/api/categories', { name: 'Coffee', type: 'expense', icon: 'coffee', color: '#795548' });
    assert.equal(created.status, 201);
    assert.equal((await A.post('/api/categories', { name: ' coffee ', type: 'expense' })).status, 409);
    // same name, other type is fine
    assert.equal((await A.post('/api/categories', { name: 'Coffee', type: 'income' })).status, 201);
    const renamed = await A.patch(`/api/categories/${created.body.id}`, { name: 'Coffee & Tea' });
    assert.equal(renamed.body.name, 'Coffee & Tea');
    categories = (await A.get('/api/categories')).body.items;
  });

  let t1; let t2; let t3;
  test('transaction CRUD', async () => {
    const r1 = await A.post('/api/transactions', { type: 'expense', amount: '0.10', categoryId: cat('Food & Dining').id, occurredOn: `${month}-02`, note: 'Gum' });
    const r2 = await A.post('/api/transactions', { type: 'expense', amount: 0.2, categoryId: cat('Food & Dining').id, occurredOn: `${month}-02` });
    const r3 = await A.post('/api/transactions', { type: 'income', amount: 1500, categoryId: cat('Salary').id, occurredOn: `${month}-01` });
    for (const r of [r1, r2, r3]) assert.equal(r.status, 201, JSON.stringify(r.body));
    [t1, t2, t3] = [r1.body, r2.body, r3.body];
    assert.equal(t1.category.name, 'Food & Dining');

    const got = await A.get(`/api/transactions/${t1.id}`);
    assert.equal(got.body.note, 'Gum');

    const upd = await A.patch(`/api/transactions/${t1.id}`, { amount: 4.5, note: 'Lunch' });
    assert.equal(upd.body.amount, 4.5);
    assert.equal(upd.body.note, 'Lunch');
  });

  test('database rules: wrong category type and foreign category are rejected', async () => {
    const r = await A.post('/api/transactions', { type: 'income', amount: 1, categoryId: cat('Transport').id });
    assert.equal(r.status, 400);
    assert.equal(r.body.error.code, 'category_type_mismatch');
  });

  test('list: filters, search and paging', async () => {
    const all = await A.get(`/api/transactions?from=${month}-01&to=${month}-30`);
    assert.equal(all.body.total, 3);
    assert.equal(all.body.items[0].occurredOn, `${month}-02`); // newest first
    assert.equal((await A.get('/api/transactions?type=income')).body.total, 1);
    assert.equal((await A.get('/api/transactions?q=lun')).body.total, 1);
    const page = await A.get('/api/transactions?limit=2&offset=0');
    assert.equal(page.body.items.length, 2);
    assert.equal(page.body.hasMore, true);
    const past = await A.get('/api/transactions?limit=2&offset=50');
    assert.equal(past.status, 200);
    assert.deepEqual(past.body.items, []);
  });

  test('ISOLATION: user B cannot see or change user A data', async () => {
    assert.equal((await B.get(`/api/transactions/${t1.id}`)).status, 404);
    assert.equal((await B.patch(`/api/transactions/${t1.id}`, { amount: 1 })).status, 404);
    assert.equal((await B.del(`/api/transactions/${t1.id}`)).status, 404);
    assert.equal((await B.get('/api/transactions')).body.total, 0);
    // B cannot file a transaction under A's category
    const r = await B.post('/api/transactions', { type: 'expense', amount: 1, categoryId: cat('Transport').id });
    assert.equal(r.status, 400);
    assert.equal((await B.del(`/api/categories/${cat('Transport').id}`)).status, 404);
    // A's data is untouched
    assert.equal((await A.get(`/api/transactions/${t1.id}`)).body.amount, 4.5);
  });

  test('budgets', async () => {
    const overall = await A.post('/api/budgets', { categoryId: null, amount: 100 });
    assert.equal(overall.status, 201);
    assert.equal((await A.post('/api/budgets', { amount: 50 })).status, 409);
    const food = await A.post('/api/budgets', { categoryId: cat('Food & Dining').id, amount: 4 });
    assert.equal(food.status, 201);
    const income = await A.post('/api/budgets', { categoryId: cat('Salary').id, amount: 4 });
    assert.equal(income.status, 400);
    assert.equal((await A.patch(`/api/budgets/${overall.body.id}`, { amount: 200 })).body.amount, 200);
    assert.equal((await A.get('/api/budgets')).body.items.length, 2);
  });

  test('stats summary math', async () => {
    const res = await A.get(`/api/stats/summary?month=${month}&today=${month}-10`);
    assert.equal(res.status, 200);
    const s = res.body;
    assert.equal(s.totals.income, 1500);
    assert.equal(s.totals.expense, 4.7); // 4.5 + 0.2
    assert.equal(s.totals.balance, 1495.3);
    assert.equal(s.averages.dailyExpense, 0.47);
    assert.equal(s.topCategory.name, 'Food & Dining');
    assert.equal(s.budgets[0].name, 'Overall');
    assert.equal(s.budgets[0].spent, 4.7);
    assert.equal(s.budgets[1].status, 'over'); // 4.7 of 4
    assert.equal(s.allTime.balance, 1495.3);
  });

  test('receipts: upload, view, replace, remove', async () => {
    const up = await A.put(`/api/transactions/${t1.id}/receipt`).attach('file', PNG, 'r.png');
    assert.equal(up.status, 200, JSON.stringify(up.body));
    assert.equal(up.body.hasReceipt, true);

    const link = await A.get(`/api/transactions/${t1.id}/receipt`);
    assert.equal(link.status, 200);
    const file = await fetch(link.body.url);
    assert.equal(file.status, 200);

    // B cannot get A's receipt
    assert.equal((await B.get(`/api/transactions/${t1.id}/receipt`)).status, 404);

    const replaced = await A.put(`/api/transactions/${t1.id}/receipt`).attach('file', PNG, 'r2.png');
    assert.equal(replaced.status, 200);
    const oldLinkStillWorks = await fetch(link.body.url);
    assert.equal(oldLinkStillWorks.status >= 400, true, 'old file should be deleted');

    const bad = await A.put(`/api/transactions/${t1.id}/receipt`).attach('file', Buffer.from('not an image at all'), 'x.png');
    assert.equal(bad.status, 400);

    const removed = await A.del(`/api/transactions/${t1.id}/receipt`);
    assert.equal(removed.body.hasReceipt, false);
  });

  test('profile update + avatar', async () => {
    const p = await A.patch('/api/profile', { fullName: 'E2E Tester', currency: 'usd' });
    assert.equal(p.status, 200);
    assert.equal(p.body.currency, 'USD');
    const av = await A.put('/api/profile/avatar').attach('file', PNG, 'a.png');
    assert.equal(av.status, 200, JSON.stringify(av.body));
    assert.match(av.body.avatarUrl, /\/avatars\//);
    assert.equal((await fetch(av.body.avatarUrl)).status, 200);
    assert.equal((await A.del('/api/profile/avatar')).body.avatarUrl, null);
  });

  test('delete category: reassign, then uncategorised', async () => {
    const coffee = categories.find((c) => c.name === 'Coffee & Tea');
    await A.post('/api/transactions', { type: 'expense', amount: 3, categoryId: coffee.id, occurredOn: `${month}-03` });
    const moved = await A.del(`/api/categories/${coffee.id}?reassignTo=${cat('Food & Dining').id}`);
    assert.deepEqual(moved.body, { deleted: true, affectedTransactions: 1 });

    const wrongType = await A.del(`/api/categories/${cat('Transport').id}?reassignTo=${cat('Salary').id}`);
    assert.equal(wrongType.status, 400);

    const food = await A.del(`/api/categories/${cat('Food & Dining').id}`);
    assert.equal(food.body.affectedTransactions, 3);
    const uncategorised = await A.get('/api/transactions?categoryId=none');
    assert.equal(uncategorised.body.total, 3);
    // the Food budget was removed with the category
    assert.equal((await A.get('/api/budgets')).body.items.length, 1);
  });

  test('delete transaction', async () => {
    assert.equal((await A.del(`/api/transactions/${t2.id}`)).status, 200);
    assert.equal((await A.get(`/api/transactions/${t2.id}`)).status, 404);
    assert.equal((await A.del(`/api/transactions/${t2.id}`)).status, 404);
    assert.ok(t3);
  });

  test('reset restores defaults', async () => {
    const r = await A.post('/api/account/reset');
    assert.equal(r.status, 200);
    assert.equal((await A.get('/api/transactions')).body.total, 0);
    assert.equal((await A.get('/api/categories')).body.items.length, 12);
  });
});
