-- Reworks `refresh_profile_level` from an ad-hoc point total into a
-- transparent weighted formula: five signals, each normalized to its own
-- 0-100 sub-score against a clearly-defined cap, combined with fixed
-- weights that sum to 1.0 — so the final `score` is itself a 0-100
-- percentage, and every number on screen traces back to a real, visible
-- ratio rather than an arbitrary point value.
--
--   Shipping rate  (30%): launched-or-maintaining projects ÷ total projects
--   Tech breadth   (15%): unique tech_stack entries ÷ 8 (capped at 100%)
--   Activity       (20%): updates posted ÷ (3 × project count)
--   Engagement     (20%): (likes + comments received) ÷ (10 × project count)
--   Portfolio size (15%): project count ÷ 6 (capped at 100%)
--
-- `notes` surfaces the one or two lowest-scoring components as concrete,
-- specific suggestions — still rule-based, not an LLM call.
alter table public.profile_levels add column if not exists breakdown jsonb not null default '[]'::jsonb;
alter table public.profile_levels add column if not exists notes text[] not null default '{}';

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
  tech_list jsonb;

  shipping_score numeric;
  tech_score numeric;
  activity_score numeric;
  engagement_score numeric;
  portfolio_score numeric;
  computed_score int;
  computed_level int;
  computed_label text;

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

  select count(distinct tech), coalesce(jsonb_agg(jsonb_build_object('name', tech, 'projects', cnt) order by cnt desc), '[]'::jsonb)
    into unique_tech_count, tech_list
    from (
      select tech, count(*) as cnt
      from public.projects p, unnest(p.tech_stack) as tech
      where p.owner_id = target_profile_id
      group by tech
      order by cnt desc
      limit 8
    ) t;

  -- Every sub-score is a clean 0-100 ratio against its cap, never negative,
  -- never over 100 (least(...,1) clamps the ratio before scaling to 100).
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

  computed_level := case
    when computed_score >= 75 then 4
    when computed_score >= 50 then 3
    when computed_score >= 25 then 2
    else 1
  end;

  computed_label := case computed_level
    when 4 then 'Expert'
    when 3 then 'Advanced'
    when 2 then 'Intermediate'
    else 'Beginner'
  end;

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
    -- Cap at the two most impactful (lowest-scoring) suggestions rather
    -- than listing every gap at once.
    if array_length(notes_arr, 1) > 2 then
      notes_arr := notes_arr[1:2];
    end if;
  end if;

  insert into public.profile_levels (
    profile_id, level, level_label, score, skills, projects_analyzed, summary,
    breakdown, notes, computed_at
  )
  values (
    target_profile_id, computed_level, computed_label, computed_score, tech_list, proj_count,
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
