-- `content_reports` already anticipated a review workflow (`status` was
-- always 'open'/'reviewed'/'dismissed'), but nothing could ever move it
-- past 'open' — no update grant existed at all, and reports were only
-- ever readable by their own submitter. This adds a real, minimal admin
-- concept (a single boolean, not a roles/permissions system — solo-dev
-- scope) and the read/update access an actual review queue needs.
--
-- There's no UI to grant this — flip it directly for yourself:
--   update public.profiles set is_admin = true where username = 'you';
alter table public.profiles add column is_admin boolean not null default false;

grant update on public.content_reports to authenticated;

create policy "admins read all reports" on public.content_reports
  for select using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create policy "admins update reports" on public.content_reports
  for update
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));
