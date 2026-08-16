-- Basic abuse protection: notes, comments, project creation, and chat
-- messages had no rate limiting at all — fine for a closed beta, not fine
-- once this is public. A shared event log + a small helper function, with
-- one trigger function per table (rather than one fully generic trigger)
-- since `NEW`'s column name differs per table and PL/pgSQL resolves
-- record field access per concrete row type.
create table public.rate_limit_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  action text not null,
  created_at timestamptz not null default now()
);

create index rate_limit_events_lookup_idx on public.rate_limit_events (user_id, action, created_at);

-- No RLS/grants at all — this table is never touched directly by clients,
-- only by the trigger functions below (which run as the table owner).

create or replace function public.record_rate_limit_event(
  p_user_id uuid, p_action text, p_max_count int, p_window_seconds int
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  recent_count int;
begin
  select count(*) into recent_count
  from public.rate_limit_events
  where user_id = p_user_id
    and action = p_action
    and created_at > now() - make_interval(secs => p_window_seconds);

  if recent_count >= p_max_count then
    raise exception 'You''re doing that too fast — try again in a bit.'
      using errcode = 'P0001', hint = format('rate_limit:%s', p_action);
  end if;

  insert into public.rate_limit_events (user_id, action) values (p_user_id, p_action);
end;
$$;

create or replace function public.notes_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.author_id, 'notes', 10, 3600);
  return new;
end;
$$;
create trigger notes_rate_limit before insert on public.notes
  for each row execute function public.notes_rate_limit();

create or replace function public.comments_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.user_id, 'comments', 30, 3600);
  return new;
end;
$$;
create trigger comments_rate_limit before insert on public.comments
  for each row execute function public.comments_rate_limit();

create or replace function public.projects_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.owner_id, 'projects', 5, 86400);
  return new;
end;
$$;
create trigger projects_rate_limit before insert on public.projects
  for each row execute function public.projects_rate_limit();

create or replace function public.messages_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.sender_id, 'messages', 60, 3600);
  return new;
end;
$$;
create trigger messages_rate_limit before insert on public.messages
  for each row execute function public.messages_rate_limit();
