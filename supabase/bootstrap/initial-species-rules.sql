-- Run manually in the DEVELOPMENT project's SQL Editor after initial-team.sql.
-- Safe to rerun: existing species, age classes, and rules are not overwritten.
-- Kronhjort is quota-based, but quota categories/counts are omitted until the
-- hunting leadership supplies current hjort/hind/kalv values.

do $seed$
declare
  v_team_id uuid;
  v_season_id uuid;
  v_mark_id uuid;
  age_seed record;
begin
  select id into strict v_team_id
  from public.teams
  where name = 'Fän Jaktlag';

  select id into strict v_season_id
  from public.seasons
  where seasons.team_id = v_team_id
    and label = '2026/2027';

  select id into strict v_mark_id
  from public.marks
  where marks.team_id = v_team_id
    and name = 'Fän';

  insert into public.species (team_id, name, can_observe, can_harvest)
  values
    (v_team_id, 'Rådjur', true, true),
    (v_team_id, 'Dovhjort', true, true),
    (v_team_id, 'Kronhjort', true, true),
    (v_team_id, 'Vildsvin', true, true),
    (v_team_id, 'Älg', true, true)
  on conflict do nothing;

  for age_seed in
    select species.name as species_name,
           age_class.age_name,
           age_class.sort_order
    from (values
      ('Rådjur', 'Kid', 1),
      ('Dovhjort', 'Kalv', 1),
      ('Kronhjort', 'Kalv', 1),
      ('Vildsvin', 'Kulting', 1),
      ('Älg', 'Kalv', 1)
    ) as age_class(species_name, age_name, sort_order)
    join public.species species
      on species.team_id = v_team_id
     and species.name = age_class.species_name
  loop
    insert into public.species_age_classes (
      team_id, species_id, name, sort_order
    )
    select v_team_id, species.id, age_seed.age_name, age_seed.sort_order
    from public.species species
    where species.team_id = v_team_id
      and species.name = age_seed.species_name
    on conflict (species_id, name) do nothing;
  end loop;

  insert into public.mark_species_rules (
    team_id, season_id, mark_id, species_id, mode, guidance
  )
  select v_team_id,
         v_season_id,
         v_mark_id,
         species.id,
         rule.mode::public.rule_mode,
         rule.guidance
  from (values
    ('Rådjur', 'open', 'Jägarmässigt'),
    ('Dovhjort', 'open', 'Jägarmässigt'),
    ('Vildsvin', 'open', 'Jägarmässigt'),
    ('Kronhjort', 'quota', null),
    ('Älg', 'closed', null)
  ) as rule(species_name, mode, guidance)
  join public.species species
    on species.team_id = v_team_id
   and species.name = rule.species_name
  on conflict (season_id, mark_id, species_id) do nothing;
end;
$seed$;