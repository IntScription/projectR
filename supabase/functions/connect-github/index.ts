// Stores a GitHub connection only after verifying the token server-side —
// the client hands over the raw OAuth token it got from `linkIdentity`,
// but never gets to claim its own username for it. This function fetches
// https://api.github.com/user itself with that token and only trusts
// whatever GitHub reports back, so `github_connections.github_username`
// (and the verified checkmark it drives, see `is_github_connected`) can
// never be spoofed by calling the storage RPC directly with a made-up
// username — see 20260826000000_verified_github_connect.sql, which also
// locks `set_my_github_access_token` down to service_role only.
//
// Same two-client pattern as delete-account: `caller` only ever answers
// "who is asking" from their own JWT; `admin` (service-role) is the only
// thing allowed to write the connection.

import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { token } = await req.json().catch(() => ({ token: null }));
  if (typeof token !== "string" || token.length === 0) {
    return new Response(JSON.stringify({ error: "Missing token" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const caller = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const {
    data: { user },
    error: userError,
  } = await caller.auth.getUser();
  if (userError || !user) {
    return new Response(JSON.stringify({ error: "Not authenticated" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // The only source of truth for the username — never trust anything the
  // client claims about which GitHub account this token belongs to.
  const githubResponse = await fetch("https://api.github.com/user", {
    headers: { Authorization: `Bearer ${token}`, "User-Agent": "ProjectR-App" },
  });
  if (!githubResponse.ok) {
    return new Response(JSON.stringify({ error: "Could not verify this token with GitHub" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  const githubUser = await githubResponse.json();
  const username = typeof githubUser.login === "string" ? githubUser.login : null;

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { error: rpcError } = await admin.rpc("set_my_github_access_token", {
    target_user_id: user.id,
    token,
    username,
  });
  if (rpcError) {
    return new Response(JSON.stringify({ error: rpcError.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ username }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
