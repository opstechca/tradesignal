-- ============================================================
-- Stock Signals platform - Supabase schema
-- Paste this whole file into: Supabase dashboard -> SQL Editor -> Run
-- ============================================================

-- 1. PROFILES (one row per user, mirrors auth.users)
create table if not exists profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role         text not null default 'follower' check (role in ('follower','admin')),
  referral_code text unique,
  referred_by  text,
  created_at   timestamptz not null default now()
);

-- 2. SIGNALS (what the admin broadcasts)
create table if not exists signals (
  id         bigint generated always as identity primary key,
  symbol     text not null,
  side       text not null check (side in ('BUY','SELL')),
  entry      numeric not null,
  target     numeric,
  stoploss   numeric,
  note       text,
  status     text not null default 'open' check (status in ('open','hit_target','hit_sl','closed')),
  result_pct numeric,                      -- filled when closed, for the track record
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  closed_at  timestamptz
);
create index if not exists signals_created_idx on signals(created_at desc);

-- 3. FOLLOWS (a follower marks that they took a signal)
create table if not exists follows (
  id        bigint generated always as identity primary key,
  signal_id bigint not null references signals(id) on delete cascade,
  user_id   uuid   not null references auth.users(id) on delete cascade,
  taken_at  timestamptz not null default now(),
  unique (signal_id, user_id)
);

-- ============================================================
-- Auto-create a profile + referral code when someone signs up
-- ============================================================
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, display_name, referral_code, referred_by)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
    upper(substr(md5(new.id::text),1,7)),
    new.raw_user_meta_data->>'referred_by'
  );
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ============================================================
-- Row Level Security  (the rules that keep it safe)
-- ============================================================
alter table profiles enable row level security;
alter table signals  enable row level security;
alter table follows  enable row level security;

-- helper: is the current user an admin?
create or replace function is_admin()
returns boolean language sql stable security definer as $$
  select exists(select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

-- PROFILES: you can read/update only your own row
drop policy if exists p_read_own on profiles;
create policy p_read_own on profiles for select using (id = auth.uid() or is_admin());
drop policy if exists p_update_own on profiles;
create policy p_update_own on profiles for update using (id = auth.uid());

-- SIGNALS: anyone (even logged-out) can READ -> powers the public track record.
--          only an admin can insert / update.
drop policy if exists s_read_all on signals;
create policy s_read_all on signals for select using (true);
drop policy if exists s_write_admin on signals;
create policy s_write_admin on signals for insert with check (is_admin());
drop policy if exists s_update_admin on signals;
create policy s_update_admin on signals for update using (is_admin());

-- FOLLOWS: a follower manages only their own rows
drop policy if exists f_read_own on follows;
create policy f_read_own on follows for select using (user_id = auth.uid() or is_admin());
drop policy if exists f_insert_own on follows;
create policy f_insert_own on follows for insert with check (user_id = auth.uid());
drop policy if exists f_delete_own on follows;
create policy f_delete_own on follows for delete using (user_id = auth.uid());

-- ============================================================
-- AFTER RUNNING: make yourself the admin. Sign up in the app first,
-- then run (with your email):
--   update profiles set role='admin'
--   where id = (select id from auth.users where email='YOU@EMAIL.COM');
-- ============================================================
