-- `set_my_github_access_token` was callable directly by any authenticated
-- client with an arbitrary `token`/`username` pair — nothing verified the
-- token was real or that `username` actually belonged to it, so a client
-- could fabricate a "GitHub connected" state (and the verified checkmark
-- it drives) without ever completing a real GitHub OAuth round trip.
-- RLS already scoped this to the caller's own row, so it was never a
-- cross-user issue, but it meant the badge wasn't actually trustworthy.
--
-- Fix: the function now takes an explicit target_user_id and is callable
-- only by service_role — the new `connect-github` Edge Function is the
-- only caller, and it fetches the real https://api.github.com/user
-- record itself server-side before ever calling this, so the stored
-- username always comes from GitHub, never from client input.

revoke execute on function public.set_my_github_access_token(text, text) from authenticated;
drop function public.set_my_github_access_token(text, text);

create function public.set_my_github_access_token(target_user_id uuid, token text, username text default null)
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  new_secret_id uuid;
  existing_secret_id uuid;
begin
  select access_token_id into existing_secret_id
    from public.github_connections where user_id = target_user_id;

  if existing_secret_id is not null then
    perform vault.update_secret(existing_secret_id, token);
    new_secret_id := existing_secret_id;
  else
    new_secret_id := vault.create_secret(
      token, 'github_access_token:' || target_user_id::text, 'GitHub OAuth access token'
    );
  end if;

  insert into public.github_connections (user_id, access_token_id, github_username)
  values (target_user_id, new_secret_id, username)
  on conflict (user_id) do update set
    access_token_id = excluded.access_token_id,
    github_username = coalesce(excluded.github_username, public.github_connections.github_username);
end;
$$;

-- Postgres grants EXECUTE to PUBLIC by default on newly created
-- functions. That was harmless for the sibling auth.uid()-scoped
-- functions in this file (a caller can only ever read/act on their own
-- row), but this function now trusts an explicit target_user_id
-- parameter instead — without this revoke, any authenticated (or even
-- anon) caller could overwrite *any other* user's GitHub connection by
-- just passing their id, which is worse than the spoofing bug this
-- migration set out to fix.
revoke execute on function public.set_my_github_access_token(uuid, text, text) from public;
grant execute on function public.set_my_github_access_token(uuid, text, text) to service_role;
