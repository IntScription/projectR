-- "Level 10k" — rescales the display level from 0-100 to 1-10,000 (100x),
-- so there's real room for the "an achievement every 100 levels" system
-- (100 achievement slots) to mean something. The underlying formula is
-- unchanged and still produces a 0-100 `score` (breakdown components stay
-- intuitive percentages) — `level` is simply that score × 100, floored at
-- 1 rather than defaulting a brand-new profile straight into an
-- already-unlocked-achievement level. Per-skill levels get the same
-- treatment. Nothing about *how* the formula is computed changes here,
-- only the final display scale.
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

  -- `score` stays a plain 0-100 quality figure (the breakdown bars read
  -- naturally as percentages); `level` is the 10,000-scale number shown
  -- everywhere else.
  computed_score := round(
    shipping_score * 0.30 + tech_score * 0.15 + activity_score * 0.20
    + engagement_score * 0.20 + portfolio_score * 0.15
  );
  computed_level := greatest(1, computed_score * 100);

  computed_label := case
    when computed_level >= 7600 then 'Expert'
    when computed_level >= 5100 then 'Advanced'
    when computed_level >= 2600 then 'Intermediate'
    else 'Beginner'
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
  )
  select coalesce(jsonb_agg(
    jsonb_build_object(
      'name', tech,
      'level', greatest(1, round(
        (
          least(shipped_uses::numeric / greatest(proj_uses, 1), 1) * 100 * 0.4
          + least(updates_sum::numeric / greatest(3 * proj_uses, 1), 1) * 100 * 0.2
          + least((likes_sum + comments_sum)::numeric / greatest(10 * proj_uses, 1), 1) * 100 * 0.2
          + least(proj_uses::numeric / 3, 1) * 100 * 0.2
        ) * 100
      )::int),
      'projects', proj_uses
    )
    order by proj_uses desc, tech
  ), '[]'::jsonb)
  into skills_json
  from skill_agg;

  breakdown_json := jsonb_build_array(
    jsonb_build_object('name', 'Shipping rate', 'score', round(shipping_score), 'weight', 30),
    jsonb_build_object('name', 'Tech breadth', 'score', round(tech_score), 'weight', 15),
    jsonb_build_object('name', 'Activity', 'score', round(activity_score), 'weight', 20),
    jsonb_build_object('name', 'Engagement', 'score', round(engagement_score), 'weight', 20),
    jsonb_build_object('name', 'Portfolio size', 'score', round(portfolio_score), 'weight', 15)
  );

  if proj_count = 0 then
    notes_arr := array_append(notes_arr, 'Create your first project to start building your level and skill profile.');
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
