-- Lightweight, SQL-only recommendations — no ML infra needed at this
-- scale. Two heuristics:
--   1. suggested_profiles: "people followed by people you follow" (2-hop
--      graph), falling back to overall follower-count popularity so a
--      brand-new account with zero follows still gets a non-empty list.
--   2. similar_projects_to_profile: other users' projects sharing a
--      category or tag with the target profile's own projects, surfaced
--      on a profile page as "you might also like" to keep the discovery
--      loop going past a single profile visit.
-- Both are `security invoker` SQL functions rather than views, since they
-- need a parameter (the calling user, or the profile being viewed) that a
-- plain view can't take — but they still run under the caller's RLS via
-- security invoker, same as project_feed.

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
  )
  select pr.*
  from public.profiles pr
  left join scored s on s.id = pr.id
  left join popularity pop on pop.id = pr.id
  where pr.id <> auth.uid()
    and pr.id not in (select id from my_follows)
  order by coalesce(s.score, 0) desc, coalesce(pop.follower_count, 0) desc, pr.created_at desc
  limit limit_count;
$$;

grant execute on function public.suggested_profiles(int) to authenticated;

create or replace function public.similar_projects_to_profile(
  target_profile_id uuid, limit_count int default 6
)
returns setof public.project_feed
language sql
security invoker
stable
as $$
  with target_categories as (
    select distinct category from public.projects where owner_id = target_profile_id
  ),
  target_tags as (
    select coalesce(array_agg(distinct tag), array[]::text[]) as tags
    from public.projects p, unnest(p.tags) as tag
    where p.owner_id = target_profile_id
  )
  select pf.*
  from public.project_feed pf
  join public.projects p on p.id = pf.id
  where pf.owner_id <> target_profile_id
    and (
      pf.category in (select category from target_categories)
      or p.tags && (select tags from target_tags)
    )
  order by pf.trending_score desc
  limit limit_count;
$$;

grant execute on function public.similar_projects_to_profile(uuid, int) to anon, authenticated;
