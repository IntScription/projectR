-- Likes/comments/project-update notifications already exist. Missing:
-- someone you follow shipping a brand-new project, or posting a note —
-- both currently invisible unless you happen to scroll past them.
alter type notification_type add value 'new_project';
alter type notification_type add value 'note';

alter table public.notifications add column note_id uuid references public.notes (id) on delete cascade;

-- New project → notify everyone following its owner. (Unlike
-- notify_on_update, there's no "following the project directly" case yet
-- — the project didn't exist a moment ago for anyone to have followed.)
create or replace function public.notify_on_new_project()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (recipient_id, actor_id, type, project_id)
  select f.follower_id, new.owner_id, 'new_project'::notification_type, new.id
  from public.follows f
  where f.followee_profile_id = new.owner_id
    and f.follower_id <> new.owner_id;
  return new;
end;
$$;

create trigger projects_notify_new after insert on public.projects
  for each row execute function public.notify_on_new_project();

create or replace function public.notify_on_new_note()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (recipient_id, actor_id, type, note_id)
  select f.follower_id, new.author_id, 'note'::notification_type, new.id
  from public.follows f
  where f.followee_profile_id = new.author_id
    and f.follower_id <> new.author_id;
  return new;
end;
$$;

create trigger notes_notify_new after insert on public.notes
  for each row execute function public.notify_on_new_note();
