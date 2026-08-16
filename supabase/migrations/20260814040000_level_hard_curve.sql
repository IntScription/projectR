-- Levels up to 10,000 shouldn't come from a flat ×100 rescale — that just
-- inflates every existing number without anyone doing more work, which
-- feels cheap rather than earned. Instead:
--
--   * Below level 100, `level` is *exactly* the same 0-100 quality score
--     this app has always computed (shipping ratio, tech breadth,
--     activity, engagement, portfolio size — all still capped ratios, all
--     still strictly derived from real projects). A profile with today's
--     level 46 stays at level 46. Nothing about how that number moves
--     changes.
--   * Level 100 itself is genuinely hard to reach: it requires maxing out
--     every one of those five capped ratios at once (100% shipped, full
--     tech breadth, sustained activity, real engagement, a real-size
--     portfolio) simultaneously — a strong, well-rounded profile, not a
--     handful of projects.
--   * Past level 100, the fundamentals are already maxed, so further
--     growth comes from uncapped lifetime totals across those same five
--     signals ("career XP") — every additional shipped project, tech, update,
--     like and comment keeps counting forever, no ceiling. The XP required
--     for each additional level grows faster than the last (a super-linear
--     curve), so climbing from 100 to 1,000 takes real sustained output,
--     and reaching 10,000 (the "Powerlevel10k" max) is a long-haul,
--     hall-of-fame achievement — exactly the kind of thing worth chasing,
--     not something a rescale hands out for free.
create or replace function public.refresh_profile_level(target_profile_id uuid)
returns public.profile_levels
language plpgsql
security definer
set search_path = public
as $$
declare
  proj_count int;
  launched_count int;
  update_count int;
  like_total int;
  comment_total int;
  unique_tech_count int;

  shipping_score numeric;
  tech_score numeric;
  activity_score numeric;
  engagement_score numeric;
  portfolio_score numeric;
  computed_score int;
  career_xp numeric;
  prestige_levels int;
  computed_level int;
  computed_label text;

  skills_json jsonb;
  breakdown_json jsonb;
  notes_arr text[] := '{}';
  result public.profile_levels;
begin
  select count(*), count(*) filter (where status in ('launched', 'maintaining'))
    into proj_count, launched_count
    from public.projects where owner_id = target_profile_id;

  select count(*) into update_count
    from public.project_updates pu
    join public.projects p on p.id = pu.project_id
    where p.owner_id = target_profile_id;

  select
    coalesce(sum(l.like_count), 0), coalesce(sum(c.comment_count), 0)
    into like_total, comment_total
    from public.projects p
    left join lateral (
      select count(*) as like_count from public.likes where project_id = p.id
    ) l on true
    left join lateral (
      select count(*) as comment_count from public.comments where project_id = p.id
    ) c on true
    where p.owner_id = target_profile_id;

  select count(distinct tech) into unique_tech_count
    from public.projects p, unnest(p.tech_stack) as tech
    where p.owner_id = target_profile_id;

  shipping_score := case when proj_count = 0 then 0
    else least(launched_count::numeric / proj_count, 1) * 100 end;
  tech_score := least(unique_tech_count::numeric / 8, 1) * 100;
  activity_score := case when proj_count = 0 then 0
    else least(update_count::numeric / (3 * proj_count), 1) * 100 end;
  engagement_score := case when proj_count = 0 then 0
    else least((like_total + comment_total)::numeric / (10 * proj_count), 1) * 100 end;
  portfolio_score := least(proj_count::numeric / 6, 1) * 100;

  computed_score := round(
    shipping_score * 0.30 + tech_score * 0.15 + activity_score * 0.20
    + engagement_score * 0.20 + portfolio_score * 0.15
  );

  if computed_score < 100 then
    computed_level := greatest(1, computed_score);
  else
    -- Fundamentals maxed — switch to uncapped lifetime totals across the
    -- same five signals, with no ceiling on any of them.
    career_xp :=
      launched_count * 8 + unique_tech_count * 12 + update_count * 3
      + (like_total + comment_total) + proj_count * 10;
    prestige_levels := least(9900, floor(
      power(greatest(career_xp, 0)::double precision / 6.0, 1.0 / 1.3)
    )::int);
    computed_level := 100 + prestige_levels;
  end if;

  computed_label := case
    when computed_level >= 10000 then 'Powerlevel10k'
    when computed_level >= 5000 then 'Legend'
    when computed_level >= 1000 then 'Master'
    when computed_level >= 100 then 'Expert'
    when computed_level >= 76 then 'Advanced'
    when computed_level >= 51 then 'Intermediate'
    when computed_level >= 26 then 'Beginner'
    else 'Newcomer'
  end;

  with project_tech as (
    select p.id as project_id, p.status, tech
    from public.projects p, unnest(p.tech_stack) as tech
    where p.owner_id = target_profile_id
  ),
  project_stats as (
    select
      p.id as project_id,
      coalesce((select count(*) from public.project_updates u where u.project_id = p.id), 0) as update_count,
      coalesce((select count(*) from public.likes l where l.project_id = p.id), 0) as like_count,
      coalesce((select count(*) from public.comments c where c.project_id = p.id), 0) as comment_count
    from public.projects p
    where p.owner_id = target_profile_id
  ),
  skill_agg as (
    select
      pt.tech,
      count(*) as proj_uses,
      count(*) filter (where pt.status in ('launched', 'maintaining')) as shipped_uses,
      coalesce(sum(ps.update_count), 0) as updates_sum,
      coalesce(sum(ps.like_count), 0) as likes_sum,
      coalesce(sum(ps.comment_count), 0) as comments_sum
    from project_tech pt
    join project_stats ps on ps.project_id = pt.project_id
    group by pt.tech
  ),
  skill_scored as (
    select
      tech, proj_uses, shipped_uses, updates_sum, likes_sum, comments_sum,
      round(
        least(shipped_uses::numeric / greatest(proj_uses, 1), 1) * 100 * 0.4
        + least(updates_sum::numeric / greatest(3 * proj_uses, 1), 1) * 100 * 0.2
        + least((likes_sum + comments_sum)::numeric / greatest(10 * proj_uses, 1), 1) * 100 * 0.2
        + least(proj_uses::numeric / 3, 1) * 100 * 0.2
      ) as skill_score
    from skill_agg
  ),
  skill_leveled as (
    select
      tech, proj_uses, skill_score,
      case
        when skill_score < 100 then greatest(1, skill_score::int)
        else 100 + least(9900, floor(
          power(
            greatest(shipped_uses * 10 + updates_sum * 4 + (likes_sum + comments_sum) + proj_uses * 15, 0)
              ::double precision / 5.0,
            1.0 / 1.25
          )
        )::int)
      end as skill_level
    from skill_scored
  )
  select coalesce(jsonb_agg(
    jsonb_build_object('name', tech, 'level', skill_level, 'projects', proj_uses)
    order by proj_uses desc, tech
  ), '[]'::jsonb)
  into skills_json
  from skill_leveled;

  breakdown_json := jsonb_build_array(
    jsonb_build_object('name', 'Shipping rate', 'score', round(shipping_score), 'weight', 30),
    jsonb_build_object('name', 'Tech breadth', 'score', round(tech_score), 'weight', 15),
    jsonb_build_object('name', 'Activity', 'score', round(activity_score), 'weight', 20),
    jsonb_build_object('name', 'Engagement', 'score', round(engagement_score), 'weight', 20),
    jsonb_build_object('name', 'Portfolio size', 'score', round(portfolio_score), 'weight', 15)
  );

  if proj_count = 0 then
    notes_arr := array_append(notes_arr, 'Create your first project to start building your level and skill profile.');
  elsif computed_score >= 100 then
    notes_arr := array_append(notes_arr,
      'Fundamentals maxed. You''re now leveling through lifetime career output — every new shipped project, update, and bit of engagement keeps pushing you toward 10,000.');
  else
    if shipping_score < 50 then
      notes_arr := array_append(notes_arr, format(
        '%s of %s project%s %s still idea/building/testing stage — shipping them would raise your level fastest.',
        proj_count - launched_count, proj_count, case when proj_count = 1 then '' else 's' end,
        case when proj_count - launched_count = 1 then 'is' else 'are' end
      ));
    end if;
    if activity_score < 50 then
      notes_arr := array_append(notes_arr, 'Post more updates on your projects — regular updates are the strongest activity signal.');
    end if;
    if engagement_score < 50 then
      notes_arr := array_append(notes_arr, 'Share your projects to grow likes and comments — engagement is currently your weakest area.');
    end if;
    if tech_score < 50 then
      notes_arr := array_append(notes_arr, 'Try a new language or tool on your next project to broaden your tech breadth.');
    end if;
    if portfolio_score < 50 then
      notes_arr := array_append(notes_arr, 'Start one or two more projects — a bigger portfolio raises your level on its own.');
    end if;
    if array_length(notes_arr, 1) > 2 then
      notes_arr := notes_arr[1:2];
    end if;
  end if;

  insert into public.profile_levels (
    profile_id, level, level_label, score, skills, projects_analyzed, summary,
    breakdown, notes, computed_at
  )
  values (
    target_profile_id, computed_level, computed_label, computed_score, skills_json, proj_count,
    format(
      '%s project%s, %s launched, %s update%s posted.',
      proj_count, case when proj_count = 1 then '' else 's' end,
      launched_count, update_count, case when update_count = 1 then '' else 's' end
    ),
    breakdown_json, notes_arr, now()
  )
  on conflict (profile_id) do update set
    level = excluded.level,
    level_label = excluded.level_label,
    score = excluded.score,
    skills = excluded.skills,
    projects_analyzed = excluded.projects_analyzed,
    summary = excluded.summary,
    breakdown = excluded.breakdown,
    notes = excluded.notes,
    computed_at = excluded.computed_at
  returning * into result;

  return result;
end;
$$;

grant execute on function public.refresh_profile_level(uuid) to authenticated;
