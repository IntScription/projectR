// Sends a real APNs push for a notification row, triggered server-side by
// notify_push_on_notification (see 20260813180000_push_notifications.sql)
// via pg_net whenever a new `notifications` row is inserted — the same
// fan-out-on-insert pattern the in-app notification triggers already use,
// just extended to also ring the recipient's phone.
//
// Needs real Apple Push credentials to actually deliver anything:
//   APNS_KEY_ID       - the Key ID of your APNs Auth Key (.p8)
//   APNS_TEAM_ID      - your Apple Developer Team ID
//   APNS_BUNDLE_ID    - com.mrk.projectr (or your bundle id)
//   APNS_PRIVATE_KEY  - the full contents of the .p8 file
//   APNS_ENVIRONMENT  - "production" or "sandbox" (default: sandbox)
// None of these exist until a paid Apple Developer account provides them.
// Without them this function logs and returns 200 (a documented no-op,
// not an error) — the in-app notification already exists regardless, this
// only controls whether a push additionally fires.
//
// Authenticated by a shared secret (PUSH_WEBHOOK_SECRET), not a user JWT —
// the caller is our own Postgres trigger, not a signed-in client. The
// request body only ever carries a notification_id; this function looks
// up the real row (and the recipient's device tokens) itself via the
// service-role key, so even a leaked webhook secret can't be used to
// fabricate arbitrary push content — at most it replays a real,
// already-created notification.

import { createClient } from "npm:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const providedSecret = req.headers.get("x-webhook-secret");
  if (!expectedSecret || providedSecret !== expectedSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  let notificationID: string | undefined;
  try {
    ({ notification_id: notificationID } = await req.json());
  } catch {
    // fall through to the missing-id check below
  }
  if (!notificationID) {
    return new Response(JSON.stringify({ error: "Missing notification_id" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const bundleID = Deno.env.get("APNS_BUNDLE_ID");
  const privateKeyPEM = Deno.env.get("APNS_PRIVATE_KEY");

  if (!keyID || !teamID || !bundleID || !privateKeyPEM) {
    console.log("APNs credentials not configured — skipping push send.");
    return new Response(JSON.stringify({ skipped: true, reason: "apns_not_configured" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  const { data: notification, error: notificationError } = await admin
    .from("notifications")
    .select("*, actor:profiles!notifications_actor_id_fkey(display_name)")
    .eq("id", notificationID)
    .single();

  if (notificationError || !notification) {
    return new Response(JSON.stringify({ error: "Notification not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json" },
    });
  }

  const { data: tokens } = await admin
    .from("device_tokens")
    .select("token")
    .eq("user_id", notification.recipient_id);

  if (!tokens || tokens.length === 0) {
    return new Response(JSON.stringify({ skipped: true, reason: "no_device_tokens" }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  let levelUpLevel: number | null = null;
  if (notification.type === "level_up") {
    const { data: levelRow } = await admin
      .from("profile_levels")
      .select("level")
      .eq("profile_id", notification.recipient_id)
      .single();
    levelUpLevel = levelRow?.level ?? null;
  }

  const { title, body } = messageFor(notification, levelUpLevel);
  const jwt = await signAPNsJWT(keyID, teamID, privateKeyPEM);
  const host =
    Deno.env.get("APNS_ENVIRONMENT") === "production"
      ? "api.push.apple.com"
      : "api.sandbox.push.apple.com";

  const results = await Promise.all(
    tokens.map(async ({ token }) => {
      const response = await fetch(`https://${host}/3/device/${token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": bundleID,
          "apns-push-type": "alert",
        },
        body: JSON.stringify({ aps: { alert: { title, body }, sound: "default" } }),
      });
      return { token, status: response.status };
    })
  );

  return new Response(JSON.stringify({ sent: results }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

function messageFor(
  notification: { type: string; actor: { display_name: string } | null },
  levelUpLevel: number | null
): { title: string; body: string } {
  const actorName = notification.actor?.display_name ?? "Someone";
  switch (notification.type) {
    case "follow":
      return { title: "New follower", body: `${actorName} started following you.` };
    case "like":
      return { title: "New like", body: `${actorName} liked your project.` };
    case "comment":
      return { title: "New comment", body: `${actorName} commented on your project.` };
    case "update":
      return { title: "Project update", body: `${actorName} posted an update.` };
    case "level_up":
      return {
        title: "🎉 Level up!",
        body: levelUpLevel != null ? `You just reached Level ${levelUpLevel}!` : "You just leveled up!",
      };
    default:
      return { title: "ProjectR", body: "You have a new notification." };
  }
}

async function signAPNsJWT(keyID: string, teamID: string, privateKeyPEM: string): Promise<string> {
  const header = { alg: "ES256", kid: keyID };
  const payload = { iss: teamID, iat: Math.floor(Date.now() / 1000) };

  const encoder = new TextEncoder();
  const headerB64 = base64url(encoder.encode(JSON.stringify(header)));
  const payloadB64 = base64url(encoder.encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;

  const key = await importAPNsPrivateKey(privateKeyPEM);
  // Web Crypto's ECDSA signatures are already the raw (r || s) format
  // JWS ES256 expects — no DER-to-raw conversion needed, unlike most
  // non-JS ECDSA libraries.
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput)
  );

  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

async function importAPNsPrivateKey(pem: string): Promise<CryptoKey> {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
