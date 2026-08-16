-- Backing schema for: profile role tags, public GitHub-verified checkmark,
-- an Instagram-grid "Posts" tab, a "Saved" tab, and a rule-based level/
-- skill dashboard. All new client-facing surfaces are either publicly
-- readable views (matching project_feed's `security_invoker` pattern) or
-- `security definer` functions that never trust a client-supplied id for
-- anything privileged — same discipline as the rest of this schema.

-- A free-text badge shown next to a profile's name (e.g. "ProjectR
-- Developer"). Nullable; almost every profile leaves it unset. Deliberately
-- just a column the owner can set via the existing "users manage their own
-- profile" policy, not a special role/permission system — it's a display
-- label, not an authorization mechanism.
alter table public.profiles add column if not exists role text;

-- Public "is this account GitHub-connected" check — a trust signal (like a
-- verified badge), safe to expose to anyone, unlike the token itself which
-- stays behind the auth.uid()-gated functions from the previous migration.
create or replace function public.is_github_connected(target_profile_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from public.github_connections where user_id = target_profile_id);
$$;

grant execute on function public.is_github_connected(uuid) to anon, authenticated;

-- Instagram-grid-style "Posts" tab: one row per update, with its first
-- media item (if any) flattened in rather than requiring a second query
-- per grid cell.
create or replace view public.profile_updates_feed
with (security_invoker = true) as
select
  pu.id,
  pu.project_id,
  pu.body,
  pu.created_at,
  p.owner_id,
  p.slug as project_slug,
  p.name as project_name,
  (
    select um.url from public.update_media um
    where um.update_id = pu.id
    order by um.position asc
    limit 1
  ) as media_url,
  (
    select um.type from public.update_media um
    where um.update_id = pu.id
    order by um.position asc
    limit 1
  ) as media_type
from public.project_updates pu
join public.projects p on p.id = pu.project_id;

grant select on public.profile_updates_feed to anon, authenticated;

-- "Saved" tab — own-profile only (saves are private), so this only ever
-- needs to work for the caller's own rows. security_invoker means the
-- existing "users manage their own saves" RLS on `saves` already does
-- that scoping; this view just joins in the project_feed shape so the
-- client can reuse the same card component as everywhere else.
create or replace view public.saved_projects_feed
with (security_invoker = true) as
select pf.*, s.user_id as saved_by, s.created_at as saved_at
from public.saves s
join public.project_feed pf on pf.id = s.project_id;

grant select on public.saved_projects_feed to authenticated;

-- Level/skill dashboard. Deliberately rule-based rather than calling an
-- LLM: every signal already lives in this DB (tech stack diversity across
-- owned projects, how many shipped past "idea", update cadence, and
-- engagement received), so a `security definer` function can score it
-- directly with no external API, no key to manage, and no per-run cost.
-- Cached in a table rather than computed on every read, and lazily
-- refreshed once a day (see get_profile_level) rather than needing a cron
-- job — a dashboard that's stale by at most a day is a fine trade against
-- the operational cost of scheduling.
create table public.profile_levels (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  level int not null default 1,
  level_label text not null default 'Beginner',
  score int not null default 0,
  skills jsonb not null default '[]'::jsonb,
  projects_analyzed int not null default 0,
  summary text not null default '',
  computed_at timestamptz not null default now()
);

alter table public.profile_levels enable row level security;
grant select on public.profile_levels to anon, authenticated;
create policy "profile levels are publicly readable" on public.profile_levels for select using (true);
-- No insert/update grants at all — only ever written by refresh_profile_level below.

create or replace function public.refresh_profile_level(target_profile_id uuid)
returns public.profile_levels
language plpgsql
security definer
set search_path = public
as $$
declare
  proj_count int;
  launched_count int;
  update_count int;
  like_total int;
  comment_total int;
  tech_list jsonb;
  computed_score int;
  computed_level int;
  computed_label text;
  result public.profile_levels;
begin
  select count(*), count(*) filter (where status in ('launched', 'maintaining'))
    into proj_count, launched_count
    from public.projects where owner_id = target_profile_id;

  select count(*) into update_count
    from public.project_updates pu
    join public.projects p on p.id = pu.project_id
    where p.owner_id = target_profile_id;

  select
    coalesce(sum(l.like_count), 0), coalesce(sum(c.comment_count), 0)
    into like_total, comment_total
    from public.projects p
    left join lateral (
      select count(*) as like_count from public.likes where project_id = p.id
    ) l on true
    left join lateral (
      select count(*) as comment_count from public.comments where project_id = p.id
    ) c on true
    where p.owner_id = target_profile_id;

  select coalesce(jsonb_agg(jsonb_build_object('name', tech, 'projects', cnt) order by cnt desc), '[]'::jsonb)
    into tech_list
    from (
      select tech, count(*) as cnt
      from public.projects p, unnest(p.tech_stack) as tech
      where p.owner_id = target_profile_id
      group by tech
      order by cnt desc
      limit 8
    ) t;

  computed_score :=
    proj_count * 2 + launched_count * 3 + least(update_count, 20)
    + least(like_total, 30) / 3 + least(comment_total, 30) / 3;

  computed_level := case
    when computed_score >= 25 then 4
    when computed_score >= 12 then 3
    when computed_score >= 5 then 2
    else 1
  end;

  computed_label := case computed_level
    when 4 then 'Expert'
    when 3 then 'Advanced'
    when 2 then 'Intermediate'
    else 'Beginner'
  end;

  insert into public.profile_levels (
    profile_id, level, level_label, score, skills, projects_analyzed, summary, computed_at
  )
  values (
    target_profile_id, computed_level, computed_label, computed_score, tech_list, proj_count,
    format(
      '%s project%s, %s launched, %s update%s posted.',
      proj_count, case when proj_count = 1 then '' else 's' end,
      launched_count, update_count, case when update_count = 1 then '' else 's' end
    ),
    now()
  )
  on conflict (profile_id) do update set
    level = excluded.level,
    level_label = excluded.level_label,
    score = excluded.score,
    skills = excluded.skills,
    projects_analyzed = excluded.projects_analyzed,
    summary = excluded.summary,
    computed_at = excluded.computed_at
  returning * into result;

  return result;
end;
$$;

grant execute on function public.refresh_profile_level(uuid) to authenticated;

create or replace function public.get_profile_level(target_profile_id uuid)
returns public.profile_levels
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.profile_levels;
begin
  select * into result from public.profile_levels where profile_id = target_profile_id;
  if result is null or result.computed_at < now() - interval '1 day' then
    result := public.refresh_profile_level(target_profile_id);
  end if;
  return result;
end;
$$;

grant execute on function public.get_profile_level(uuid) to anon, authenticated;
