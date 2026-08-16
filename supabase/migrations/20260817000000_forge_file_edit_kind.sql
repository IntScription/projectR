-- Forge's single-file editor commits a change straight to a task's branch;
-- this lets that action post a normal project_updates activity row the
-- same way branch_created/pr_opened already do.
alter table public.project_updates drop constraint project_updates_kind_check;
alter table public.project_updates add constraint project_updates_kind_check
  check (kind in ('manual', 'branch_created', 'pr_opened', 'pr_merged', 'file_edited'));
