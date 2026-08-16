-- The AI-authored portfolio bio, kept deliberately separate from
-- `description` (the user's own words, shown everywhere today) — AI
-- generation is an explicit, reviewable action from the project
-- create/edit flow, never a silent overwrite of something the user wrote.
-- Nullable: most projects won't have one until a user taps "Generate bio
-- with AI."
alter table public.projects add column ai_summary text;
