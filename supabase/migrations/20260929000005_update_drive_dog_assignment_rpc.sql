create or replace function public.update_drive_dog_assignment(
  target_drive_id uuid,
  target_hunt_dog_id uuid,
  target_dog_id uuid,
  target_handler_participant_id uuid
)
returns public.drive_dog_assignments
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  target_hunt_id uuid;
  assignment public.drive_dog_assignments;
begin
  select d.team_id, d.hunt_id
  into target_team_id, target_hunt_id
  from public.drives d
  where d.id = target_drive_id
    and public.is_team_leader(d.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can edit drive dogs';
  end if;

  if not exists (
    select 1 from public.hunt_dogs hd
    where hd.id = target_hunt_dog_id and hd.hunt_id = target_hunt_id
  ) then
    raise exception using errcode = 'P0002', message = 'Hunt dog not found';
  end if;

  if not exists (
    select 1 from public.dogs d
    where d.id = target_dog_id and d.team_id = target_team_id and d.is_active
  ) then
    raise exception using errcode = 'P0002', message = 'Dog not found';
  end if;

  if not exists (
    select 1 from public.hunt_participants hp
    where hp.id = target_handler_participant_id
      and hp.hunt_id = target_hunt_id
      and hp.revoked_at is null
  ) then
    raise exception using errcode = '23514', message = 'Handler is not a hunt participant';
  end if;

  update public.hunt_dogs
  set dog_id = target_dog_id,
      guest_dog_name = null,
      guest_dog_breed = null
  where id = target_hunt_dog_id;

  insert into public.drive_dog_assignments (
    team_id, hunt_id, drive_id, hunt_dog_id, handler_participant_id
  ) values (
    target_team_id, target_hunt_id, target_drive_id, target_hunt_dog_id, target_handler_participant_id
  )
  on conflict (drive_id, hunt_dog_id) do update
  set handler_participant_id = excluded.handler_participant_id
  returning * into assignment;

  return assignment;
end;
$$;

revoke all on function public.update_drive_dog_assignment(uuid, uuid, uuid, uuid) from public;
grant execute on function public.update_drive_dog_assignment(uuid, uuid, uuid, uuid) to authenticated;
