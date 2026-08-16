-- `messages` never had delete support at all — only select/insert/update
-- (the update grant is itself restricted to the `read_at` column, see
-- 20260813100000_fix_messages_update.sql) were ever granted. Adding
-- "unsend your own message" to chat needs this.
grant delete on public.messages to authenticated;

create policy "senders delete their own messages" on public.messages
  for delete using (auth.uid() = sender_id);
