-- Security hardening: github_connections.access_token was plaintext.
-- RLS already scoped reads/writes to the owning user, so this wasn't an
-- API-level authorization gap — but a raw DB/backup compromise would have
-- exposed every connected user's real GitHub bearer token at once. Moves
-- storage into Supabase Vault (encrypted at rest) and removes direct
-- client table access entirely: writes and reads now only happen through
-- `security definer` functions that hard-check `auth.uid()` themselves,
-- never trusting a client-supplied user id.

alter table public.github_connections add column access_token_id uuid references vault.secrets (id);

-- Migrate any existing plaintext tokens into Vault before dropping the column.
do $$
declare
  row_record record;
  new_secret_id uuid;
begin
  for row_record in select user_id, access_token from public.github_connections loop
    new_secret_id := vault.create_secret(
      row_record.access_token,
      'github_access_token:' || row_record.user_id::text,
      'GitHub OAuth access token'
    );
    update public.github_connections
      set access_token_id = new_secret_id
      where user_id = row_record.user_id;
  end loop;
end $$;

alter table public.github_connections drop column access_token;
alter table public.github_connections alter column access_token_id set not null;

-- No more direct client access to the table at all — every interaction
-- goes through the functions below, which enforce auth.uid() themselves.
revoke select, insert, update, delete on public.github_connections from authenticated;
drop policy if exists "users manage their own github connection" on public.github_connections;

create or replace function public.set_my_github_access_token(token text, username text default null)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  caller uuid := auth.uid();
  new_secret_id uuid;
  existing_secret_id uuid;
begin
  if caller is null then
    raise exception 'not authenticated';
  end if;

  select access_token_id into existing_secret_id
    from public.github_connections where user_id = caller;

  if existing_secret_id is not null then
    perform vault.update_secret(existing_secret_id, token);
    new_secret_id := existing_secret_id;
  else
    new_secret_id := vault.create_secret(
      token, 'github_access_token:' || caller::text, 'GitHub OAuth access token'
    );
  end if;

  insert into public.github_connections (user_id, access_token_id, github_username)
  values (caller, new_secret_id, username)
  on conflict (user_id) do update set
    access_token_id = excluded.access_token_id,
    github_username = coalesce(excluded.github_username, public.github_connections.github_username);
end;
$$;

grant execute on function public.set_my_github_access_token(text, text) to authenticated;

create or replace function public.get_my_github_access_token()
returns text
language sql
security definer
set search_path = public, vault
as $$
  select s.decrypted_secret
  from public.github_connections c
  join vault.decrypted_secrets s on s.id = c.access_token_id
  where c.user_id = auth.uid();
$$;

grant execute on function public.get_my_github_access_token() to authenticated;

create or replace function public.is_my_github_connected()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (select 1 from public.github_connections where user_id = auth.uid());
$$;

grant execute on function public.is_my_github_connected() to authenticated;
