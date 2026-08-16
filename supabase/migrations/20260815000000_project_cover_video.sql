-- Projects can now carry an optional cover video alongside (or instead
-- of) a cover image — Home/Discover feed cards autoplay it muted when
-- present, same media slot `project-media` storage already serves images
-- from, no new bucket needed.
alter table public.projects add column cover_video_url text;

create or replace view public.project_feed
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
  (
    (coalesce(l.like_count, 0) * 2 + coalesce(c.comment_count, 0) + p.view_count * 0.1)
    / power(extract(epoch from (now() - p.created_at)) / 3600 + 2, 1.5)
  ) as trending_score,
  p.cover_image_url,
  exists(
    select 1 from public.likes lk where lk.project_id = p.id and lk.user_id = auth.uid()
  ) as is_liked_by_me,
  p.cover_video_url
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
) c on c.project_id = p.id
where not public.is_blocked(p.owner_id);

grant select on public.project_feed to anon, authenticated;
