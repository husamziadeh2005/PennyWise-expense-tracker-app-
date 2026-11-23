import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildMonthlySummary } from '../../src/services/stats.service.js';

const food = { id: 'c-food', name: 'Food', icon: 'restaurant', color: '#E57373' };
const fun = { id: 'c-fun', name: 'Fun', icon: 'movie', color: '#F06292' };
const salary = { id: 'c-sal', name: 'Salary', icon: 'payments', color: '#66BB6A' };

const tx = (id, type, amount, occurred_on, category = null, note = null) =>
  ({ id, type, amount, occurred_on, category, note });

const base = {
  month: '2026-11',
  today: '2026-11-10',
  transactions: [
    tx('1', 'income', 1000, '2026-11-01', salary),
    tx('2', 'expense', 0.1, '2026-11-02', food),
    tx('3', 'expense', 0.2, '2026-11-02', food),
    tx('4', 'expense', 99.7, '2026-11-05', fun, 'Concert'),
    tx('5', 'expense', 50, '2026-11-09'),
  ],
  budgets: [
    { id: 'b-all', category_id: null, amount: 200 },
    { id: 'b-food', category_id: 'c-food', amount: 0.25, category: food },
  ],
  previousTotals: { income: 800, expense: 300 },
  allTime: { income: 5000.1, expense: 1200.2 },
};

test('totals use exact cents (no 0.1 + 0.2 floating point error)', () => {
  const s = buildMonthlySummary(base);
  assert.equal(s.totals.income, 1000);
  assert.equal(s.totals.expense, 150); // 0.1 + 0.2 + 99.7 + 50
  assert.equal(s.totals.balance, 850);
  assert.equal(s.totals.transactionCount, 5);
  assert.equal(s.totals.savingsRate, 85);
  assert.equal(s.allTime.balance, 3799.9);
});

test('expense by category is sorted, includes Uncategorized, percents add up', () => {
  const s = buildMonthlySummary(base);
  assert.deepEqual(s.expenseByCategory.map((c) => [c.name, c.total, c.percent]), [
    ['Fun', 99.7, 66.5],
    ['Uncategorized', 50, 33.3],
    ['Food', 0.3, 0.2],
  ]);
  assert.equal(s.topCategory.name, 'Fun');
  assert.equal(s.incomeByCategory[0].percent, 100);
});

test('daily series covers every day of the month', () => {
  const s = buildMonthlySummary(base);
  assert.equal(s.daily.length, 30);
  assert.deepEqual(s.daily[1], { date: '2026-11-02', income: 0, expense: 0.3 });
});

test('daily average counts only days elapsed in the current month', () => {
  assert.equal(buildMonthlySummary(base).averages.dailyExpense, 15); // 150 / 10 days
  const past = buildMonthlySummary({ ...base, today: '2026-12-15' });
  assert.equal(past.averages.daysCounted, 30);
  assert.equal(past.averages.dailyExpense, 5);
  const future = buildMonthlySummary({ ...base, today: '2026-10-01' });
  assert.equal(future.averages.dailyExpense, null);
});

test('change vs previous month, null when last month was empty', () => {
  const s = buildMonthlySummary(base);
  assert.equal(s.previousMonth.month, '2026-10');
  assert.equal(s.previousMonth.expenseChangePercent, -50); // 150 vs 300
  assert.equal(s.previousMonth.incomeChangePercent, 25); // 1000 vs 800
  const empty = buildMonthlySummary({ ...base, previousTotals: { income: 0, expense: 0 } });
  assert.equal(empty.previousMonth.expenseChangePercent, null);
});

test('budgets: overall first, spent/remaining/status calculated', () => {
  const s = buildMonthlySummary(base);
  assert.deepEqual(s.budgets.map((b) => [b.name, b.spent, b.remaining, b.percent, b.status]), [
    ['Overall', 150, 50, 75, 'ok'],
    ['Food', 0.3, -0.05, 120, 'over'],
  ]);
});

test('largest expense', () => {
  const s = buildMonthlySummary(base);
  assert.equal(s.largestExpense.amount, 99.7);
  assert.equal(s.largestExpense.categoryName, 'Fun');
});

test('empty month', () => {
  const s = buildMonthlySummary({ ...base, transactions: [], budgets: [] });
  assert.equal(s.totals.balance, 0);
  assert.equal(s.totals.savingsRate, null);
  assert.equal(s.topCategory, null);
  assert.equal(s.largestExpense, null);
  assert.deepEqual(s.expenseByCategory, []);
});

test('February in a leap year has 29 days', () => {
  const s = buildMonthlySummary({ ...base, month: '2028-02', today: '2028-03-01', transactions: [] });
  assert.equal(s.daily.length, 29);
  assert.equal(s.previousMonth.month, '2028-01');
});
