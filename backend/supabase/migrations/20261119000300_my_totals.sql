-- Income / expense totals for the signed-in user, optionally limited to a
-- date range. Used for "all-time balance" and "last month" on the dashboard,
-- so the API never has to download every transaction just to add them up.
-- SECURITY INVOKER + RLS: a user can only ever sum their own rows.
create or replace function public.my_totals(p_from date default null, p_to date default null)
returns table (income numeric, expense numeric, transaction_count bigint)
language sql stable security invoker set search_path = '' as $$
  select
    coalesce(sum(t.amount) filter (where t.type = 'income'), 0)  as income,
    coalesce(sum(t.amount) filter (where t.type = 'expense'), 0) as expense,
    count(*)                                                      as transaction_count
  from public.transactions t
  where t.user_id = (select auth.uid())
    and (p_from is null or t.occurred_on >= p_from)
    and (p_to   is null or t.occurred_on <= p_to);
$$;
revoke execute on function public.my_totals(date, date) from public, anon;
grant  execute on function public.my_totals(date, date) to authenticated;
