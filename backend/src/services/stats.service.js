import { unwrap } from '../lib/errors.js';
import { datesOfMonth, daysInMonth, monthRange, shiftMonth, toIsoDate } from '../lib/dates.js';
import { fromCents, percent, toCents } from '../lib/money.js';

/**
 * Dashboard statistics — deliberately simple math:
 *
 *   balance        = income - expense
 *   savings rate   = (income - expense) / income * 100
 *   change vs last = (this month - last month) / last month * 100
 *   daily average  = expense / days counted so far this month
 *   category share = category expense / total expense * 100
 *   budget used    = spent / budget * 100
 *
 * buildMonthlySummary() is a pure function (no database), which makes it
 * easy to unit test; getMonthlySummary() loads the data and calls it.
 */

const PAGE = 1000; // Supabase returns at most 1000 rows per request

/** Loads every row of a query, 1000 at a time. */
async function fetchAll(makeQuery) {
  const rows = [];
  for (let from = 0; ; from += PAGE) {
    const page = await unwrap(makeQuery().range(from, from + PAGE - 1));
    rows.push(...page);
    if (page.length < PAGE) return rows;
  }
}

async function totals(supabase, from, to) {
  const [row] = await unwrap(supabase.rpc('my_totals', { p_from: from ?? null, p_to: to ?? null }));
  return {
    income: Number(row?.income ?? 0),
    expense: Number(row?.expense ?? 0),
    count: Number(row?.transaction_count ?? 0),
  };
}

export async function getMonthlySummary(supabase, { month, today }) {
  const todayIso = today ?? toIsoDate(new Date());
  const targetMonth = month ?? todayIso.slice(0, 7);
  const { start, end } = monthRange(targetMonth);
  const previous = monthRange(shiftMonth(targetMonth, -1));

  // The four queries are independent, so run them at the same time.
  const [transactions, budgets, previousTotals, allTime] = await Promise.all([
    fetchAll(() =>
      supabase
        .from('transactions')
        .select('id, type, amount, note, occurred_on, category:categories(id, name, icon, color)')
        .gte('occurred_on', start)
        .lte('occurred_on', end)
        .order('id'),
    ),
    unwrap(supabase.from('budgets').select('id, category_id, amount, category:categories(id, name, icon, color)')),
    totals(supabase, previous.start, previous.end),
    totals(supabase),
  ]);

  return buildMonthlySummary({ month: targetMonth, today: todayIso, transactions, budgets, previousTotals, allTime });
}

const UNCATEGORIZED = { id: null, name: 'Uncategorized', icon: 'category', color: '#9E9E9E' };

function groupByCategory(rows) {
  const groups = new Map();
  let totalCents = 0;
  for (const t of rows) {
    const cat = t.category ?? UNCATEGORIZED;
    const key = cat.id ?? 'none';
    const g = groups.get(key) ?? { category: cat, cents: 0, count: 0 };
    g.cents += toCents(t.amount);
    g.count += 1;
    groups.set(key, g);
    totalCents += toCents(t.amount);
  }
  return [...groups.values()]
    .sort((a, b) => b.cents - a.cents)
    .map((g) => ({
      categoryId: g.category.id,
      name: g.category.name,
      icon: g.category.icon,
      color: g.category.color,
      total: fromCents(g.cents),
      count: g.count,
      percent: percent(g.cents, totalCents) ?? 0,
    }));
}

/** How many days of the month have passed (for the daily average). */
function daysCounted(month, today) {
  const currentMonth = today.slice(0, 7);
  if (month > currentMonth) return 0; // future month
  if (month < currentMonth) return daysInMonth(month); // finished month
  return Number(today.slice(8, 10)); // this month: up to today
}

export function buildMonthlySummary({ month, today, transactions, budgets = [], previousTotals, allTime }) {
  const income = transactions.filter((t) => t.type === 'income');
  const expenses = transactions.filter((t) => t.type === 'expense');
  const sumCents = (rows) => rows.reduce((s, t) => s + toCents(t.amount), 0);

  const incomeCents = sumCents(income);
  const expenseCents = sumCents(expenses);
  const balanceCents = incomeCents - expenseCents;

  // ---- per day
  const daily = new Map(datesOfMonth(month).map((d) => [d, { income: 0, expense: 0 }]));
  for (const t of transactions) {
    const day = daily.get(t.occurred_on);
    if (day) day[t.type] += toCents(t.amount);
  }

  // ---- per category
  const expenseByCategory = groupByCategory(expenses);
  const incomeByCategory = groupByCategory(income);

  // ---- averages
  const days = daysCounted(month, today);

  // ---- biggest single expense
  const largest = expenses.reduce((max, t) => (!max || toCents(t.amount) > toCents(max.amount) ? t : max), null);

  // ---- budgets: spent vs limit
  const spentByCategory = new Map(expenseByCategory.map((c) => [c.categoryId, toCents(c.total)]));
  const budgetRows = budgets.map((b) => {
    const limitCents = toCents(b.amount);
    const spentCents = b.category_id ? (spentByCategory.get(b.category_id) ?? 0) : expenseCents;
    const used = percent(spentCents, limitCents) ?? 0;
    return {
      id: b.id,
      categoryId: b.category_id,
      name: b.category_id ? (b.category?.name ?? 'Category') : 'Overall',
      icon: b.category?.icon ?? 'wallet',
      color: b.category?.color ?? '#14213D',
      limit: fromCents(limitCents),
      spent: fromCents(spentCents),
      remaining: fromCents(limitCents - spentCents),
      percent: used,
      status: used >= 100 ? 'over' : used >= 80 ? 'warning' : 'ok',
    };
  });
  // overall budget first, then the most used ones
  budgetRows.sort((a, b) => (a.categoryId === null ? -1 : b.categoryId === null ? 1 : b.percent - a.percent));

  const prevIncome = toCents(previousTotals?.income ?? 0);
  const prevExpense = toCents(previousTotals?.expense ?? 0);
  const changePct = (now, before) => (before ? percent(now - before, before) : null);

  return {
    month,
    totals: {
      income: fromCents(incomeCents),
      expense: fromCents(expenseCents),
      balance: fromCents(balanceCents),
      transactionCount: transactions.length,
      savingsRate: percent(balanceCents, incomeCents),
    },
    previousMonth: {
      month: shiftMonth(month, -1),
      income: fromCents(prevIncome),
      expense: fromCents(prevExpense),
      incomeChangePercent: changePct(incomeCents, prevIncome),
      expenseChangePercent: changePct(expenseCents, prevExpense),
    },
    averages: {
      daysCounted: days,
      dailyExpense: days ? fromCents(Math.round(expenseCents / days)) : null,
    },
    topCategory: expenseByCategory[0] ?? null,
    largestExpense: largest && {
      id: largest.id,
      amount: Number(largest.amount),
      note: largest.note,
      occurredOn: largest.occurred_on,
      categoryName: largest.category?.name ?? UNCATEGORIZED.name,
    },
    expenseByCategory,
    incomeByCategory,
    daily: [...daily].map(([date, v]) => ({ date, income: fromCents(v.income), expense: fromCents(v.expense) })),
    budgets: budgetRows,
    allTime: {
      income: Number(allTime?.income ?? 0),
      expense: Number(allTime?.expense ?? 0),
      balance: fromCents(toCents(allTime?.income ?? 0) - toCents(allTime?.expense ?? 0)),
    },
  };
}
