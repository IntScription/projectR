-- Short public text notes, posted from the Add tab, surfaced on the
-- author's profile in the "Notes" tab. Deliberately separate from
-- `project_updates` — a note isn't tied to any one project, it's a
-- lightweight status/thought, closer to a tweet than a devlog entry.
-- Public (like everything else except `saves`), so it shows up on
-- other people's profiles too, not just your own.
create table public.notes (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index notes_author_idx on public.notes (author_id, created_at desc);

alter table public.notes enable row level security;
grant select on public.notes to anon, authenticated;
grant insert, delete on public.notes to authenticated;

create policy "notes are publicly readable" on public.notes for select using (true);
create policy "users manage their own notes" on public.notes for all
  using (auth.uid() = author_id) with check (auth.uid() = author_id);
