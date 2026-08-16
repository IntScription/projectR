-- likes and follows were the two write-heavy, cheap-to-spam tables left
-- without rate limiting from 20260813160000_rate_limits.sql — a bot can
-- currently mass-like or mass-follow with no friction at all. Same
-- shared `record_rate_limit_event` helper, generous limits since these
-- are meant to be frequent actions (unlike posting a project or a note).
create or replace function public.likes_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.user_id, 'likes', 100, 3600);
  return new;
end;
$$;
drop trigger if exists likes_rate_limit on public.likes;
create trigger likes_rate_limit before insert on public.likes
  for each row execute function public.likes_rate_limit();

create or replace function public.follows_rate_limit() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.record_rate_limit_event(new.follower_id, 'follows', 50, 3600);
  return new;
end;
$$;
drop trigger if exists follows_rate_limit on public.follows;
create trigger follows_rate_limit before insert on public.follows
  for each row execute function public.follows_rate_limit();
