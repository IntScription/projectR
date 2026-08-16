-- Projects had exactly one owner with no way to co-build. Adds
-- collaborators: the owner can add/remove anyone, a collaborator can
-- remove themselves ("leave"), and collaborators get the same
-- project_updates/update_media write access owners already have — the
-- point is real co-authorship (posting updates), not just a credits list.
create table public.project_collaborators (
  project_id uuid not null references public.projects (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (project_id, user_id)
);

alter table public.project_collaborators enable row level security;
grant select on public.project_collaborators to anon, authenticated;
grant insert, delete on public.project_collaborators to authenticated;

create policy "collaborators are publicly readable" on public.project_collaborators
  for select using (true);

create policy "owners add collaborators" on public.project_collaborators
  for insert with check (
    exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid())
  );

create policy "owners remove collaborators or collaborators leave" on public.project_collaborators
  for delete using (
    auth.uid() = user_id
    or exists (select 1 from public.projects p where p.id = project_id and p.owner_id = auth.uid())
  );

-- Extend project_updates / update_media write access from "owner only" to
-- "owner or collaborator." Same USING/WITH CHECK shape both tables had
-- before, just with the collaborator EXISTS clause added.
drop policy "owners manage their project updates" on public.project_updates;
create policy "owners and collaborators manage project updates" on public.project_updates
  for all using (
    exists (
      select 1 from public.projects p
      where p.id = project_updates.project_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1 from public.project_collaborators c
            where c.project_id = p.id and c.user_id = auth.uid()
          )
        )
    )
  ) with check (
    exists (
      select 1 from public.projects p
      where p.id = project_updates.project_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1 from public.project_collaborators c
            where c.project_id = p.id and c.user_id = auth.uid()
          )
        )
    )
  );

drop policy "owners manage their update media" on public.update_media;
create policy "owners and collaborators manage update media" on public.update_media
  for all using (
    exists (
      select 1 from public.project_updates u
      join public.projects p on p.id = u.project_id
      where u.id = update_media.update_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1 from public.project_collaborators c
            where c.project_id = p.id and c.user_id = auth.uid()
          )
        )
    )
  ) with check (
    exists (
      select 1 from public.project_updates u
      join public.projects p on p.id = u.project_id
      where u.id = update_media.update_id
        and (
          p.owner_id = auth.uid()
          or exists (
            select 1 from public.project_collaborators c
            where c.project_id = p.id and c.user_id = auth.uid()
          )
        )
    )
  );
