-- Feed cards (Home, Discover) currently show like/comment counts as static
-- text, not the real interactive LikeButton — so tapping a heart in a
-- feed does nothing but navigate into the project instead of actually
-- liking it. Fixing that in the client means every visible card needs to
-- know "did I like this" — baking `is_liked_by_me` into project_feed
-- itself (one correlated subquery per row, cheap/indexed) means the whole
-- feed's like state comes back in the single feed fetch, instead of each
-- card firing its own extra query on appear.
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
  ) as is_liked_by_me
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
