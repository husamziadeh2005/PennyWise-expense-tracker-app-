-- Indexes that cover the composite (category_id, user_id) foreign keys, so
-- deleting a category never has to scan the whole table.
drop index if exists public.transactions_category_idx;
drop index if exists public.budgets_category_idx;
create index transactions_category_user_idx on public.transactions (category_id, user_id);
create index budgets_category_user_idx on public.budgets (category_id, user_id);
