-- Backs a proper "Connect GitHub" / "Disconnect" affordance in Settings
-- (previously GitHub only ever got connected reactively, mid-fork-flow).
-- Same pattern as the rest of the github_connections access: no direct
-- table grants, only security definer functions scoped to auth.uid().

create or replace function public.get_my_github_username()
returns text
language sql
security definer
set search_path = public
as $$
  select github_username from public.github_connections where user_id = auth.uid();
$$;

grant execute on function public.get_my_github_username() to authenticated;

create or replace function public.disconnect_my_github()
returns void
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  secret_id uuid;
begin
  select access_token_id into secret_id from public.github_connections where user_id = auth.uid();
  delete from public.github_connections where user_id = auth.uid();
  if secret_id is not null then
    delete from vault.secrets where id = secret_id;
  end if;
end;
$$;

grant execute on function public.disconnect_my_github() to authenticated;
