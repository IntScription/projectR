-- Same bug class as 20260813080000: the messages UPDATE policy has no
-- WITH CHECK, and its USING clause only checks conversation membership —
-- not who sent the message or which columns changed. Either participant
-- could PATCH `body`, `sender_id`, or `conversation_id` on any message in
-- a shared conversation, rewriting the other person's message content.
-- Confirmed exploitable via a live REST PATCH against the local DB.
--
-- The client only ever needs to set `read_at` (see ChatThreadView.markRead
-- in the iOS app). Enforce that at the column-grant level, same fix as
-- conversations.
revoke update on public.messages from authenticated;
grant update (read_at) on public.messages to authenticated;
