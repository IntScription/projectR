-- Projects only ever had one fixed "website" link alongside github_url.
-- Replaces it with a flexible label+url array — the same shape
-- public.profiles.links already uses — so a project can carry a website,
-- an App Store listing, a demo video, docs, whatever, instead of being
-- limited to exactly one extra link. github_url stays its own column
-- (unchanged) since it drives real logic (the fork/download feature,
-- the GitHub-verified badge), not just display.
alter table public.projects add column links jsonb not null default '[]'::jsonb;

update public.projects
set links = jsonb_build_array(jsonb_build_object('label', 'Website', 'url', website_url))
where website_url is not null and website_url <> '';

alter table public.projects drop column website_url;
