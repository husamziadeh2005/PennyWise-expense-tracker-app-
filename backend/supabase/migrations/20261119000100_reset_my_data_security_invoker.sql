-- reset_my_data() now runs as the calling user (SECURITY INVOKER), so Row
-- Level Security protects it like every other query. The default category
-- list lives in one place: public.default_categories().

create or replace function public.default_categories()
returns table (name text, type text, icon text, color text)
language sql immutable set search_path = '' as $$
  values
    ('Food & Dining',     'expense', 'restaurant',     '#E57373'),
    ('Transport',         'expense', 'directions_car', '#64B5F6'),
    ('Shopping',          'expense', 'shopping_bag',   '#BA68C8'),
    ('Bills & Utilities', 'expense', 'receipt',        '#FFB74D'),
    ('Entertainment',     'expense', 'movie',          '#F06292'),
    ('Health',            'expense', 'health',         '#4DB6AC'),
    ('Education',         'expense', 'school',         '#7986CB'),
    ('Other',             'expense', 'category',       '#90A4AE'),
    ('Salary',            'income',  'payments',       '#66BB6A'),
    ('Freelance',         'income',  'work',           '#26A69A'),
    ('Gifts',             'income',  'gift',           '#AB47BC'),
    ('Other Income',      'income',  'savings',        '#8D6E63')
$$;
revoke execute on function public.default_categories() from public, anon;
grant execute on function public.default_categories() to authenticated;

create or replace function public.seed_default_categories(uid uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.categories (user_id, name, type, icon, color)
  select uid, d.name, d.type, d.icon, d.color from public.default_categories() d
  on conflict do nothing;
end $$;
revoke execute on function public.seed_default_categories(uuid) from public, anon, authenticated;

drop function public.reset_my_data();
create function public.reset_my_data()
returns setof text language plpgsql security invoker set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  return query
    with removed as (
      delete from public.transactions where user_id = uid returning receipt_path
    )
    select r.receipt_path from removed r where r.receipt_path is not null;
  delete from public.budgets    where user_id = uid;
  delete from public.categories where user_id = uid;
  -- user_id is filled by its default (auth.uid())
  insert into public.categories (name, type, icon, color)
  select d.name, d.type, d.icon, d.color from public.default_categories() d;
end $$;
revoke execute on function public.reset_my_data() from public, anon;
grant  execute on function public.reset_my_data() to authenticated;
