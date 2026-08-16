-- Forge Phase 3: the minimum task model Forge linking actually needs —
-- title, status, an owning project, an optional linked branch. Not a full
-- project-management suite (no due dates, priorities, subtasks). `number`
-- is a per-project sequential integer (task #1, #2, ...) rather than just
-- the uuid, because that's what a person actually types into a commit
-- message ("Fix login validation (#3)") — the uuid isn't.
create type task_status as enum ('todo', 'in_progress', 'done');

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references public.projects (id) on delete cascade,
  number integer not null,
  title text not null,
  status task_status not null default 'todo',
  branch_name text,
  created_by uuid not null references public.profiles (id) on delete cascade,
  assignee_id uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (project_id, number)
);
create index tasks_project_idx on public.tasks (project_id, number);

create or replace function public.set_updated_at_tasks()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
create trigger tasks_set_updated_at before update on public.tasks
  for each row execute function public.set_updated_at_tasks();

-- Assigns the next per-project task number — same trigger-derives-a-value
-- shape as everything else that needs a value computed at insert time.
create or replace function public.assign_task_number()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select coalesce(max(number), 0) + 1 into new.number
  from public.tasks
  where project_id = new.project_id;
  return new;
end;
$$;
create trigger tasks_assign_number before insert on public.tasks
  for each row execute function public.assign_task_number();

grant select on public.tasks to anon, authenticated;
grant insert, update, delete on public.tasks to authenticated;

alter table public.tasks enable row level security;

create policy "tasks are publicly readable" on public.tasks for select using (true);

-- Identical shape to project_updates' owner-or-collaborator write policy
-- (see 20260813170000_project_collaborators.sql) — same permission model,
-- not a new one.
create policy "owners and collaborators manage tasks" on public.tasks for all
  using (
    exists (
      select 1 from public.projects p
      where p.id = tasks.project_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1 from public.project_collaborators c
            where c.project_id = p.id and c.user_id = auth.uid()
          )
        )
    )
  )
  with check (
    exists (
      select 1 from public.projects p
      where p.id = tasks.project_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1 from public.project_collaborators c
            where c.project_id = p.id and c.user_id = auth.uid()
          )
        )
    )
  );

-- ---------------------------------------------------------------------------
-- Feed reuse: Forge activity (branch created, PR opened) posts as a normal
-- project_updates row with an auto-generated body, rather than a second
-- parallel activity feed — reaches ProjectDetailView's updates section and
-- the profile "Posts" tab for free. `kind` lets the UI show a small icon
-- for Forge-generated entries; existing rows default to 'manual' and
-- render exactly as they do today.
-- ---------------------------------------------------------------------------
alter table public.project_updates add column kind text not null default 'manual'
  check (kind in ('manual', 'branch_created', 'pr_opened', 'pr_merged'));

-- ---------------------------------------------------------------------------
-- Chat rich cards: a nullable metadata payload on the existing messages
-- table rather than a new message type/table — ChatThreadView renders a
-- compact card when present, falls back to plain LinkifiedText otherwise.
-- ---------------------------------------------------------------------------
alter table public.messages add column metadata jsonb;
