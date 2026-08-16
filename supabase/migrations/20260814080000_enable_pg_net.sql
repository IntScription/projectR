-- pg_net (used by notify_push_on_notification, notify_on_follow's siblings,
-- etc. for async HTTP calls out to Edge Functions) was never actually
-- created by a migration — it just happens to ship pre-enabled on the
-- local Docker dev image, which silently hid that this was missing until
-- the exact same trigger failed with "schema net does not exist" against
-- the real hosted production project.
create extension if not exists pg_net schema extensions;
