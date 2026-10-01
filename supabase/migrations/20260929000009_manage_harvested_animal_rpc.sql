create or replace function public.update_harvested_animal(
  target_id uuid,
  target_species_id uuid,
  target_pass_id uuid,
  target_pass_mark_id uuid,
  target_shooter_participant_id uuid
)
returns public.harvested_animals
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  animal public.harvested_animals;
begin
  select ha.team_id into target_team_id
  from public.harvested_animals ha
  where ha.id = target_id
    and public.is_team_leader(ha.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can edit harvest';
  end if;

  update public.harvested_animals
  set species_id = target_species_id,
      pass_id = target_pass_id,
      pass_mark_id = target_pass_mark_id,
      shooter_participant_id = target_shooter_participant_id
  where id = target_id
  returning * into animal;

  return animal;
end;
$$;

create or replace function public.remove_harvested_animal(target_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.harvested_animals ha
    where ha.id = target_id
      and public.is_team_leader(ha.team_id)
  ) then
    raise exception using errcode = '42501', message = 'Only team leaders can remove harvest';
  end if;

  delete from public.harvested_animals where id = target_id;
end;
$$;

revoke all on function public.update_harvested_animal(uuid, uuid, uuid, uuid, uuid) from public;
revoke all on function public.remove_harvested_animal(uuid) from public;
grant execute on function public.update_harvested_animal(uuid, uuid, uuid, uuid, uuid) to authenticated;
grant execute on function public.remove_harvested_animal(uuid) to authenticated;
