create or replace function public.add_harvested_animal(
  target_hunt_id uuid,
  target_species_id uuid,
  target_pass_id uuid,
  target_pass_mark_id uuid,
  target_shooter_participant_id uuid,
  target_sex public.animal_sex default null,
  target_age_class_id uuid default null,
  target_rule_exception boolean default false,
  target_exception_reason text default null
)
returns public.harvested_animals
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  report_id uuid;
  animal public.harvested_animals;
begin
  select h.team_id into target_team_id
  from public.hunts h
  where h.id = target_hunt_id
    and public.is_team_leader(h.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can report harvest';
  end if;

  select hr.id into report_id
  from public.hunt_reports hr
  where hr.hunt_id = target_hunt_id;

  if report_id is null then
    insert into public.hunt_reports (team_id, hunt_id, status)
    values (target_team_id, target_hunt_id, 'in_progress')
    returning id into report_id;
  end if;

  insert into public.harvested_animals (
    team_id, hunt_id, report_id, species_id, sex, age_class_id,
    pass_id, pass_mark_id, shooter_participant_id,
    rule_exception, exception_reason
  ) values (
    target_team_id, target_hunt_id, report_id, target_species_id, target_sex, target_age_class_id,
    target_pass_id, target_pass_mark_id, target_shooter_participant_id,
    target_rule_exception, case when target_rule_exception then nullif(btrim(target_exception_reason), '') else null end
  ) returning * into animal;

  return animal;
end;
$$;

revoke all on function public.add_harvested_animal(uuid, uuid, uuid, uuid, uuid, public.animal_sex, uuid, boolean, text) from public;
grant execute on function public.add_harvested_animal(uuid, uuid, uuid, uuid, uuid, public.animal_sex, uuid, boolean, text) to authenticated;
