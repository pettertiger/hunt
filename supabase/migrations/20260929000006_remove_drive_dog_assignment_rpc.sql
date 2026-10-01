create or replace function public.remove_drive_dog_assignment(
  target_drive_id uuid,
  target_hunt_dog_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
begin
  select d.team_id
  into target_team_id
  from public.drives d
  where d.id = target_drive_id
    and public.is_team_leader(d.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can remove drive dogs';
  end if;

  delete from public.drive_dog_assignments
  where drive_id = target_drive_id
    and hunt_dog_id = target_hunt_dog_id;
end;
$$;

revoke all on function public.remove_drive_dog_assignment(uuid, uuid) from public;
grant execute on function public.remove_drive_dog_assignment(uuid, uuid) to authenticated;
