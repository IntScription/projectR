// Fallback tier for AI project-bio generation — the primary tier is fully
// on-device via Apple's FoundationModels framework
// (`Core/AI/ProjectBioGenerator.swift`), used whenever
// `SystemLanguageModel.default.availability` reports available (needs
// Apple-Intelligence-eligible hardware + iOS 26+ + the feature enabled).
// This function exists for everyone else — older devices, non-eligible
// hardware, or Apple Intelligence turned off — so "Generate bio with AI"
// works the same regardless of device.
//
// Called directly by a signed-in user tapping that button in the
// project create/edit flow — a real client action, not a server-triggered
// job, so this uses Supabase's normal JWT verification (verify_jwt stays
// at its default `true`; no shared-secret header like send-push or
// capture-repo-snapshots need, since a caller here already has to be a
// real authenticated user).
//
// Never writes anything itself — the client shows the returned bio for
// review and only persists it to `projects.ai_summary` on explicit save,
// so nothing generated here can land in a portfolio PDF unseen.

const ANTHROPIC_MODEL = "claude-sonnet-4-5";

interface ProjectBioRequest {
  name: string;
  category: string;
  status: string;
  tags: string[];
  techStack: string[];
  description?: string | null;
  repoDescription?: string | null;
}

Deno.serve(async (req) => {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "AI bio generation isn't configured on this server yet." }), {
      status: 503,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: ProjectBioRequest;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid request body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }
  if (!body.name) {
    return new Response(JSON.stringify({ error: "Missing project name" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const facts = [
    `Name: ${body.name}`,
    `Category: ${body.category}`,
    `Status: ${body.status}`,
    body.techStack.length > 0 ? `Tech stack: ${body.techStack.join(", ")}` : null,
    body.tags.length > 0 ? `Tags: ${body.tags.join(", ")}` : null,
    body.description ? `Existing description (from the creator): ${body.description}` : null,
    body.repoDescription ? `GitHub repository description: ${body.repoDescription}` : null,
  ]
    .filter(Boolean)
    .join("\n");

  const response = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: ANTHROPIC_MODEL,
      max_tokens: 300,
      system:
        "You write short, factual project bios for developer portfolios. Write 2-3 sentences " +
        "covering what the project is and its real tech stack, based strictly on the facts given. " +
        "Never invent metrics, claims, or details not present in the facts. No marketing language, " +
        "no emoji, no headings — plain prose only.",
      messages: [{ role: "user", content: `Project facts:\n${facts}` }],
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    console.error("Anthropic API error:", response.status, errorText);
    return new Response(JSON.stringify({ error: "Couldn't generate a bio right now." }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  const result = await response.json();
  const bio = result.content?.[0]?.text?.trim();
  if (!bio) {
    return new Response(JSON.stringify({ error: "Couldn't generate a bio right now." }), {
      status: 502,
      headers: { "Content-Type": "application/json" },
    });
  }

  return new Response(JSON.stringify({ bio }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
