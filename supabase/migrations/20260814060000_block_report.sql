-- Block/report — the biggest real gap for a public app with user-generated
-- content: right now there is no way to stop seeing someone, or to flag
-- something that shouldn't be up. Two new tables, a handful of
-- `security definer` RPCs (so a block also atomically tears down any
-- existing follow relationship, rather than leaving the client to do that
-- as a second, separately-racy step), enforcement triggers on
-- follows/conversations/messages, and blocked-pair filtering folded into
-- `project_feed` and `suggested_profiles` so it reaches every surface that
-- already reads through them (Discover, Home, similar-projects,
-- suggested-follows) for free.

create table public.blocked_profiles (
  blocker_id uuid not null references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint blocked_profiles_not_self check (blocker_id <> blocked_id)
);

alter table public.blocked_profiles enable row level security;

-- Blocks are private: you can only ever see or manage your own outgoing
-- block list, never who has blocked you, never anyone else's list.
grant select, insert, delete on public.blocked_profiles to authenticated;

create policy "users manage their own blocks"
  on public.blocked_profiles for all
  using (auth.uid() = blocker_id)
  with check (auth.uid() = blocker_id);

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles (id) on delete cascade,
  target_type text not null check (target_type in ('profile', 'project', 'comment', 'update')),
  target_id uuid not null,
  reason text not null check (reason in ('spam', 'harassment', 'inappropriate', 'impersonation', 'other')),
  details text,
  status text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at timestamptz not null default now()
);

create index content_reports_target_idx on public.content_reports (target_type, target_id);

alter table public.content_reports enable row level security;

-- Reports are write-once from the client: insert your own, read your own
-- submission history back, no update/delete grant at all (an immutable
-- accusation trail) — review happens by direct DB access for now, same
-- solo-dev-operated stage as everything else pre-launch.
grant select, insert on public.content_reports to authenticated;

create policy "users submit their own reports"
  on public.content_reports for insert
  with check (auth.uid() = reporter_id);

create policy "users read their own submitted reports"
  on public.content_reports for select
  using (auth.uid() = reporter_id);

create or replace function public.reports_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.reporter_id, 'reports', 20, 86400);
  return new;
end;
$$;
drop trigger if exists reports_rate_limit on public.content_reports;
create trigger reports_rate_limit before insert on public.content_reports
  for each row execute function public.reports_rate_limit();

create or replace function public.block_profile(target_profile_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if target_profile_id = auth.uid() then
    raise exception 'You can''t block yourself.';
  end if;

  insert into public.blocked_profiles (blocker_id, blocked_id)
  values (auth.uid(), target_profile_id)
  on conflict do nothing;

  delete from public.follows
  where (follower_id = auth.uid() and followee_profile_id = target_profile_id)
     or (follower_id = target_profile_id and followee_profile_id = auth.uid());
end;
$$;
grant execute on function public.block_profile(uuid) to authenticated;

create or replace function public.unblock_profile(target_profile_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.blocked_profiles
  where blocker_id = auth.uid() and blocked_id = target_profile_id;
$$;
grant execute on function public.unblock_profile(uuid) to authenticated;

-- Bidirectional: true whether the caller blocked the target or the target
-- blocked the caller — the UI doesn't need to distinguish (the outcome,
-- hiding follow/message affordances, is the same either way), and this
-- deliberately never reveals *which* direction to the client so a blocked
-- user can't tell they were the one who got blocked.
create or replace function public.is_blocked(target_profile_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.blocked_profiles
    where (blocker_id = auth.uid() and blocked_id = target_profile_id)
       or (blocker_id = target_profile_id and blocked_id = auth.uid())
  );
$$;
grant execute on function public.is_blocked(uuid) to authenticated;

create or replace function public.submit_report(
  p_target_type text, p_target_id uuid, p_reason text, p_details text default null
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.content_reports (reporter_id, target_type, target_id, reason, details)
  values (auth.uid(), p_target_type, p_target_id, p_reason, p_details);
$$;
grant execute on function public.submit_report(text, uuid, text, text) to authenticated;

create or replace function public.follows_block_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  other_profile uuid;
begin
  other_profile := coalesce(
    new.followee_profile_id,
    (select owner_id from public.projects where id = new.followee_project_id)
  );
  if other_profile is not null and exists (
    select 1 from public.blocked_profiles
    where (blocker_id = new.follower_id and blocked_id = other_profile)
       or (blocker_id = other_profile and blocked_id = new.follower_id)
  ) then
    raise exception 'You can''t follow this.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists follows_block_check on public.follows;
create trigger follows_block_check before insert on public.follows
  for each row execute function public.follows_block_check();

create or replace function public.conversation_block_check() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (
    select 1 from public.blocked_profiles
    where (blocker_id = new.user_one_id and blocked_id = new.user_two_id)
       or (blocker_id = new.user_two_id and blocked_id = new.user_one_id)
  ) then
    raise exception 'You can''t message this person.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists conversation_block_check on public.conversations;
create trigger conversation_block_check before insert on public.conversations
  for each row execute function public.conversation_block_check();

-- Covers the case where a block happens *after* a conversation already
-- exists — the conversation-creation check above only guards new threads.
create or replace function public.message_block_check() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  other_participant uuid;
begin
  select case when user_one_id = new.sender_id then user_two_id else user_one_id end
  into other_participant
  from public.conversations where id = new.conversation_id;

  if other_participant is not null and exists (
    select 1 from public.blocked_profiles
    where (blocker_id = new.sender_id and blocked_id = other_participant)
       or (blocker_id = other_participant and blocked_id = new.sender_id)
  ) then
    raise exception 'You can''t message this person.' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
drop trigger if exists message_block_check on public.messages;
create trigger message_block_check before insert on public.messages
  for each row execute function public.message_block_check();

-- Blocked-pair filtering folded directly into project_feed so Discover,
-- Home's New/Trending, and similar_projects_to_profile (which reads
-- through this view) all stop surfacing a blocked pair's projects without
-- each caller needing to filter separately. `security_invoker` means
-- auth.uid() here correctly resolves to whoever is actually running the
-- query, not the view's owner.
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
  p.cover_image_url
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
-- is_blocked() is `security definer`, so it correctly sees a block
-- regardless of direction even though blocked_profiles' own RLS would
-- otherwise hide "someone blocked me" rows from the blocked party. A raw
-- subquery against blocked_profiles here would run under the invoker's
-- RLS (this view is security_invoker) and silently miss that direction.
where not public.is_blocked(p.owner_id);

grant select on public.project_feed to anon, authenticated;

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
    and not public.is_blocked(pr.id)
  order by coalesce(s.score, 0) desc, coalesce(pop.follower_count, 0) desc, pr.created_at desc
  limit limit_count;
$$;

grant execute on function public.suggested_profiles(int) to authenticated;
