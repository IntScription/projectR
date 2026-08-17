-- 20260826000000_verified_github_connect.sql's `revoke ... from public`
-- turned out to be incomplete: this hosted Supabase project grants
-- EXECUTE on new functions directly to `anon` and `authenticated` via
-- default privileges, not through the `PUBLIC` pseudo-role, so that
-- revoke never touched them. Confirmed via a live grants query against
-- production right after that migration shipped — `authenticated` and
-- `anon` both still had EXECUTE, meaning any client could call
-- set_my_github_access_token with an arbitrary target_user_id and
-- overwrite *any other* user's GitHub connection. This is the real fix.

revoke execute on function public.set_my_github_access_token(uuid, text, text) from authenticated, anon, public;
