-- Achievements gain a real notification the moment someone crosses into a
-- new 100-level tier (100, 200, ... 10,000) — both in-app (via the normal
-- notifications table every other feature already uses) and, once real
-- APNs credentials exist, as a push. Reuses the exact same fan-out
-- mechanism as follows/likes/comments: insert into `notifications`,
-- `notifications_send_push` (already unconditional on `type`) does the
-- rest with zero new trigger plumbing.
alter type notification_type add value 'level_up';
