-- Only `messages` was ever added to the realtime publication — the
-- notification badge and the conversation list were poll-based (refresh on
-- tab reselect / pull-to-refresh) rather than live, unlike chat threads.
-- Extends the same Realtime pattern already proven out in ChatThreadView
-- to both.
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.conversations;
