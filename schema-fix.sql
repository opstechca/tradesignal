-- ============================================================
-- FIX: "Database error saving new user" on signup.
-- Cause: the signup trigger runs as supabase_auth_admin, whose
-- search_path does not include public, so unqualified table names
-- (profiles) are not found. Pin search_path + fully qualify.
-- Run this whole file once in the SQL Editor.
-- ============================================================

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, referral_code, referred_by)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email,'@',1)),
    upper(substr(md5(new.id::text),1,7)),
    new.raw_user_meta_data->>'referred_by'
  );
  return new;
end $$;

-- same hardening for the RLS helpers (harmless if already fine)
create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$ select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin'); $$;

create or replace function public.is_paid()
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid()
      and (role = 'admin' or (tier = 'paid' and (paid_until is null or paid_until > now())))
  );
$$;
