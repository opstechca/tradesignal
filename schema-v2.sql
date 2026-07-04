-- ============================================================
-- v2: paid tiers + gated live access. Run AFTER schema.sql.
-- Free followers see signals delayed 30 min + all closed calls.
-- Paid followers + admin see signals live.
-- ============================================================

alter table profiles add column if not exists tier       text not null default 'free' check (tier in ('free','paid'));
alter table profiles add column if not exists paid_until  timestamptz;

-- is the current user a live/paid viewer (paid & not expired, or admin)?
create or replace function is_paid()
returns boolean language sql stable security definer as $$
  select exists(
    select 1 from profiles
    where id = auth.uid()
      and (role = 'admin' or (tier = 'paid' and (paid_until is null or paid_until > now())))
  );
$$;

-- Replace the open read policy with a gated one.
drop policy if exists s_read_all on signals;
create policy s_read_gated on signals for select using (
  status <> 'open'                                   -- closed calls always public (track record)
  or created_at < now() - interval '30 minutes'      -- free/anon get delayed access
  or is_paid()                                       -- paid + admin get it live
);

-- ============================================================
-- After Stripe is wired, a follower's tier is set by the
-- stripe-webhook edge function. To grant manually for testing:
--   update profiles set tier='paid', paid_until=now()+interval '30 days'
--   where id=(select id from auth.users where email='TESTER@EMAIL.COM');
-- ============================================================
