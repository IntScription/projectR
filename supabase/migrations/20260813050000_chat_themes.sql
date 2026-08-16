-- Per-conversation chat themes (Instagram-style: either participant sets
-- it, both see the same one). No new RLS/grants needed — the existing
-- "participants update their conversations" policy and the table-wide
-- UPDATE grant already cover this new column.
alter table public.conversations
  add column theme text not null default 'default';
