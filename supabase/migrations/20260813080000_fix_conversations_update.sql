-- Security fix: the chat-themes UPDATE policy on conversations had no
-- WITH CHECK, so Postgres fell back to reusing the USING clause as the
-- check — a participant could PATCH the *other* participant's id to any
-- third user (they themselves still matched auth.uid() = user_one_id
-- afterward), hijacking the conversation and its entire message history.
-- Confirmed exploitable via a live REST PATCH against the local DB.
--
-- The policy was only ever meant to let participants set `theme`. A row
-- policy can't cleanly express "this column may change, that one may not"
-- (that needs comparing OLD vs NEW, which RLS expressions can't do
-- directly), so enforce it at the column-grant level instead: only
-- `theme` becomes client-writable, regardless of which rows the policy
-- lets through. `last_message_at` is still maintained by the existing
-- `security definer` trigger (messages_touch_conversation), which runs as
-- the function owner and isn't subject to this grant.
revoke update on public.conversations from authenticated;
grant update (theme) on public.conversations to authenticated;
