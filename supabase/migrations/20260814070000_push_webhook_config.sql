-- The original push-notification trigger hardcoded a local-only URL
-- (`http://kong:8000`, Docker's internal hostname for the local Kong
-- gateway — meaningless outside `supabase start`) and the webhook secret
-- directly in the migration's SQL text. Neither survives shipping this
-- migration to a real hosted project: the URL needs to be that project's
-- real Functions endpoint, and a secret baked into a migration file is a
-- secret sitting in git history forever.
--
-- Fix: read both from a plain key/value settings table instead — same
-- function body everywhere, but the actual values are seeded
-- per-environment via a direct INSERT (local vs. production), never
-- committed. (`ALTER DATABASE ... SET` on a custom GUC was the first
-- instinct here, but Supabase's `postgres` role isn't actually a real
-- superuser even locally, so that's not an option — same table-backed
-- "app settings" pattern `rate_limit_events` already uses: no RLS, no
-- grants, touched only by `security definer` functions.)
create table public.app_settings (
  key text primary key,
  value text not null
);

create or replace function public.notify_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
declare
  function_url text;
  webhook_secret text;
begin
  select value into function_url from public.app_settings where key = 'push_function_url';
  select value into webhook_secret from public.app_settings where key = 'push_webhook_secret';

  if function_url is null or webhook_secret is null then
    raise warning 'push_function_url/push_webhook_secret not configured on this database — skipping push send for notification %', new.id;
    return new;
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', webhook_secret
    ),
    body := jsonb_build_object('notification_id', new.id)
  );
  return new;
end;
$$;
