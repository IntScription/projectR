-- ProjectR initial schema
-- Identity (profiles), Projects & Content, Social Graph — see docs/blueprint for the full design rationale.

create extension if not exists citext;
create extension if not exists pgcrypto;

create type project_category as enum (
  'software', 'ai', 'games', 'design', 'music', 'art', 'hardware', 'writing', 'research', 'other'
);

create type project_status as enum (
  'idea', 'building', 'testing', 'launched', 'maintaining', 'archived'
);

create type media_type as enum ('image', 'video');

-- ---------------------------------------------------------------------------
-- Identity
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username citext unique not null,
  display_name text not null,
  avatar_url text,
  bio text,
  skills text[] not null default '{}',
  links jsonb not null default '[]', -- [{ "label": "GitHub", "url": "https://..." }, ...]
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint username_format check (username ~ '^[a-zA-Z0-9_]{3,30}$')
);
comment on table public.profiles is 'ProjectR identity — separate from auth.users on purpose. Created explicitly during onboarding, not auto-provisioned on signup.';

-- ---------------------------------------------------------------------------
-- Projects & content
-- ---------------------------------------------------------------------------

create table public.projects (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  slug text unique not null,
  name text not null,
  description text,
  cover_image_url text,
  category project_category not null,
  tags text[] not null default '{}',
  status project_status not null default 'idea',
  tech_stack text[] not null default '{}',
  github_url text,
  website_url text,
  view_count integer not null default 0,
  -- Maintained by the trigger below rather than a GENERATED column:
  -- to_tsvector(regconfig, text) is STABLE, not IMMUTABLE, so Postgres
  -- refuses it in a generated expression.
  search_vector tsvector,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index projects_owner_idx on public.projects (owner_id);
create index projects_tags_gin_idx on public.projects using gin (tags);
create index projects_category_idx on public.projects (category);
create index projects_search_idx on public.projects using gin (search_vector);

create table public.project_media (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  type media_type not null,
  url text not null,
  position integer not null default 0,
  created_at timestamptz not null default now()
);
create index project_media_project_idx on public.project_media (project_id, position);

create table public.project_updates (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);
create index project_updates_project_idx on public.project_updates (project_id, created_at desc);

create table public.update_media (
  id uuid primary key default gen_random_uuid(),
  update_id uuid not null references public.project_updates (id) on delete cascade,
  type media_type not null,
  url text not null,
  position integer not null default 0
);
create index update_media_update_idx on public.update_media (update_id, position);

-- ---------------------------------------------------------------------------
-- Social graph
-- Engagement tables target one of two possible parents through a nullable
-- column pair (Postgres has no true polymorphic FK). Exactly one is set,
-- enforced by a CHECK constraint; partial unique indexes prevent duplicates.
-- ---------------------------------------------------------------------------

create table public.follows (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references public.profiles (id) on delete cascade,
  followee_profile_id uuid references public.profiles (id) on delete cascade,
  followee_project_id uuid references public.projects (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint follows_one_target check (num_nonnulls(followee_profile_id, followee_project_id) = 1),
  constraint follows_not_self check (follower_id <> followee_profile_id)
);
create unique index follows_unique_profile_idx on public.follows (follower_id, followee_profile_id) where followee_profile_id is not null;
create unique index follows_unique_project_idx on public.follows (follower_id, followee_project_id) where followee_project_id is not null;
create index follows_followee_profile_idx on public.follows (followee_profile_id);
create index follows_followee_project_idx on public.follows (followee_project_id);

create table public.likes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  project_id uuid references public.projects (id) on delete cascade,
  update_id uuid references public.project_updates (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint likes_one_target check (num_nonnulls(project_id, update_id) = 1)
);
create unique index likes_unique_project_idx on public.likes (user_id, project_id) where project_id is not null;
create unique index likes_unique_update_idx on public.likes (user_id, update_id) where update_id is not null;
create index likes_project_idx on public.likes (project_id);
create index likes_update_idx on public.likes (update_id);

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  project_id uuid references public.projects (id) on delete cascade,
  update_id uuid references public.project_updates (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  constraint comments_one_target check (num_nonnulls(project_id, update_id) = 1)
);
create index comments_project_idx on public.comments (project_id, created_at);
create index comments_update_idx on public.comments (update_id, created_at);

create table public.saves (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  created_at timestamptz not null default now(),
  unique (user_id, project_id)
);
create index saves_project_idx on public.saves (project_id);

-- ---------------------------------------------------------------------------
-- updated_at maintenance
-- ---------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
  for each row execute function public.set_updated_at();
create trigger projects_set_updated_at before update on public.projects
  for each row execute function public.set_updated_at();

create or replace function public.projects_search_vector_update()
returns trigger
language plpgsql
as $$
begin
  new.search_vector :=
    setweight(to_tsvector('english', coalesce(new.name, '')), 'A') ||
    setweight(to_tsvector('english', coalesce(new.description, '')), 'B') ||
    setweight(to_tsvector('english', array_to_string(new.tags, ' ')), 'C');
  return new;
end;
$$;

create trigger projects_search_vector_update before insert or update
  on public.projects for each row execute function public.projects_search_vector_update();

-- ---------------------------------------------------------------------------
-- Row Level Security
-- Public read everywhere except `saves` (bookmarks are a private reading
-- list, not a public signal — a deliberate deviation from "everything is
-- public"). Writes are restricted to the acting user; media/update tables
-- gate writes through a join back to the parent project's owner_id.
-- ---------------------------------------------------------------------------

-- Table-level GRANTs, separate from RLS. New public-schema tables are no
-- longer auto-exposed to the Data API roles (see api.auto_expose_new_tables
-- in config.toml) — RLS policies alone don't grant access.
grant usage on schema public to anon, authenticated;

grant select on
  public.profiles, public.projects, public.project_media, public.project_updates,
  public.update_media, public.follows, public.likes, public.comments, public.saves
to anon;

grant select, insert, update, delete on
  public.profiles, public.projects, public.project_media, public.project_updates,
  public.update_media, public.follows, public.likes, public.comments, public.saves
to authenticated;

alter table public.profiles enable row level security;
alter table public.projects enable row level security;
alter table public.project_media enable row level security;
alter table public.project_updates enable row level security;
alter table public.update_media enable row level security;
alter table public.follows enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.saves enable row level security;

create policy "profiles are publicly readable" on public.profiles for select using (true);
create policy "users manage their own profile" on public.profiles for all
  using (auth.uid() = id) with check (auth.uid() = id);

create policy "projects are publicly readable" on public.projects for select using (true);
create policy "owners manage their own projects" on public.projects for all
  using (auth.uid() = owner_id) with check (auth.uid() = owner_id);

create policy "project media is publicly readable" on public.project_media for select using (true);
create policy "owners manage their project media" on public.project_media for all
  using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()))
  with check (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()));

create policy "project updates are publicly readable" on public.project_updates for select using (true);
create policy "owners manage their project updates" on public.project_updates for all
  using (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()))
  with check (exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid()));

create policy "update media is publicly readable" on public.update_media for select using (true);
create policy "owners manage their update media" on public.update_media for all
  using (exists (
    select 1 from public.project_updates u
    join public.projects p on p.id = u.project_id
    where u.id = update_id and p.owner_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.project_updates u
    join public.projects p on p.id = u.project_id
    where u.id = update_id and p.owner_id = auth.uid()
  ));

create policy "follows are publicly readable" on public.follows for select using (true);
create policy "users manage their own follows" on public.follows for all
  using (auth.uid() = follower_id) with check (auth.uid() = follower_id);

create policy "likes are publicly readable" on public.likes for select using (true);
create policy "users manage their own likes" on public.likes for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "comments are publicly readable" on public.comments for select using (true);
create policy "users manage their own comments" on public.comments for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "users manage their own saves" on public.saves for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Storage buckets
-- ---------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true),
       ('project-media', 'project-media', true)
on conflict (id) do nothing;

-- Uploads are expected at path "{auth.uid()}/filename.ext" so ownership can
-- be checked from the storage path alone.
create policy "avatar images are publicly readable" on storage.objects for select
  using (bucket_id = 'avatars');
create policy "users manage their own avatar" on storage.objects for all
  using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1])
  with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);

create policy "project media is publicly readable in storage" on storage.objects for select
  using (bucket_id = 'project-media');
create policy "users manage their own project media in storage" on storage.objects for all
  using (bucket_id = 'project-media' and auth.uid()::text = (storage.foldername(name))[1])
  with check (bucket_id = 'project-media' and auth.uid()::text = (storage.foldername(name))[1]);
