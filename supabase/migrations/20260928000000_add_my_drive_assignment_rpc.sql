create or replace function public.set_my_drive_assignment(
  target_drive_id uuid,
  target_pass_id uuid
)
returns public.drive_participants
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  target_hunt_id uuid;
  target_person_id uuid;
  target_participant_id uuid;
  target_pass_mark_id uuid;
  assignment public.drive_participants;
begin
  select d.team_id, d.hunt_id
  into target_team_id, target_hunt_id
  from public.drives d
  where d.id = target_drive_id;

  if target_team_id is null then
    raise exception using errcode = 'P0002', message = 'Drive not found';
  end if;

  select p.id
  into target_person_id
  from public.people p
  where p.team_id = target_team_id
    and p.auth_user_id = (select auth.uid())
    and p.is_active;

  select hp.id
  into target_participant_id
  from public.hunt_participants hp
  where hp.hunt_id = target_hunt_id
    and hp.person_id = target_person_id
    and hp.revoked_at is null;

  if target_participant_id is null then
    raise exception using errcode = '42501', message = 'No hunt participant record exists for this account';
  end if;

  select ps.mark_id
  into target_pass_mark_id
  from public.passes ps
  where ps.id = target_pass_id
    and ps.team_id = target_team_id
    and ps.is_active;

  if target_pass_mark_id is null then
    raise exception using errcode = 'P0002', message = 'Pass not found';
  end if;

  if not exists (
    select 1
    from public.drive_marks dm
    where dm.drive_id = target_drive_id
      and dm.mark_id = target_pass_mark_id
      and dm.team_id = target_team_id
  ) then
    raise exception using errcode = '23514', message = 'Pass mark is not enabled for this drive';
  end if;

  insert into public.drive_participants (
    team_id, hunt_id, drive_id, participant_id,
    assignment_status, pass_id, pass_mark_id
  ) values (
    target_team_id, target_hunt_id, target_drive_id, target_participant_id,
    'assigned', target_pass_id, target_pass_mark_id
  )
  on conflict (drive_id, participant_id) do update
  set assignment_status = excluded.assignment_status,
      pass_id = excluded.pass_id,
      pass_mark_id = excluded.pass_mark_id
  returning * into assignment;

  return assignment;
end;
$$;

revoke all on function public.set_my_drive_assignment(uuid, uuid) from public;
grant execute on function public.set_my_drive_assignment(uuid, uuid) to authenticated;
