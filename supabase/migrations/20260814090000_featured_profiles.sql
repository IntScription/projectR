-- A brand-new install can easily have exactly one real profile (the
-- developer's own) — without a guarantee, `suggested_profiles` naturally
-- surfaces that profile purely because there's nothing else to rank, which
-- is fragile: it stops holding the moment there are enough other users
-- that normal scoring pushes it out. `is_featured` makes the guarantee
-- explicit and generic (not hardcoded to one profile id, reusable for
-- anyone worth always surfacing) rather than relying on that coincidence.
--
-- Featured profiles are mixed in, not pinned — the ranked/popularity
-- ordering still decides who else appears, but the final result is
-- shuffled before returning, so a featured profile has no fixed position.
alter table public.profiles add column is_featured boolean not null default false;

create or replace function public.suggested_profiles(limit_count int default 10)
returns setof public.profiles
language sql
security invoker
stable
as $$
  with my_follows as (
    select followee_profile_id as id
    from public.follows
    where follower_id = auth.uid() and followee_profile_id is not null
  ),
  scored as (
    select f2.followee_profile_id as id, count(*) as score
    from public.follows f2
    where f2.follower_id in (select id from my_follows)
      and f2.followee_profile_id is not null
      and f2.followee_profile_id <> auth.uid()
      and f2.followee_profile_id not in (select id from my_follows)
    group by f2.followee_profile_id
  ),
  popularity as (
    select followee_profile_id as id, count(*) as follower_count
    from public.follows
    where followee_profile_id is not null
    group by followee_profile_id
  ),
  eligible as (
    select
      pr.id, pr.is_featured, pr.created_at,
      coalesce(s.score, 0) as score,
      coalesce(pop.follower_count, 0) as follower_count
    from public.profiles pr
    left join scored s on s.id = pr.id
    left join popularity pop on pop.id = pr.id
    where pr.id <> auth.uid()
      and pr.id not in (select id from my_follows)
      and not public.is_blocked(pr.id)
  ),
  featured_ids as (
    select id from eligible where is_featured
  ),
  ranked_rest_ids as (
    select id from eligible
    where not is_featured
    order by score desc, follower_count desc, created_at desc
    limit greatest(limit_count - (select count(*) from featured_ids), 0)
  ),
  combined_ids as (
    select id from featured_ids
    union
    select id from ranked_rest_ids
  )
  select pr.*
  from public.profiles pr
  join combined_ids c on c.id = pr.id
  order by random()
  limit limit_count;
$$;

grant execute on function public.suggested_profiles(int) to authenticated;
