-- =====================================================================
-- PennyWise – core expense-tracker schema
--
--   categories   : user-owned income / expense categories
--   transactions : every income or expense entry
--   budgets      : monthly spending limit (overall or per category)
--
-- Security model
--   * Row Level Security on every table: a user only ever sees / changes
--     rows where user_id = auth.uid().
--   * Column-level grants: clients can never write user_id, id or
--     timestamps; user_id is always filled from the JWT (auth.uid()).
--   * The Node.js API forwards the user's JWT, so these rules apply to
--     the API exactly like they would to the app.
-- =====================================================================

-- ------------------------------------------------------------ categories
create table public.categories (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  type        text not null check (type in ('income', 'expense')),
  icon        text not null default 'category' check (char_length(icon) between 1 and 40),
  color       text not null default '#607D8B' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- lets other tables reference (id, user_id) so a row can only point to
  -- a category owned by the same user
  unique (id, user_id)
);

-- no two categories with the same name (case-insensitive) and type per user
create unique index categories_user_type_name_key
  on public.categories (user_id, type, lower(btrim(name)));

-- ---------------------------------------------------------- transactions
create table public.transactions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type          text not null check (type in ('income', 'expense')),
  amount        numeric(12, 2) not null check (amount > 0 and amount <= 9999999999.99),
  category_id   uuid,
  note          text check (note is null or char_length(note) <= 500),
  occurred_on   date not null default current_date,
  receipt_path  text check (receipt_path is null or char_length(receipt_path) <= 300),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  -- category must belong to the same user; deleting a category keeps the
  -- transaction and just clears its category
  foreign key (category_id, user_id)
    references public.categories (id, user_id) on delete set null (category_id)
);

create index transactions_user_date_idx on public.transactions (user_id, occurred_on desc, created_at desc);
create index transactions_category_idx  on public.transactions (category_id);

-- --------------------------------------------------------------- budgets
create table public.budgets (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  category_id  uuid,                -- null = overall monthly budget
  amount       numeric(12, 2) not null check (amount > 0 and amount <= 9999999999.99),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  foreign key (category_id, user_id)
    references public.categories (id, user_id) on delete cascade,
  -- one overall budget + one budget per category
  unique nulls not distinct (user_id, category_id)
);

create index budgets_category_idx on public.budgets (category_id);

-- ----------------------------------------------------- integrity triggers

-- A transaction's category must have the same type (an "income" entry can
-- not be filed under "Food"), and a receipt must live in the owner's folder.
create or replace function public.validate_transaction()
returns trigger language plpgsql set search_path = '' as $$
declare v_type text;
begin
  if new.category_id is not null then
    select c.type into v_type from public.categories c
     where c.id = new.category_id and c.user_id = new.user_id;
    if v_type is distinct from new.type then
      raise exception 'Category type does not match transaction type'
        using errcode = '23514', hint = 'category_type_mismatch';
    end if;
  end if;
  if new.receipt_path is not null and new.receipt_path not like new.user_id::text || '/%' then
    raise exception 'Invalid receipt path'
      using errcode = '23514', hint = 'invalid_receipt_path';
  end if;
  return new;
end $$;

create trigger transactions_validate
  before insert or update on public.transactions
  for each row execute function public.validate_transaction();

-- Budgets are for spending, so only expense categories are allowed.
create or replace function public.validate_budget()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.category_id is not null and not exists (
    select 1 from public.categories c
     where c.id = new.category_id and c.user_id = new.user_id and c.type = 'expense'
  ) then
    raise exception 'Budgets can only be set for expense categories'
      using errcode = '23514', hint = 'budget_category_not_expense';
  end if;
  return new;
end $$;

create trigger budgets_validate
  before insert or update on public.budgets
  for each row execute function public.validate_budget();

create trigger categories_set_updated_at   before update on public.categories
  for each row execute function public.set_updated_at();
create trigger transactions_set_updated_at before update on public.transactions
  for each row execute function public.set_updated_at();
create trigger budgets_set_updated_at      before update on public.budgets
  for each row execute function public.set_updated_at();

-- ------------------------------------------------------ Row Level Security
alter table public.categories   enable row level security;
alter table public.transactions enable row level security;
alter table public.budgets      enable row level security;

create policy "Own categories: select" on public.categories for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Own categories: insert" on public.categories for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Own categories: update" on public.categories for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own categories: delete" on public.categories for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "Own transactions: select" on public.transactions for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Own transactions: insert" on public.transactions for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Own transactions: update" on public.transactions for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own transactions: delete" on public.transactions for delete to authenticated
  using ((select auth.uid()) = user_id);

create policy "Own budgets: select" on public.budgets for select to authenticated
  using ((select auth.uid()) = user_id);
create policy "Own budgets: insert" on public.budgets for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Own budgets: update" on public.budgets for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Own budgets: delete" on public.budgets for delete to authenticated
  using ((select auth.uid()) = user_id);

-- ------------------------------------------------------------- privileges
revoke all on public.categories, public.transactions, public.budgets from anon, authenticated;

grant select, delete on public.categories, public.transactions, public.budgets to authenticated;

-- a category's type is fixed after creation (existing transactions depend on it)
grant insert (name, type, icon, color) on public.categories to authenticated;
grant update (name, icon, color)       on public.categories to authenticated;

grant insert (type, amount, category_id, note, occurred_on, receipt_path) on public.transactions to authenticated;
grant update (type, amount, category_id, note, occurred_on, receipt_path) on public.transactions to authenticated;

grant insert (category_id, amount) on public.budgets to authenticated;
grant update (amount)              on public.budgets to authenticated;

-- ------------------------------------------------- default categories seed
create or replace function public.seed_default_categories(uid uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.categories (user_id, name, type, icon, color) values
    (uid, 'Food & Dining',     'expense', 'restaurant',     '#E57373'),
    (uid, 'Transport',         'expense', 'directions_car', '#64B5F6'),
    (uid, 'Shopping',          'expense', 'shopping_bag',   '#BA68C8'),
    (uid, 'Bills & Utilities', 'expense', 'receipt',        '#FFB74D'),
    (uid, 'Entertainment',     'expense', 'movie',          '#F06292'),
    (uid, 'Health',            'expense', 'health',         '#4DB6AC'),
    (uid, 'Education',         'expense', 'school',         '#7986CB'),
    (uid, 'Other',             'expense', 'category',       '#90A4AE'),
    (uid, 'Salary',            'income',  'payments',       '#66BB6A'),
    (uid, 'Freelance',         'income',  'work',           '#26A69A'),
    (uid, 'Gifts',             'income',  'gift',           '#AB47BC'),
    (uid, 'Other Income',      'income',  'savings',        '#8D6E63')
  on conflict do nothing;
end $$;

-- internal helper only: never callable from the API
revoke execute on function public.seed_default_categories(uuid) from public, anon, authenticated;

create or replace function public.handle_new_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform public.seed_default_categories(new.id);
  return new;
end $$;
revoke execute on function public.handle_new_profile() from public, anon, authenticated;

create trigger on_profile_created_seed_categories
  after insert on public.profiles
  for each row execute function public.handle_new_profile();

-- existing users get the defaults too
select public.seed_default_categories(p.id) from public.profiles p;

-- --------------------------------------------- orchestration functions (RPC)

-- Deletes a category in ONE database transaction. If p_reassign_to is
-- given, its transactions are moved there first; otherwise they become
-- "uncategorised". Returns how many transactions were affected.
-- SECURITY INVOKER (default): RLS still applies, users can only touch
-- their own rows.
create or replace function public.delete_category(p_category_id uuid, p_reassign_to uuid default null)
returns integer language plpgsql set search_path = '' as $$
declare
  v_type   text;
  v_target text;
  v_count  integer := 0;
begin
  select type into v_type from public.categories
   where id = p_category_id and user_id = auth.uid();
  if v_type is null then
    raise exception 'Category not found' using errcode = 'P0002', hint = 'category_not_found';
  end if;

  if p_reassign_to is not null then
    if p_reassign_to = p_category_id then
      raise exception 'Cannot move transactions to the same category'
        using errcode = '22023', hint = 'same_category';
    end if;
    select type into v_target from public.categories
     where id = p_reassign_to and user_id = auth.uid();
    if v_target is null then
      raise exception 'Target category not found' using errcode = 'P0002', hint = 'target_not_found';
    end if;
    if v_target <> v_type then
      raise exception 'Target category has a different type'
        using errcode = '23514', hint = 'category_type_mismatch';
    end if;
    update public.transactions set category_id = p_reassign_to
     where category_id = p_category_id and user_id = auth.uid();
    get diagnostics v_count = row_count;
  else
    select count(*) into v_count from public.transactions
     where category_id = p_category_id and user_id = auth.uid();
  end if;

  delete from public.categories where id = p_category_id and user_id = auth.uid();
  return v_count;
end $$;

revoke execute on function public.delete_category(uuid, uuid) from public, anon;
grant  execute on function public.delete_category(uuid, uuid) to authenticated;

-- Wipes the caller's transactions, budgets and categories and restores the
-- default categories, all in one transaction. Returns the receipt paths
-- that were attached so the API can remove the files from Storage.
create or replace function public.reset_my_data()
returns setof text language plpgsql security definer set search_path = '' as $$
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
  delete from public.budgets      where user_id = uid;
  delete from public.categories   where user_id = uid;
  perform public.seed_default_categories(uid);
end $$;

revoke execute on function public.reset_my_data() from public, anon;
grant  execute on function public.reset_my_data() to authenticated;

-- ----------------------------------------------------------------- Storage
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('receipts', 'receipts', false, 5242880,
     array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']),
  ('avatars',  'avatars',  true,  2097152,
     array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- files are stored as "<user id>/<file name>"; users only reach their folder
create policy "Own receipts: select" on storage.objects for select to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own receipts: insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own receipts: update" on storage.objects for update to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own receipts: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'receipts' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "Own avatars: select" on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own avatars: insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own avatars: update" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Own avatars: delete" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------- Realtime
-- the app listens for changes so every open device refreshes instantly
alter publication supabase_realtime add table public.transactions, public.categories, public.budgets;
