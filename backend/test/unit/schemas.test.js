import { test } from 'node:test';
import assert from 'node:assert/strict';
import { transactionSchemas, categorySchemas, profileSchemas, budgetSchemas } from '../../src/schemas/index.js';

const ok = (schema, value) => {
  const r = schema.safeParse(value);
  assert.ok(r.success, JSON.stringify(r.error?.issues));
  return r.data;
};
const bad = (schema, value) => assert.equal(schema.safeParse(value).success, false, JSON.stringify(value));

test('amounts', () => {
  const t = transactionSchemas.create;
  assert.equal(ok(t, { type: 'expense', amount: '12.50' }).amount, 12.5);
  assert.equal(ok(t, { type: 'expense', amount: 7 }).amount, 7);
  for (const amount of [0, -5, '0.00', 1.234, 'abc', '1e5', 99999999999, null, '']) {
    bad(t, { type: 'expense', amount });
  }
});

test('transaction create: defaults, trimming, unknown fields dropped', () => {
  const v = ok(transactionSchemas.create, {
    type: 'income', amount: 5, note: '   ', user_id: 'hacker', id: 'x',
  });
  assert.equal(v.note, null);
  assert.equal(v.categoryId, null);
  assert.equal('user_id' in v, false);
  assert.equal('id' in v, false);
  bad(transactionSchemas.create, { type: 'gift', amount: 5 });
  bad(transactionSchemas.create, { type: 'income', amount: 5, occurredOn: '2026-02-30' });
  bad(transactionSchemas.create, { type: 'income', amount: 5, categoryId: 'not-a-uuid' });
  bad(transactionSchemas.create, { type: 'income', amount: 5, note: 'x'.repeat(501) });
});

test('transaction update needs at least one field', () => {
  bad(transactionSchemas.update, {});
  ok(transactionSchemas.update, { note: null });
  ok(transactionSchemas.update, { categoryId: null });
});

test('list query: coercion, limits and date order', () => {
  const v = ok(transactionSchemas.list, { limit: '20', offset: '40' });
  assert.equal(v.limit, 20);
  assert.equal(v.offset, 40);
  assert.equal(ok(transactionSchemas.list, {}).limit, 50);
  bad(transactionSchemas.list, { limit: '1000' });
  bad(transactionSchemas.list, { from: '2026-12-01', to: '2026-11-01' });
  ok(transactionSchemas.list, { categoryId: 'none' });
});

test('categories and profile', () => {
  assert.equal(ok(categorySchemas.create, { name: '  Coffee ', type: 'expense' }).name, 'Coffee');
  bad(categorySchemas.create, { name: '', type: 'expense' });
  bad(categorySchemas.create, { name: 'x', type: 'expense', color: 'red' });
  const upd = ok(categorySchemas.update, { name: 'New', type: 'income' });
  assert.equal('type' in upd, false); // type is never editable
  assert.equal(ok(profileSchemas.update, { currency: 'jod' }).currency, 'JOD');
  bad(profileSchemas.update, { gender: 'Other' });
  bad(profileSchemas.update, {});
  assert.equal(ok(budgetSchemas.create, { amount: 100 }).categoryId, null);
});
