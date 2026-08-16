-- Weekly point-in-time repo metadata (stars/open-issues/forks/watchers) —
-- the one thing GitHub's REST API doesn't expose historically, unlike
-- commit activity/code frequency/contributors/punch card, which are all
-- fetched live from GitHub's own Stats API and need no storage here (see
-- `ForgeRepoInsightsView`). Scoped to repos already attached to a
-- ProjectR project (`projects.github_url`) — that's the point a repo is
-- worth tracking long-term, and it means this reuses an existing column
-- instead of inventing a separate "tracked repos" concept.
create table public.repo_analytics_snapshots (
  id uuid primary key default gen_random_uuid(),
  github_url text not null,
  captured_at date not null default current_date,
  stars integer not null,
  open_issues integer not null,
  forks integer not null,
  watchers integer not null,
  created_at timestamptz not null default now(),
  unique (github_url, captured_at)
);

create index repo_analytics_snapshots_url_idx on public.repo_analytics_snapshots (github_url, captured_at);

alter table public.repo_analytics_snapshots enable row level security;

-- Same "publicly readable" policy `projects` itself already has — this is
-- derived, non-sensitive metadata about a public repo. No insert/update
-- policy for regular clients: rows only ever land here via the
-- `capture-repo-snapshots` Edge Function's service-role key.
create policy "repo analytics snapshots are publicly readable" on public.repo_analytics_snapshots
  for select using (true);

-- Same table-backed settings pattern `push_webhook_config.sql` introduced
-- for send-push (a URL baked into a migration doesn't survive shipping to
-- a real hosted project, and a secret baked into git history never
-- should've been there) — `app_settings` already exists from that
-- migration, this just adds two more keys to it, seeded per-environment
-- via a direct INSERT, never committed.
create or replace function public.capture_repo_snapshots_trigger()
returns void
language plpgsql
security definer
set search_path = public, net
as $$
declare
  function_url text;
  webhook_secret text;
begin
  select value into function_url from public.app_settings where key = 'repo_snapshot_function_url';
  select value into webhook_secret from public.app_settings where key = 'repo_snapshot_webhook_secret';

  if function_url is null or webhook_secret is null then
    raise warning 'repo_snapshot_function_url/repo_snapshot_webhook_secret not configured on this database — skipping this week''s repo snapshot capture';
    return;
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret
    ),
    body := '{}'::jsonb
  );
end;
$$;

-- pg_cron/pg_net are both already enabled (see 20260814080000_enable_pg_net.sql
-- and refresh-stale-profile-levels' pg_cron use) — Monday 4am, well clear
-- of the existing 3am daily level-refresh job.
select cron.schedule(
  'capture-repo-snapshots',
  '0 4 * * 1',
  $$select public.capture_repo_snapshots_trigger();$$
);
