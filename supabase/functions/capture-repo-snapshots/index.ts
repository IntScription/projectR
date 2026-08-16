// Weekly capture of the one thing GitHub's REST API doesn't expose
// historically: point-in-time repo metadata (stars/open-issues/forks/
// watchers). Everything else `ForgeRepoInsightsView` shows (commit
// activity, code frequency, contributors, punch card) is fetched live
// from GitHub's own Stats API instead — it's already bucketed by week and
// kept refreshed server-side, so duplicating it here would just be
// reinventing something already authoritative.
//
// Triggered by pg_cron via pg_net (see
// 20260819000000_repo_analytics_snapshots.sql's
// capture_repo_snapshots_trigger, scheduled Mondays 4am) rather than an
// insert — same "shared secret, not a user JWT" auth as send-push, and
// the same `app_settings`-backed URL/secret pattern
// push_webhook_config.sql introduced (a URL/secret baked into a migration
// doesn't survive shipping to a real hosted project).
//
// Unauthenticated GitHub requests only (same no-auth approach
// `GitHubService.publicMetadata` already uses client-side) — private
// repos are silently skipped, not a failure. That also means this is
// capped at GitHub's 60 req/hour unauthenticated rate limit; fine at
// today's scale, would need a service-account token if the number of
// project-linked repos grows enough to matter.

import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const expectedSecret = Deno.env.get("REPO_SNAPSHOT_WEBHOOK_SECRET");
  const providedSecret = req.headers.get("x-webhook-secret");
  if (!expectedSecret || providedSecret !== expectedSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data: projects, error: projectsError } = await admin
    .from("projects")
    .select("github_url")
    .not("github_url", "is", null);

  if (projectsError) {
    return new Response(JSON.stringify({ error: projectsError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const githubURLs = [...new Set((projects ?? []).map((p) => p.github_url as string))];
  const capturedAt = new Date().toISOString().slice(0, 10);

  const results = await Promise.all(
    githubURLs.map(async (githubURL) => {
      const ownerRepo = parseOwnerRepo(githubURL);
      if (!ownerRepo) return { githubURL, skipped: "unparseable_url" };

      const response = await fetch(`https://api.github.com/repos/${ownerRepo.owner}/${ownerRepo.repo}`, {
        headers: { Accept: "application/vnd.github+json", "User-Agent": "ProjectR-App" },
      });
      if (!response.ok) {
        return { githubURL, skipped: `github_status_${response.status}` };
      }
      const repo = await response.json();

      const { error: upsertError } = await admin
        .from("repo_analytics_snapshots")
        .upsert(
          {
            github_url: githubURL,
            captured_at: capturedAt,
            stars: repo.stargazers_count ?? 0,
            open_issues: repo.open_issues_count ?? 0,
            forks: repo.forks_count ?? 0,
            // `watchers_count` mirrors `stargazers_count` due to a
            // long-standing GitHub API quirk — `subscribers_count` is the
            // field that actually means "people watching for
            // notifications."
            watchers: repo.subscribers_count ?? 0,
          },
          { onConflict: "github_url,captured_at" }
        );

      return upsertError ? { githubURL, error: upsertError.message } : { githubURL, captured: true };
    })
  );

  return new Response(JSON.stringify({ results }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

function parseOwnerRepo(githubURL: string): { owner: string; repo: string } | null {
  try {
    const url = new URL(githubURL);
    const parts = url.pathname.split("/").filter(Boolean);
    if (parts.length < 2) return null;
    const repo = parts[1].endsWith(".git") ? parts[1].slice(0, -4) : parts[1];
    return { owner: parts[0], repo };
  } catch {
    return null;
  }
}
