-- Local dev seed data. Runs after migrations on `supabase db reset`.
--
-- Showcases the founder's own real, public GitHub projects on the Welcome
-- page marquee instead of throwaway smoke-test rows — real content, not
-- placeholder data, for what's meant to be the product's own first
-- impression. `cover_image_url` is deliberately left null: GitHub's
-- auto-generated repo social-preview images bake "owner/repo-name" plus
-- language/stats text directly into the picture, which reads as cluttered
-- at marquee-card size next to the name/creator text already shown below
-- each card — the clean gradient-placeholder card (same one every project
-- without a real cover image gets) reads better small.
--
-- Deliberately does NOT create the `IntScription` profile itself: that's
-- the founder's own real signed-up account (created through the app, not
-- seed data), and a fresh `db reset` won't have it yet either — these
-- inserts are a no-op until that profile exists, rather than fabricating a
-- placeholder account with a guessed id that could collide with a real one
-- (this bit us once already; see the owner_id lookup below instead of a
-- literal UUID).
insert into public.projects (
  owner_id, slug, name, description, category, tags,
  status, tech_stack, github_url, website_url, is_open_source
)
select owner.id, v.slug, v.name, v.description,
  v.category::project_category, v.tags, v.status::project_status, v.tech_stack,
  v.github_url, v.website_url, v.is_open_source
from (values
  (
    'rundeck', 'RunDeck', 'RunDeck - Personal Project Dashboard', 'software',
    array['lazyvim', 'rust', 'terminal', 'terminal-app', 'tmux', 'tui-app'],
    'launched', array['Rust'], 'https://github.com/IntScription/rundeck',
    null, true
  ),
  (
    'rest-assured', 'Rest Assured', 'Rest Assured – Train hard. Track smarter.', 'software',
    array[]::text[], 'launched', array['TypeScript'],
    'https://github.com/IntScription/rest-assured',
    'https://rest-assured-rho.vercel.app', true
  ),
  (
    'terminal-portfolio', 'Terminal Portfolio', 'This is my terminal-styled portfolio.', 'software',
    array['portfolio-website', 'terminal-portfolio-website', 'website'],
    'launched', array['TypeScript'], 'https://github.com/IntScription/terminal-portfolio',
    'https://terminal-portfolio-eight-theta.vercel.app', true
  ),
  (
    'devlog', 'Devlog', 'My Devlog', 'software',
    array['devlog', 'lazyvim', 'markdown', 'neovim'],
    'launched', array['Python'], 'https://github.com/IntScription/devlog',
    'https://intscription.github.io/devlog/', true
  )
) as v(slug, name, description, category, tags, status, tech_stack, github_url, website_url, is_open_source)
cross join (select id from public.profiles where username = 'IntScription' limit 1) as owner
on conflict (slug) do update set
  owner_id = excluded.owner_id,
  name = excluded.name,
  description = excluded.description,
  cover_image_url = null,
  category = excluded.category,
  tags = excluded.tags,
  status = excluded.status,
  tech_stack = excluded.tech_stack,
  github_url = excluded.github_url,
  website_url = excluded.website_url,
  is_open_source = excluded.is_open_source;

-- Founder badge — shown next to the name on the profile header. Only ever
-- set for the one real account it's true for; every other profile's
-- `role` stays null.
update public.profiles set role = 'ProjectR Developer' where username = 'IntScription';
