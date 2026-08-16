-- 1:1 direct messages. No participants join table needed: the
-- (user_one_id < user_two_id) ordering check plus a unique index on the
-- pair guarantees exactly one conversation row exists per pair of users,
-- regardless of who starts it — the app just always sorts the two ids
-- before insert/lookup.

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_one_id uuid not null references public.profiles (id) on delete cascade,
  user_two_id uuid not null references public.profiles (id) on delete cascade,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  constraint conversations_distinct_users check (user_one_id <> user_two_id),
  constraint conversations_ordered_pair check (user_one_id < user_two_id)
);

create unique index conversations_unique_pair_idx on public.conversations (user_one_id, user_two_id);
create index conversations_user_one_idx on public.conversations (user_one_id);
create index conversations_user_two_idx on public.conversations (user_two_id);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index messages_conversation_idx on public.messages (conversation_id, created_at);

create or replace function public.touch_conversation_last_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations set last_message_at = new.created_at where id = new.conversation_id;
  return new;
end;
$$;

create trigger messages_touch_conversation after insert on public.messages
  for each row execute function public.touch_conversation_last_message();

-- Backs the Chat tab's unread badge via the same Engagement.count(table:,
-- filters:) helper the Notifications badge already uses — no new counting
-- logic needed client-side.
create view public.unread_messages
with (security_invoker = true) as
select m.id, m.conversation_id, m.sender_id
from public.messages m
join public.conversations c on c.id = m.conversation_id
where m.read_at is null
  and m.sender_id <> auth.uid()
  and (c.user_one_id = auth.uid() or c.user_two_id = auth.uid());

grant select on public.unread_messages to authenticated;

alter table public.conversations enable row level security;
grant select, insert, update on public.conversations to authenticated;

create policy "participants read their conversations" on public.conversations for select
  using (auth.uid() = user_one_id or auth.uid() = user_two_id);
create policy "participants create conversations they're in" on public.conversations for insert
  with check (auth.uid() = user_one_id or auth.uid() = user_two_id);
create policy "participants update their conversations" on public.conversations for update
  using (auth.uid() = user_one_id or auth.uid() = user_two_id);

alter table public.messages enable row level security;
grant select, insert, update on public.messages to authenticated;

create policy "participants read messages in their conversations" on public.messages for select
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id and (c.user_one_id = auth.uid() or c.user_two_id = auth.uid())
    )
  );
create policy "participants send messages as themselves" on public.messages for insert
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id and (c.user_one_id = auth.uid() or c.user_two_id = auth.uid())
    )
  );
create policy "participants mark messages read" on public.messages for update
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id and (c.user_one_id = auth.uid() or c.user_two_id = auth.uid())
    )
  );

-- Required for Postgres Changes realtime — tables aren't included by
-- default just because RLS/grants exist.
alter publication supabase_realtime add table public.messages;
