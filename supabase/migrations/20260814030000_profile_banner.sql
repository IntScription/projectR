-- LinkedIn-style cover banner for the profile header. Stored in the same
-- `avatars` bucket as the avatar image (path `{profile_id}/banner.jpg`) —
-- the existing storage RLS already restricts writes to a path prefixed
-- with the uploader's own auth.uid(), so no new storage policy is needed.
alter table public.profiles
  add column if not exists banner_url text;
