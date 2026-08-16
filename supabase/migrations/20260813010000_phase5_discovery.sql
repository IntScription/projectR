-- Phase 5: discovery & feed.
--
-- Two views instead of new tables — discovery is a read-shape over data
-- that already exists (projects + their engagement, and the follow graph).
-- `security_invoker` makes each view respect the querying role's RLS rather
-- than the view owner's, matching Supabase's recommended pattern (moot here
-- since the underlying tables are public-read anyway, but it's the correct
-- default to reach for).

-- One view backs New / Trending / Categories / Search — same shape, just a
-- different ORDER BY or WHERE from the client. Owner info is flattened in
-- (rather than left for PostgREST embedding) because embedding relies on
-- introspecting a foreign key, and views don't carry one.
create view public.project_feed
with (security_invoker = true) as
select
  p.id,
  p.slug,
  p.name,
  p.description,
  p.category,
  p.status,
  p.created_at,
  p.owner_id,
  p.search_vector,
  owner.username as owner_username,
  owner.display_name as owner_display_name,
  owner.avatar_url as owner_avatar_url,
  coalesce(l.like_count, 0) as like_count,
  coalesce(c.comment_count, 0) as comment_count,
  -- Hacker-News-style decay: engagement divided by (age in hours + 2) ^ 1.5.
  -- Simple and legible on purpose — an ML ranking model is explicitly out
  -- of scope for the MVP.
  (
    (coalesce(l.like_count, 0) * 2 + coalesce(c.comment_count, 0) + p.view_count * 0.1)
    / power(extract(epoch from (now() - p.created_at)) / 3600 + 2, 1.5)
  ) as trending_score
from public.projects p
join public.profiles owner on owner.id = p.owner_id
left join (
  select project_id, count(*) as like_count
  from public.likes
  where project_id is not null
  group by project_id
) l on l.project_id = p.id
left join (
  select project_id, count(*) as comment_count
  from public.comments
  where project_id is not null
  group by project_id
) c on c.project_id = p.id;

grant select on public.project_feed to anon, authenticated;

-- Personalized: updates and new projects from whoever the caller follows
-- (directly, or via following the creator), merged into one reverse-chron
-- list. Depends on auth.uid(), so authenticated-only.
create view public.following_feed
with (security_invoker = true) as
select
  pu.id,
  'update'::text as item_type,
  p.id as project_id,
  p.slug as project_slug,
  p.name as project_name,
  p.owner_id,
  owner.username as owner_username,
  owner.display_name as owner_display_name,
  pu.body as text,
  pu.created_at
from public.project_updates pu
join public.projects p on p.id = pu.project_id
join public.profiles owner on owner.id = p.owner_id
where exists (
  select 1 from public.follows f
  where f.follower_id = auth.uid()
    and (f.followee_profile_id = p.owner_id or f.followee_project_id = p.id)
)
union all
select
  p.id,
  'new_project'::text as item_type,
  p.id as project_id,
  p.slug as project_slug,
  p.name as project_name,
  p.owner_id,
  owner.username as owner_username,
  owner.display_name as owner_display_name,
  coalesce(p.description, '') as text,
  p.created_at
from public.projects p
join public.profiles owner on owner.id = p.owner_id
where exists (
  select 1 from public.follows f
  where f.follower_id = auth.uid()
    and f.followee_profile_id = p.owner_id
);

grant select on public.following_feed to authenticated;
