-- ============================================================
-- v3: public leaderboard. Run after schema.sql.
-- Aggregates each follower's taken+closed calls into win rate and
-- total return %. security definer so it reads across follows/profiles
-- past RLS, but returns only display_name + aggregates (no ids, no emails).
-- ============================================================
create or replace function leaderboard()
returns table(display_name text, calls_taken bigint, wins bigint, total_pct numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(p.display_name, 'anon')            as display_name,
         count(*)                                    as calls_taken,
         count(*) filter (where s.result_pct >= 0)   as wins,
         round(sum(s.result_pct)::numeric, 2)        as total_pct
  from follows f
  join signals  s on s.id = f.signal_id
  join profiles p on p.id = f.user_id
  where s.result_pct is not null
  group by p.id, p.display_name
  order by total_pct desc nulls last
  limit 20;
$$;

grant execute on function leaderboard() to anon, authenticated;
