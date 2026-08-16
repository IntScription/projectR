# ProjectR

"Project your work." A project-first social network for people who build things — see the
[Blueprint](https://claude.ai/code/artifact/852ca73e-e1ef-459b-b679-bde67745ad16) for the product
vision, MVP build order, and data schema. All 8 build-order phases are implemented: Foundation,
Identity, Projects, Updates, Social graph, Discovery & Feed, Sharing, and Notifications.

## Layout

```
supabase/    Postgres schema (migrations) + local dev config
web/         Next.js app — public profile & project pages (the distribution loop)
ios/         SwiftUI app — XcodeGen-generated, project.yml is the source of truth
```

## Prerequisites

- Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- Node 20+, [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started), Docker (for local Supabase)

## Running locally

**1. Start the local Supabase stack** (applies `supabase/migrations/` automatically):

```sh
supabase start
```

This prints an API URL and anon key. Both the web app and the iOS app need them.

**2. Web app:**

```sh
cd web
cp .env.local.example .env.local   # fill in NEXT_PUBLIC_SUPABASE_URL / ANON_KEY from step 1
npm install
npm run dev
```

Visit `http://localhost:3000/@someusername` or `/p/some-project-slug`.

**3. iOS app:**

```sh
cd ios
cp Config.local.xcconfig.example Config.local.xcconfig   # fill in SUPABASE_URL / ANON_KEY from step 1
xcodegen generate
open ProjectR.xcodeproj
```

`Config.local.xcconfig` is gitignored — every developer (and CI) fills in their own. The
`.xcodeproj` itself is also gitignored and regenerated from `project.yml` by `xcodegen generate`;
re-run it whenever you add/remove source files.

## Sign in with Apple / Google

Both are fully wired and enabled (`supabase/config.toml`'s `[auth.external.apple]` /
`[auth.external.google]`, `DEVELOPMENT_TEAM` set in `ios/project.yml`). Apple's native flow
verifies a real nonce round-trip (`AuthViewModel.prepareAppleSignInRequest` / `signInWithApple`) —
`skip_nonce_check` is deliberately left off for it. Google's SDK integration doesn't generate its
own nonce, so that provider keeps `skip_nonce_check = true`.

If you fork this for your own bundle ID/team, update: `PRODUCT_BUNDLE_IDENTIFIER` and
`DEVELOPMENT_TEAM` in `project.yml`, `client_id` under `[auth.external.apple]` in `config.toml`
(must match your bundle ID exactly — native Sign in with Apple tokens have `aud` = bundle ID, not
a Services ID), and `GOOGLE_CLIENT_ID` / `GOOGLE_REVERSED_CLIENT_ID` in `Config.local.xcconfig`
from your own Google Cloud OAuth client. Restart the stack (`supabase stop && supabase start`)
after any `config.toml` auth change — it isn't picked up live.

Email/password auth works out of the box against local Supabase.

## Sharing: deep links & Universal Links

- The custom scheme `projectr://project/<slug>` and `projectr://profile/<username>` works today,
  no external setup needed — verified via `xcrun simctl openurl`.
- Universal Links (`https://projectr.app/p/<slug>`, `https://projectr.app/@<username>`) need two
  things that don't exist yet: the app deployed to a real domain, and
  `web/public/.well-known/apple-app-site-association` updated with the real Apple Developer Team
  ID (currently a `TEAMID` placeholder). iOS verifies Universal Links by fetching that file over
  HTTPS from the live domain — this cannot be tested locally. The entitlement
  (`applinks:projectr.app`) and the in-app routing (`DeepLinkRouter`) are both already in place.
- `ShareLink` on project/profile screens shares the web URL, built from `SITE_URL` in
  `Config.local.xcconfig` — point it at the deployed site once there is one.

## Notifications

- The in-app notification center is fully real: a `notifications` table is populated by Postgres
  triggers on `follows`/`likes`/`comments`/`project_updates` (fan-out happens server-side, not at
  each app call site), gated by RLS so a user can only ever read or mark-read their own rows —
  they cannot be fabricated client-side (no `INSERT` grant).
- Actual push delivery is not implemented. The client-side half is real — permission request,
  `UIApplication.registerForRemoteNotifications()`, and storing the resulting token in
  `device_tokens` all work — but sending a push needs an APNs key, which needs the same paid Apple
  Developer Program membership already blocking Sign in with Apple, plus a server-side function
  (e.g. a Supabase Edge Function triggered off new `notifications` rows) to actually call APNs.
  That's the next piece once the account exists.

## Account & Settings

- **Delete account is real**, not a stub: `supabase/functions/delete-account` uses the
  service-role key to remove the user's storage objects (`avatars`, `project-media`) and then
  `auth.admin.deleteUser`, which cascades through every table via existing FKs — no separate
  cleanup migration needed. Served locally automatically by `supabase start` once the function
  file exists (restart the stack if you add functions after it's already running — new functions
  aren't picked up live). Test with a **throwaway** account, not your real dev user.
- **Username changes** and **avatar uploads** both go through the same `profiles` row and
  `avatars` bucket set up in the initial migration — no schema changes. The avatar is stored at a
  **fixed path** (`{user_id}/avatar.jpg`, `upsert: true`) so re-uploading replaces it rather than
  accumulating files; the app appends a cache-busting query param to the stored URL so the new
  image actually displays instead of a cached copy of the old one at the same URL.
- **Light/Dark/System** is a plain `@AppStorage("appTheme")` read by `ProjectRApp` and written by
  Settings — no extra plumbing.
- Privacy Policy / Terms of Service (`Features/Settings/`) are **placeholder text**, drafted to be
  reasonable enough to populate the Settings screen for initial App Store review — get real legal
  review before shipping to real users.

## GitHub connect & Download/Fork

- "Download" on a project only appears when the owner marked it **open source** *and* set a
  GitHub URL (`projects.is_open_source` — explicit, not inferred from the URL being set, since a
  project can link a private repo for reference without inviting forks).
- Connecting GitHub is a browser round trip, not a native SDK flow: `GitHubService.connect()` →
  `client.auth.linkIdentity(provider: .github, ...)` opens Safari → GitHub's OAuth consent →
  GoTrue's callback → redirects to `projectr://auth-callback`, caught in `ProjectRApp.onOpenURL` →
  `client.auth.session(from: url)` finishes the exchange. `AuthViewModel`'s existing session-change
  listener then hands the resulting `providerToken` to `GitHubService.captureToken`, which stores
  it in `github_connections` — Supabase doesn't guarantee `providerToken` survives the hourly JWT
  refresh, so it's captured once rather than read from the session later.
- The access token is encrypted at rest via Supabase Vault, not stored as plaintext. The client has
  **no direct table access** to `github_connections` at all (no grants) — every read/write goes
  through `security definer` RPCs (`set_my_github_access_token`, `get_my_github_access_token`,
  `is_my_github_connected`) that hard-check `auth.uid()` server-side rather than trusting a
  client-supplied user id.
- GitHub OAuth App callback URL must be `<API_URL>/auth/v1/callback` (`http://127.0.0.1:54421/auth/v1/callback`
  locally) — update it at github.com/settings/developers if you move to a hosted Supabase project.
  The client secret lives in `supabase/.env` (gitignored, see `.env.example`), referenced from
  `config.toml` via `env(...)` — never committed directly, unlike the client ID which isn't sensitive.

## Chat

- 1:1 direct messages, a 5th tab. No participants join table: `conversations` has a
  `user_one_id < user_two_id` CHECK plus a unique index on the pair, so there's exactly one
  conversation per pair of users regardless of who starts it — the app always sorts the two ids
  (comparing `uuidString`s lexicographically matches Postgres's own uuid byte-ordering) and
  `upsert(onConflict: "user_one_id,user_two_id")`s rather than insert-then-check.
- Realtime is wired for the open thread only (`ChatThreadView` subscribes to `postgres_changes` on
  `messages` filtered by `conversation_id`) — the conversation list refreshes on pull-to-refresh /
  tab reselect rather than subscribing broadly. A fully live list is a reasonable fast-follow, not
  required to make this a real chat feature.
- `messages` had to be added to the `supabase_realtime` publication explicitly
  (`ALTER PUBLICATION ... ADD TABLE`) — RLS and grants alone don't make a table's changes stream.
- The Chat tab's unread badge reads an `unread_messages` view (same `security_invoker` /
  `Engagement.count` pattern the Notifications badge already uses) rather than new counting logic.
- `conversations` and `messages` both only grant `UPDATE` on the one column the client legitimately
  needs to change (`theme`, `read_at`) rather than the whole row. A blanket `UPDATE` grant plus a
  row policy with no matching `WITH CHECK` let a participant `PATCH` *any* column — confirmed
  exploitable (swapping the other participant's id to hijack a conversation; rewriting another
  user's message body) before being fixed this way.

## Welcome page

- Shown before sign-in, not instead of it: `WelcomeView` pushes to `SignInView` via a "Get
  Started" CTA. The centerpiece is a live, auto-scrolling marquee of real trending projects from
  `project_feed` (already public/anon-readable) — three rows driven by `TimelineView(.animation)`
  rather than a restarting `Animation`, so the loop never jump-cuts.
- `supabase/seed.sql` seeds the founder's own real, public GitHub repos (`@IntScription`) as the
  marquee's starting content instead of throwaway smoke-test rows, using GitHub's own dynamically
  generated repo social-preview images (`opengraph.githubassets.com`) as cover art. It looks up the
  `IntScription` profile by username rather than a literal UUID — that profile is the founder's
  real signed-up account, not seed data, and a fixed placeholder UUID collided with a real account
  once already.

## Smart recommendations

- Two SQL-only heuristics, no ML infra: `suggested_profiles()` ("people followed by people you
  follow," falling back to overall follower-count popularity so a brand-new account still gets a
  non-empty list) surfaced as a horizontal row at the top of Discover → Trending, and
  `similar_projects_to_profile()` (other users' projects sharing a category or tag) surfaced as a
  "Similar projects" section at the bottom of any profile page, so a profile visit doesn't dead-end.
- Both are `security invoker` functions (not views, since they take a parameter) callable via
  PostgREST's `/rpc/` endpoint — `client.rpc("fn_name", params: ...)` in the iOS app.

## Face ID app lock

- Opt-in via Settings → "Require Face ID." Separate from the Supabase session entirely — it's a
  local device-unlock gate (`AppLockManager`, `LocalAuthentication`) protecting a phone left
  unlocked, not the account. Locks on `scenePhase == .background`, prompts on return to
  foreground; `deviceOwnerAuthentication` (not the biometrics-only policy) also falls back to the
  passcode, and gracefully no-ops if the device/simulator has no biometrics or passcode enrolled.

## Social feed & profile

- Home and Discover → Trending share one `FeedPostCard` component (creator
  header, cover media, like/comment counts, caption) instead of plain text
  rows — ProjectR has no separate top-level "post" object, so a project
  card doubles as the feed's post unit. None of the five tabs repeat their
  own name as a page heading; the tab bar already says that.
- The Download/fork button never shows on a project you own — forking your
  own repo isn't meaningful for anyone, not just the founder's account.
- Profile header shows username → display name → an optional `role` tag
  (e.g. "ProjectR Developer" — a plain nullable text column, not a
  permissions system) → a GitHub-verified checkmark once `is_github_connected`
  is true for that profile.
- Three icon-only sub-tabs on your **own** profile (Projects, Posts, Saved);
  other people's profiles only get Projects + Posts, since saves are
  private. "Posts" is an Instagram-style grid over `profile_updates_feed`
  (one row per update with its first media item flattened in); "Saved" is
  `saved_projects_feed`, an RLS-scoped join over your own `saves`. Both
  render with `LazyVStack`/`LazyVGrid` directly inside the profile's own
  `ScrollView` rather than a nested `List` — a `List` inside a `ScrollView`
  is a known-broken combination.
- The level/skill dashboard (tap the badge under any profile's bio) is
  entirely rule-based — `refresh_profile_level` scores tech-stack
  diversity, shipped-vs-idea projects, update cadence, and engagement
  directly from existing tables, no external API or key. `get_profile_level`
  lazily recomputes it once a day rather than needing a cron job.

## GitHub connect from Settings & project import

- Settings now has a standalone "Connect GitHub" / "Disconnect" row
  (`GitHubSettingsSection`), not just the reactive prompt that used to only
  appear mid-download on someone else's project. Backed by two more
  `security definer` RPCs (`get_my_github_username`, `disconnect_my_github`)
  following the same auth.uid()-only pattern as the rest of the GitHub
  functions.
- Once connected, `CreateProjectView` offers "Import from GitHub" —
  `GitHubImportSheet` lists the account's own repos
  (`GET /user/repos`) and picking one prefills name, description, tech
  stack (primary language), tags (topics), and the GitHub URL itself,
  instead of typing everything by hand.

## Notes

- A fourth content type, deliberately separate from `project_updates`: a
  `notes` table for short, project-independent public text (closer to a
  tweet than a devlog entry). Posted from a third Add-tab card, shown on
  the author's profile in a new Notes tab — unlike Saved, Notes are public
  and show up on other people's profiles too.

## Post-signup onboarding

- `SuggestedFollowsView` shows right after onboarding, before the signed-in
  app — a brand-new account has nobody to follow yet, so Home's feed and
  Discover → Following would otherwise be empty on first launch. Reuses
  `suggested_profiles`, which already falls back to overall popularity
  when there's no follow graph to walk (exactly this cold-start case).
  Skippable — a nudge, not a gate.

## Realtime beyond chat

- The notification badge (`ProfileView`) and the conversation list
  (`ChatListView`) now subscribe to Postgres changes the same way
  `ChatThreadView` already did for messages, rather than only refreshing
  on tab reselect / pull-to-refresh. `notifications` and `conversations`
  were added to the `supabase_realtime` publication alongside `messages`.

## Collaborators

- Projects can now have collaborators, not just a single owner —
  `project_collaborators` (owner adds/removes, a collaborator can remove
  themselves). Collaborators get the same `project_updates`/`update_media`
  write access an owner has, so real co-authorship (posting updates, not
  just a credits list) works. Surfaced RLS a bug this uncovered: media
  uploads in `PostUpdateView` were keyed to the *project owner's* id, but
  storage RLS requires the path to match the *uploader's* own `auth.uid()`
  — fine when only owners could post updates, broken the moment
  collaborators could too. Fixed by keying the path to the actual
  uploader.

## Rate limiting

- `notes`, `comments`, `projects`, and `messages` inserts are now capped
  per user per time window (10/hr, 30/hr, 5/day, 60/hr respectively) via
  `BEFORE INSERT` triggers backed by a shared `rate_limit_events` log —
  no rate limiting existed before this, fine for a closed beta, not fine
  once this is public.

## Push notifications

- Real APNs delivery, not just the in-app notification center. A
  `notifications` insert now also fires `notify_push_on_notification`
  (via `pg_net`, async — a slow/failing push send can't fail the
  underlying like/follow/comment), which calls the `send-push` Edge
  Function. That function signs its own APNs JWT (ES256, raw Web Crypto —
  deliberately no external JWT library, since the WebCrypto ECDSA
  signature format already matches what JWS ES256 expects) and posts to
  every device token for the recipient.
- **Needs real Apple Push credentials you provide** — `APNS_KEY_ID`,
  `APNS_TEAM_ID`, `APNS_BUNDLE_ID`, `APNS_PRIVATE_KEY` (the full `.p8` file
  contents) in `supabase/.env`, from a paid Apple Developer account
  (Certificates, Identifiers & Profiles → Keys). Until those are set,
  `send-push` logs and returns 200 — a documented no-op, not an error —
  verified end-to-end locally (a real follow → notification →
  trigger → function call, confirmed via `pg_net`'s response log and the
  function's own logs).
- The trigger calls the function at `http://kong:8000/functions/v1/send-push`
  — Kong's internal Docker-network hostname, correct for local dev only.
  A hosted deployment needs this changed to that project's real Edge
  Functions URL.
- Authenticated by a shared `PUSH_WEBHOOK_SECRET` (proves the caller is
  our own trigger, not a real external credential) rather than a user
  JWT, since the caller is Postgres itself. Custom Edge Function secrets
  need explicit declaration under `[edge_runtime.secrets]` in
  `config.toml` — just being in `supabase/.env` isn't enough, unlike the
  handful of reserved vars (`SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`,
  etc.) every function gets automatically.

## Web: Discover

- `/discover` — a real, public, category-filterable browse page reading
  the same `project_feed` view the iOS app's Discover/Trending does, no
  auth needed (matches the existing no-login-wall pattern for profile/
  project pages). A minimal site header (`SiteHeader`) makes it actually
  reachable from every page.
- **Deliberately not built in this pass:** web-side auth and a sign-up
  flow. That's a substantially larger, security-sensitive undertaking
  (session management, protected routes, matching Supabase's SSR auth
  patterns) that deserves its own dedicated pass rather than being rushed
  alongside everything else here.

## Level system: 1-100, and per-skill too

- The overall level is now the 0-100 score itself (clamped to a minimum
  of 1) instead of a coarse 1-4 tier — "level 100 is max," so the number
  shown *is* the formula's output, not a bucket it falls into.
- Skills are no longer typed in anywhere (removed from onboarding and the
  profile header entirely) — `refresh_profile_level` now computes a 1-100
  level *per skill* too, using the same shipping/activity/engagement shape
  as the overall formula but scoped to only the projects using that one
  tech, so two people who both "know Rust" don't get the same number just
  for using it — shipping 3 real Rust projects outranks one idea-stage
  repo. The Level dashboard (tap the badge on any profile) is now the only
  place skills show up.

## Tab bar clearance, for real this time

- The previous fix (`.floatingTabBarClearance()` on pushed screens only)
  turned out incomplete — root tab screens were relying on a blanket
  `.safeAreaInset` on `RootTabView`'s outer `ZStack` that, it turns out,
  wasn't reliable either. Removed that blanket inset entirely and applied
  `.floatingTabBarClearance()` directly to all five tab roots (Home,
  Discover, Add, Chat, Profile) as well as the four pushed screens — every
  scrollable screen now reserves its own clearance, full stop, rather than
  depending on an ancestor to provide it.
- Found and fixed a real bug while in there: `profilePath` existed and was
  read by the swipe-gesture's "am I at this tab's root" check, but was
  never actually bound to the Profile tab's `NavigationStack` — so that
  check was silently always `true` for the Profile tab.

## Project links, auto-enrichment, and editing

- `projects.website_url` (a single fixed field) is now `projects.links`
  (a `label`/`url` array, the same shape `profiles.links` already used) —
  a project can carry a website, an App Store listing, a demo video,
  docs, whatever. `github_url` stays its own column since it drives real
  logic (the fork feature, the GitHub-verified badge), not just display.
- Tech stack is no longer a field anyone types into. Paste a GitHub URL
  (in `CreateProjectView` or the new `EditProjectView`) and ProjectR
  fetches that repo's real language/topics/description via GitHub's
  public API — no auth needed, works for any public repo, not just ones
  the connected account owns — and fills in whatever's still empty
  (description, tags, tech stack). Debounced via `.task(id: githubURL)`
  the same way `AddCollaboratorSheet`'s search-as-you-type already works.
- `WebsiteMetadataService` does the same trick for non-GitHub links —
  real `og:title`/`og:description`/`og:image` tags a site already
  publishes, extracted via targeted regex rather than a full HTML parser
  (meta tags are single, predictable, self-closing elements, not
  something that needs a DOM to read reliably). Never fabricated content,
  never an LLM call — same "real data only" discipline as the level
  formula.
- **`EditProjectView` is new** — projects previously had no way to add a
  cover photo, description, or anything else after creation if it was
  skipped the first time. Owner-only, reachable via a pencil icon on
  `ProjectDetailView`. It auto-offers the photo picker on appear only if
  the project still has no cover — editing an already-covered project
  doesn't re-open it unprompted.
- `ProjectDetailView` was also missing two things entirely until now: the
  project's own cover image (a `mediaGrid` of *update* media existed, but
  the project's own banner was never shown), and any display of its
  links at all. Both added.

## Fixes worth knowing about

- **Floating tab bar clearance only reaches tab roots, not pushed
  screens.** `RootTabView`'s `.safeAreaInset` for the floating bar sits on
  the `ZStack` wrapping all five `NavigationStack`s, which insets each
  stack's root content correctly — but that inset isn't inherited by
  anything reached via `.navigationDestination`, since `NavigationStack`
  manages its own safe-area context for pushed screens. Any pushed screen
  (`ProjectDetailView`, `CreatorProfileView`, `ChatThreadView`,
  `NotificationsView`) needs `.floatingTabBarClearance()`
  (`Core/FloatingTabBarClearance.swift`) applied directly, or its last
  ~80pt of content sits behind the floating bar with no way to scroll it
  into view. Confirmed via a project detail page with enough comments to
  overflow the screen.
- A `NavigationStack` root with 3+ trailing toolbar buttons and no
  `.navigationBarTitleDisplayMode(.inline)` can silently drop one under
  the default large-title layout (less width in the trailing area while
  large). `ProfileView` sets `.inline` explicitly even though it has no
  title text, specifically to keep all three (share/notifications/settings)
  reliably visible.

## Notes

- Auth identity (`auth.users`) and ProjectR identity (`public.profiles`) are deliberately separate
  — a profile is created explicitly during onboarding, not auto-provisioned on signup.
- `saves` (bookmarks) are private to the owner; every other table is publicly readable, matching
  the project-first, no-login-wall sharing model.
- New tables in the `public` schema are **not** auto-exposed to the `anon`/`authenticated` Data
  API roles by default (a recent Supabase change) — the migration grants access explicitly,
  alongside RLS policies. If you add a table, you need both.
