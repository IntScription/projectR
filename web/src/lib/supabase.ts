import { createClient } from "@supabase/supabase-js";

// Public, anon-key client for the read-only marketing/share surface
// (profile + project pages). RLS grants public SELECT on every table this
// touches, so no session/auth is needed here. An authenticated server client
// gets added when the web app grows account-gated features.
export const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  { auth: { persistSession: false } }
);
