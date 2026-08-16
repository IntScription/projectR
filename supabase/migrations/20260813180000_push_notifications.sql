-- Fires the send-push Edge Function whenever a new notification is
-- created — same server-side fan-out pattern as notify_on_follow /
-- notify_on_update, just one more trigger doing one more thing on the
-- same insert, not a new mechanism. Uses pg_net (async, non-blocking —
-- the notification insert itself never waits on the HTTP call, so a slow
-- or failing push send can't fail the underlying like/follow/comment).
--
-- The webhook secret is a fixed internal value here (see
-- supabase/.env's PUSH_WEBHOOK_SECRET comment) — it proves the request
-- came from this trigger, not a real external credential. Real push
-- delivery is still gated on the APNs secrets configured in send-push's
-- own environment, which don't exist until a paid Apple Developer account
-- provides them.
create or replace function public.notify_push_on_notification()
returns trigger
language plpgsql
security definer
set search_path = public, net
as $$
begin
  perform net.http_post(
    url := 'http://kong:8000/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', 'b3ac83d671c73dd4f8524252ac890b0dec914b9b1ff1e58b09e7be98f5b0403c'
    ),
    body := jsonb_build_object('notification_id', new.id)
  );
  return new;
end;
$$;

create trigger notifications_send_push after insert on public.notifications
  for each row execute function public.notify_push_on_notification();
