import { cache } from "react";
import { supabase } from "@/lib/supabase";

export type ProjectSummary = {
  id: string;
  slug: string;
  name: string;
  description: string | null;
  cover_image_url: string | null;
  category: string;
  status: string;
  created_at: string;
};

export type TrendingProject = ProjectSummary & {
  owner_username: string;
  owner_display_name: string;
  owner_avatar_url: string | null;
  like_count: number;
  comment_count: number;
};

export type Profile = {
  id: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
  bio: string | null;
  skills: string[];
  links: { label: string; url: string }[];
};

export type ProjectUpdate = {
  id: string;
  body: string;
  created_at: string;
};

export type ProjectDetail = ProjectSummary & {
  tags: string[];
  tech_stack: string[];
  github_url: string | null;
  links: { label: string; url: string }[];
  view_count: number;
  owner: Pick<Profile, "username" | "display_name" | "avatar_url">;
  project_media: { id: string; type: string; url: string; position: number }[];
  project_updates: ProjectUpdate[];
};

// Memoized per-request so generateMetadata and the page component sharing
// the same lookup only hit Supabase once.
export const getProfileByUsername = cache(async (username: string) => {
  const { data: profile } = await supabase
    .from("profiles")
    .select("id, username, display_name, avatar_url, bio, skills, links")
    .eq("username", username)
    .maybeSingle<Profile>();

  if (!profile) return null;

  const { data: projects } = await supabase
    .from("projects")
    .select("id, slug, name, description, cover_image_url, category, status, created_at")
    .eq("owner_id", profile.id)
    .order("created_at", { ascending: false })
    .returns<ProjectSummary[]>();

  return { profile, projects: projects ?? [] };
});

const CATEGORIES = [
  "software",
  "ai",
  "games",
  "design",
  "music",
  "art",
  "hardware",
  "writing",
  "research",
  "other",
] as const;
export type Category = (typeof CATEGORIES)[number];
export { CATEGORIES };

// Same `project_feed` view the iOS app's Discover/Trending reads —
// already public/anon-readable, so this needs no auth on the web side
// either. Not memoized like the other two: this is meant to feel live on
// every visit, not cached per-request the way a single profile/project
// lookup shared between generateMetadata and the page component is.
export async function getTrendingProjects(category?: Category) {
  let query = supabase
    .from("project_feed")
    .select(
      "id, slug, name, description, cover_image_url, category, status, created_at, owner_username, owner_display_name, owner_avatar_url, like_count, comment_count"
    )
    .order("trending_score", { ascending: false })
    .limit(30);

  if (category) query = query.eq("category", category);

  const { data } = await query.returns<TrendingProject[]>();
  return data ?? [];
}

export const getProjectBySlug = cache(async (slug: string) => {
  const { data } = await supabase
    .from("projects")
    .select(
      `id, slug, name, description, cover_image_url, category, status, tags,
       tech_stack, github_url, links, view_count, created_at,
       owner:profiles!projects_owner_id_fkey ( username, display_name, avatar_url ),
       project_media ( id, type, url, position ),
       project_updates ( id, body, created_at )`
    )
    .eq("slug", slug)
    .order("position", { referencedTable: "project_media", ascending: true })
    .order("created_at", { referencedTable: "project_updates", ascending: false })
    .maybeSingle<ProjectDetail>();

  return data;
});
