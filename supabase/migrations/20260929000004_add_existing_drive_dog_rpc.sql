create or replace function public.add_existing_drive_dog(
  target_drive_id uuid,
  target_dog_id uuid,
  target_handler_participant_id uuid default null
)
returns public.hunt_dogs
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  target_hunt_id uuid;
  hunt_dog public.hunt_dogs;
begin
  select d.team_id, d.hunt_id
  into target_team_id, target_hunt_id
  from public.drives d
  where d.id = target_drive_id
    and public.is_team_leader(d.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can add drive dogs';
  end if;

  if not exists (
    select 1 from public.dogs d
    where d.id = target_dog_id and d.team_id = target_team_id and d.is_active
  ) then
    raise exception using errcode = 'P0002', message = 'Dog not found';
  end if;

  insert into public.hunt_dogs (team_id, hunt_id, dog_id)
  values (target_team_id, target_hunt_id, target_dog_id)
  returning * into hunt_dog;

  if target_handler_participant_id is not null then
    insert into public.drive_dog_assignments (
      team_id, hunt_id, drive_id, hunt_dog_id, handler_participant_id
    ) values (
      target_team_id, target_hunt_id, target_drive_id, hunt_dog.id, target_handler_participant_id
    );
  end if;

  return hunt_dog;
end;
$$;

revoke all on function public.add_existing_drive_dog(uuid, uuid, uuid) from public;
grant execute on function public.add_existing_drive_dog(uuid, uuid, uuid) to authenticated;
