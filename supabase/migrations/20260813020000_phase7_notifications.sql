-- Phase 7: notifications.
--
-- The in-app notification center is real and fully implemented here:
-- fan-out happens via triggers on the tables that already exist (follows,
-- likes, comments, project_updates) rather than touching every app-side
-- insert call site. Trigger functions run `security definer` so they can
-- write into `notifications` regardless of the acting user's own grants —
-- the acting user only ever gets SELECT/UPDATE on their own rows, never
-- INSERT, so notifications can't be fabricated client-side.
--
-- `device_tokens` is push-registration plumbing: the client can register a
-- token here today, but nothing sends an APNs push yet — that needs an
-- Apple Developer Program membership (already the blocker noted for Sign in
-- with Apple) plus a server-side sender. See README.

create type notification_type as enum ('follow', 'like', 'comment', 'update');

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  actor_id uuid not null references public.profiles (id) on delete cascade,
  type notification_type not null,
  project_id uuid references public.projects (id) on delete cascade,
  update_id uuid references public.project_updates (id) on delete cascade,
  comment_id uuid references public.comments (id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

alter table public.notifications enable row level security;
grant select, update on public.notifications to authenticated;

create policy "users read their own notifications" on public.notifications for select
  using (auth.uid() = recipient_id);
create policy "users mark their own notifications read" on public.notifications for update
  using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

-- ---------------------------------------------------------------------------
-- Fan-out triggers
-- ---------------------------------------------------------------------------

create or replace function public.notify_on_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.followee_profile_id is not null then
    insert into public.notifications (recipient_id, actor_id, type)
    values (new.followee_profile_id, new.follower_id, 'follow');
  elsif new.followee_project_id is not null then
    -- `select` (unlike `values`) doesn't implicitly cast a bare string
    -- literal to the target enum column, so this needs an explicit cast.
    insert into public.notifications (recipient_id, actor_id, type, project_id)
    select p.owner_id, new.follower_id, 'follow'::notification_type, new.followee_project_id
    from public.projects p
    where p.id = new.followee_project_id
      and p.owner_id <> new.follower_id;
  end if;
  return new;
end;
$$;

create trigger follows_notify after insert on public.follows
  for each row execute function public.notify_on_follow();

create or replace function public.notify_on_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient uuid;
begin
  if new.project_id is not null then
    select owner_id into recipient from public.projects where id = new.project_id;
    if recipient is not null and recipient <> new.user_id then
      insert into public.notifications (recipient_id, actor_id, type, project_id)
      values (recipient, new.user_id, 'like', new.project_id);
    end if;
  elsif new.update_id is not null then
    select p.owner_id into recipient
    from public.project_updates u
    join public.projects p on p.id = u.project_id
    where u.id = new.update_id;
    if recipient is not null and recipient <> new.user_id then
      insert into public.notifications (recipient_id, actor_id, type, update_id)
      values (recipient, new.user_id, 'like', new.update_id);
    end if;
  end if;
  return new;
end;
$$;

create trigger likes_notify after insert on public.likes
  for each row execute function public.notify_on_like();

create or replace function public.notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient uuid;
begin
  if new.project_id is not null then
    select owner_id into recipient from public.projects where id = new.project_id;
    if recipient is not null and recipient <> new.user_id then
      insert into public.notifications (recipient_id, actor_id, type, project_id, comment_id)
      values (recipient, new.user_id, 'comment', new.project_id, new.id);
    end if;
  elsif new.update_id is not null then
    select p.owner_id into recipient
    from public.project_updates u
    join public.projects p on p.id = u.project_id
    where u.id = new.update_id;
    if recipient is not null and recipient <> new.user_id then
      insert into public.notifications (recipient_id, actor_id, type, update_id, comment_id)
      values (recipient, new.user_id, 'comment', new.update_id, new.id);
    end if;
  end if;
  return new;
end;
$$;

create trigger comments_notify after insert on public.comments
  for each row execute function public.notify_on_comment();

-- New update → notify everyone following the project directly, or
-- following its creator. `distinct` collapses the case where a follower
-- matches both conditions.
create or replace function public.notify_on_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  project_owner uuid;
begin
  select owner_id into project_owner from public.projects where id = new.project_id;

  insert into public.notifications (recipient_id, actor_id, type, project_id, update_id)
  select distinct f.follower_id, project_owner, 'update'::notification_type, new.project_id, new.id
  from public.follows f
  where (f.followee_project_id = new.project_id or f.followee_profile_id = project_owner)
    and f.follower_id <> project_owner;

  return new;
end;
$$;

create trigger project_updates_notify after insert on public.project_updates
  for each row execute function public.notify_on_update();

-- ---------------------------------------------------------------------------
-- Push registration plumbing
-- ---------------------------------------------------------------------------

create table public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'ios',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, token)
);

alter table public.device_tokens enable row level security;
grant select, insert, update, delete on public.device_tokens to authenticated;

create policy "users manage their own device tokens" on public.device_tokens for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create trigger device_tokens_set_updated_at before update on public.device_tokens
  for each row execute function public.set_updated_at();
