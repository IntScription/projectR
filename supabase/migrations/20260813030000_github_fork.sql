-- "Download" on an open-source project forks its GitHub repo to the
-- viewer's own account. Two additions: an explicit open-source flag (not
-- inferred from github_url being set — a project can link a private repo
-- for reference without inviting forks), and a place to keep the viewer's
-- GitHub access token once they connect their account.

alter table public.projects
  add column is_open_source boolean not null default false;

-- The access token here is only as protected as RLS makes it — equivalent
-- sensitivity to a bearer credential, stored in plaintext. Fine for this
-- pass; encrypting at rest (pgsodium/Vault) is a real hardening item for
-- later, not a blocker now.
create table public.github_connections (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  access_token text not null,
  github_username text,
  connected_at timestamptz not null default now()
);

alter table public.github_connections enable row level security;
grant select, insert, update, delete on public.github_connections to authenticated;

create policy "users manage their own github connection" on public.github_connections for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);
