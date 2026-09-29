create or replace function public.add_drive_dog(
  target_drive_id uuid,
  target_name text,
  target_breed text,
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

  if nullif(btrim(target_name), '') is null then
    raise exception using errcode = '23514', message = 'Dog name is required';
  end if;

  if target_handler_participant_id is not null and not exists (
    select 1
    from public.hunt_participants hp
    where hp.id = target_handler_participant_id
      and hp.hunt_id = target_hunt_id
      and hp.revoked_at is null
  ) then
    raise exception using errcode = '23514', message = 'Handler is not a participant in this hunt';
  end if;

  insert into public.hunt_dogs (
    team_id, hunt_id, guest_dog_name, guest_dog_breed
  ) values (
    target_team_id, target_hunt_id, btrim(target_name), nullif(btrim(target_breed), '')
  ) returning * into hunt_dog;

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

revoke all on function public.add_drive_dog(uuid, text, text, uuid) from public;
grant execute on function public.add_drive_dog(uuid, text, text, uuid) to authenticated;
