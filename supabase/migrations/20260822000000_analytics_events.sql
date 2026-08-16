-- Self-hosted event log — no new vendor/SDK, fits the existing
-- entirely-Supabase architecture. Write-only from the client: there's no
-- select policy for regular users, since this is meant to be queried
-- directly (psql/dashboard) by the developer, not shown back in the app.
create table public.analytics_events (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles (id) on delete set null,
  event_name text not null,
  properties jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index analytics_events_event_idx on public.analytics_events (event_name, created_at);
create index analytics_events_profile_idx on public.analytics_events (profile_id, created_at);

alter table public.analytics_events enable row level security;

create policy "users insert their own analytics events" on public.analytics_events
  for insert with check (auth.uid() = profile_id);
