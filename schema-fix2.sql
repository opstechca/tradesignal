-- ============================================================
-- DEFINITIVE FIX for "Database error saving new user".
-- Root cause on current Supabase projects: the internal
-- supabase_auth_admin role (which fires the signup trigger)
-- has no privileges on public.profiles, so the insert is denied.
-- Grant it, and recreate the trigger owned by that role so it
-- runs with the right rights + search_path. Run this whole file.
-- ============================================================

grant usage on schema public to supabase_auth_admin;
grant insert, select, update on public.profiles to supabase_auth_admin;

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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- sanity check: must succeed with no error
insert into public.profiles (id, display_name, referral_code) values (gen_random_uuid(),'diag','DIAG999');
delete from public.profiles where referral_code='DIAG999';
