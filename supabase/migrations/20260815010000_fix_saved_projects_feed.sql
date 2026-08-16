-- Real bug: this view explicitly listed project_feed's columns instead of
-- `pf.*`, so when is_liked_by_me and cover_video_url were added to
-- project_feed later, this view didn't pick them up — every row was
-- missing those keys, DiscoverProject's Decodable synthesis has no way to
-- fall back to a Swift-side default for a *missing* JSON key on a
-- non-Optional property, so decoding threw, `try?` swallowed it, and the
-- Saved tab silently showed empty no matter what was actually saved.
-- `pf.*` fixes this permanently — any future project_feed column shows up
-- here automatically, no more manual sync needed.
-- Column set/order changed (pf.* now includes columns added after this
-- view was first created), so this needs a real drop, not `create or
-- replace` (which forbids reordering/renaming existing columns). Nothing
-- else references this view by name.
drop view if exists public.saved_projects_feed;

create view public.saved_projects_feed
with (security_invoker = true) as
select pf.*, s.user_id as saved_by, s.created_at as saved_at
from public.saves s
join public.project_feed pf on pf.id = s.project_id;

grant select on public.saved_projects_feed to authenticated;
