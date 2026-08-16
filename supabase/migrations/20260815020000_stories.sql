-- Instagram-style stories: ephemeral (24h) photo/video posts, a viewed/
-- unviewed ring on avatars, and highlights that let an author pin specific
-- stories past their expiry. Visibility follows the app's existing default
-- (public read, like profiles/projects/likes/comments — `saves` remains the
-- one deliberate private exception) rather than a new follower-gated model;
-- the Home rail scoping to "people you follow" is a client-side feed
-- choice, not a server-side restriction, same distinction the app already
-- draws elsewhere. Reuses the existing `media_type` enum, the
-- `project-media` storage bucket (already serving images and video, no new
-- bucket needed), `is_blocked()` for blocked-pair filtering, and
-- `record_rate_limit_event` for abuse protection.
create table public.stories (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  media_url text not null,
  media_type media_type not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);
create index stories_author_idx on public.stories (author_id, created_at desc);

-- Primary key doubles as the idempotency guard — viewing the same story
-- twice (e.g. re-entering the viewer) doesn't duplicate a row or a "view".
create table public.story_views (
  story_id uuid not null references public.stories (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (story_id, viewer_id)
);

create table public.story_highlights (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  title text not null,
  created_at timestamptz not null default now()
);
create index story_highlights_owner_idx on public.story_highlights (owner_id, created_at desc);

create table public.story_highlight_items (
  highlight_id uuid not null references public.story_highlights (id) on delete cascade,
  story_id uuid not null references public.stories (id) on delete cascade,
  position integer not null default 0,
  primary key (highlight_id, story_id)
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

grant select on
  public.stories, public.story_views, public.story_highlights, public.story_highlight_items
to anon;

grant select, insert, delete on public.stories to authenticated;
grant select, insert on public.story_views to authenticated;
grant select, insert, update, delete on public.story_highlights, public.story_highlight_items to authenticated;

alter table public.stories enable row level security;
alter table public.story_views enable row level security;
alter table public.story_highlights enable row level security;
alter table public.story_highlight_items enable row level security;

-- No update policy at all — a story is immutable once posted (delete and
-- repost is the only "edit" path), same as likes/saves having no update.
create policy "stories are publicly readable" on public.stories for select using (true);
create policy "authors post their own stories" on public.stories for insert
  with check (auth.uid() = author_id);
create policy "authors delete their own stories" on public.stories for delete
  using (auth.uid() = author_id);

-- Readable by the viewer themself (so "have I seen this" checks work
-- client-side) or by the story's author (so "who viewed my story" works).
create policy "story views are readable by viewer or story author" on public.story_views for select
  using (
    auth.uid() = viewer_id
    or exists (select 1 from public.stories s where s.id = story_id and s.author_id = auth.uid())
  );
create policy "users record their own story views" on public.story_views for insert
  with check (auth.uid() = viewer_id);

create policy "highlights are publicly readable" on public.story_highlights for select using (true);
create policy "owners manage their own highlights" on public.story_highlights for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create policy "highlight items are publicly readable" on public.story_highlight_items for select using (true);
create policy "owners manage their own highlight items" on public.story_highlight_items for all
  using (exists (
    select 1 from public.story_highlights h where h.id = highlight_id and h.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.story_highlights h where h.id = highlight_id and h.owner_id = auth.uid()
  ));

-- ---------------------------------------------------------------------------
-- Rate limiting — same shape as notes_rate_limit/comments_rate_limit.
-- ---------------------------------------------------------------------------

create or replace function public.stories_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.author_id, 'stories', 20, 86400);
  return new;
end;
$$;
drop trigger if exists stories_rate_limit on public.stories;
create trigger stories_rate_limit before insert on public.stories
  for each row execute function public.stories_rate_limit();

-- ---------------------------------------------------------------------------
-- Feed view — only non-expired stories, blocked pairs excluded (same
-- filtering `project_feed` already applies), with a per-viewer
-- `viewed_by_me` flag the client groups by author to decide the ring state.
-- ---------------------------------------------------------------------------

create or replace view public.active_stories_feed
with (security_invoker = true) as
select
  s.id,
  s.author_id,
  s.media_url,
  s.media_type,
  s.created_at,
  s.expires_at,
  p.username as author_username,
  p.display_name as author_display_name,
  p.avatar_url as author_avatar_url,
  exists(
    select 1 from public.story_views v where v.story_id = s.id and v.viewer_id = auth.uid()
  ) as viewed_by_me
from public.stories s
join public.profiles p on p.id = s.author_id
where s.expires_at > now() and not public.is_blocked(s.author_id)
order by s.created_at;

grant select on public.active_stories_feed to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Report integration — stories plug into the existing report pipeline
-- rather than a bespoke flow.
-- ---------------------------------------------------------------------------

alter table public.content_reports drop constraint content_reports_target_type_check;
alter table public.content_reports add constraint content_reports_target_type_check
  check (target_type in ('profile', 'project', 'comment', 'update', 'story'));
