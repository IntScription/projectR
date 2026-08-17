# ProjectR

**"Project your work."** A project-first social network for developers and indie hackers.
The atomic unit is the *project*, not the person — there's no generic feed of posts about
nothing. Every update, comment, and piece of media belongs to something you're actually building.

- 📱 **iOS app** — submitted to the App Store, currently in review
- 🌐 **Web** — public profile and project pages, live at the deployed site (see [Deployment](#deployment))
- 📄 **License** — [MIT](./LICENSE)

## Why it's different

Most places to show your work are either a code host (GitHub — no audience), a generic feed
(LinkedIn/Twitter — no project structure), or a one-time launch (Product Hunt — no ongoing
record). ProjectR combines a real dev workspace with a social graph built around *what you've
shipped*, not who you follow:

- **Forge** — a real dev workspace inside the app. Connect GitHub to browse commits, branches,
  and pull requests, share a commit or PR straight into chat as a tappable card, or work against a
  cloned local copy of a repo (Rust/`gix`-backed) without ever leaving ProjectR.
- **Levels that mean something** — your level (1–10,000, uncapped past 100) is computed entirely
  from real signals: shipped projects, tech-stack breadth, update cadence, and engagement — never
  a follower count. Per-skill levels work the same way, scoped to only the projects using that
  tech.
- **Portfolio PDF** — generate a real, polished PDF from your best projects: auto-filled bios (on
  device via Apple Intelligence where available, a server fallback otherwise), real GitHub stats,
  ready to attach to a job application.
- **No login wall for sharing.** Every profile and project page is publicly readable and rendered
  server-side on the web — a shared link works for anyone, not just other ProjectR users.

## Features

- **Projects** — creation, editing, updates, comments, likes, saves (private bookmarks), and
  collaborators (not just a single owner).
- **Social** — following, a following/trending feed, Discover with category filters, notifications
  (in-app + real APNs push), 1:1 direct messages with realtime delivery.
- **Stories** — 24-hour stories plus permanent Highlights, shown on both your own and visited
  profiles.
- **Forge** — GitHub OAuth connect (server-verified — the token is checked against GitHub's own
  `/user` API before anything is trusted, so the verified badge can't be spoofed), commit/branch/PR
  browsing, repo insights (commit activity, code frequency, contributors, punch card), local git
  via a Rust core, weekly star-history snapshots.
- **Moderation** — blocking, reporting, and an admin review queue, all backed by real RLS policies.
- **Accounts** — Sign in with Apple/Google/email, Face ID app lock, real account deletion (not a
  stub — actually removes storage objects and cascades through every table), crash reporting
  (Sentry), self-hosted feature-usage analytics (never sold, never shared, no ad networks).

## Architecture

```
supabase/    Postgres schema (migrations), Edge Functions, local dev config
web/         Next.js app — public profile & project pages (the distribution loop)
ios/         SwiftUI app — XcodeGen-generated, project.yml is the source of truth
forge-core/  Rust crate (gix-backed local git) — compiled to an XCFramework for iOS
```

- **Backend**: Supabase (Postgres + Auth + Storage + Realtime + Edge Functions), everything gated
  by RLS — no separate API layer.
- **iOS**: SwiftUI, Swift 6 strict concurrency, XcodeGen (`project.yml` is the only source of
  truth for the Xcode project — never edit `.xcodeproj` directly).
- **Web**: Next.js (App Router), server-rendered, deployed on Vercel.
- **Forge core**: Rust (`gix` for git operations), exposed to Swift via `uniffi` as an XCFramework.

## Getting started

### Prerequisites

- Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Node 20+
- [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), Docker
  (for local Supabase)

### 1. Start the local backend

```sh
supabase start
```

Applies every migration in `supabase/migrations/` automatically and prints an API URL + anon key —
both the web app and the iOS app need these.

### 2. Web app

```sh
cd web
cp .env.local.example .env.local   # fill in NEXT_PUBLIC_SUPABASE_URL / ANON_KEY from step 1
npm install
npm run dev
```

Visit `http://localhost:3000/@someusername` or `/p/some-project-slug`.

### 3. iOS app

```sh
cd ios
cp Config.local.xcconfig.example Config.local.xcconfig   # fill in SUPABASE_URL / ANON_KEY from step 1
xcodegen generate
open ProjectR.xcodeproj
```

`Config.local.xcconfig` and `Config.production.xcconfig` are both gitignored — every developer
(and CI) fills in their own. The `.xcodeproj` itself is also gitignored and regenerated from
`project.yml` by `xcodegen generate`; re-run it whenever you add or remove source files.

### Running tests

```sh
cd ios && xcodebuild test -scheme ProjectRTests
cd forge-core && cargo test
```

## Sign in with Apple / Google

Both are fully wired (`supabase/config.toml`'s `[auth.external.apple]` / `[auth.external.google]`,
`DEVELOPMENT_TEAM` set in `ios/project.yml`). Apple's native flow verifies a real nonce round-trip;
Google's SDK integration keeps `skip_nonce_check = true` since it doesn't generate its own nonce.
Email/password auth works out of the box against local Supabase.

If you fork this for your own bundle ID/team, update `PRODUCT_BUNDLE_IDENTIFIER` and
`DEVELOPMENT_TEAM` in `project.yml`, the Apple `client_id` in `config.toml` (must match your bundle
ID exactly), and your own Google OAuth client in `Config.local.xcconfig`. Restart the stack
(`supabase stop && supabase start`) after any `config.toml` auth change.

## Deployment

- **Web** is deployed on Vercel, connected to this repo's `main` branch. Production environment
  variables (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) are set directly on the
  Vercel project, not read from `.env.local` (which stays local-only, pointed at local Supabase).
- **iOS** ships via `Config.production.xcconfig` (gitignored, points at the real hosted Supabase
  project). Universal Links and the `SITE_URL` used for `ShareLink` both point at wherever the web
  app is actually live — update both together if you move to a custom domain.
- Production Supabase secrets (APNs credentials, GitHub OAuth secret, webhook secrets, Sentry DSN,
  Anthropic API key for the AI-bio fallback tier) are managed via `supabase secrets set`, never
  committed — see `supabase/.env.example` for the full list of what's expected.

## Security notes worth knowing

- `github_connections` (the OAuth token behind the GitHub-verified badge) has **no direct client
  table access at all**. Every read/write goes through `security definer` RPCs that hard-check
  `auth.uid()` server-side, and the token-storage RPC is further locked to `service_role` only —
  a dedicated Edge Function (`connect-github`) fetches the real GitHub `/user` record itself before
  ever writing anything, so the verified badge can't be spoofed by calling the RPC directly with a
  fabricated username.
- New tables in the `public` schema are **not** auto-exposed to the `anon`/`authenticated` Data API
  roles by default. Migrations grant access explicitly alongside RLS policies — if you add a table,
  you need both.
- Postgres grants `EXECUTE` to `PUBLIC` on new functions by default, and this project's hosted
  Supabase setup separately grants `anon`/`authenticated` by default too — any `security definer`
  function that trusts an explicit id parameter instead of `auth.uid()` needs an explicit `REVOKE`,
  or it's callable by anyone regardless of role-based reasoning that looks safe on paper.

## License

[MIT](./LICENSE) © 2026 Kartik Sanil
