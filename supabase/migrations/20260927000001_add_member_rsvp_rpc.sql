alter table public.people
  add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

create unique index if not exists people_team_auth_user_id
  on public.people(team_id, auth_user_id)
  where auth_user_id is not null;

create or replace function public.set_my_hunt_response(
  target_hunt_id uuid,
  target_response public.rsvp_status,
  target_comment text default null
)
returns public.hunt_participants
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  target_person_id uuid;
  participant public.hunt_participants;
begin
  select h.team_id
  into target_team_id
  from public.hunts h
  where h.id = target_hunt_id;

  if target_team_id is null then
    raise exception using errcode = 'P0002', message = 'Hunt not found';
  end if;

  select p.id
  into target_person_id
  from public.people p
  where p.team_id = target_team_id
    and p.auth_user_id = (select auth.uid())
    and p.is_active;

  if target_person_id is null then
    raise exception using errcode = '42501', message = 'No person record is linked to this account';
  end if;

  insert into public.hunt_participants (
    team_id, hunt_id, person_id, invite_token_hash, response, response_comment, responded_at
  ) values (
    target_team_id,
    target_hunt_id,
    target_person_id,
    md5(target_hunt_id::text || ':' || target_person_id::text),
    target_response,
    nullif(btrim(target_comment), ''),
    now()
  )
  on conflict (hunt_id, person_id) do update
  set response = excluded.response,
      response_comment = excluded.response_comment,
      responded_at = excluded.responded_at
  returning * into participant;

  return participant;
end;
$$;

revoke all on function public.set_my_hunt_response(uuid, public.rsvp_status, text) from public;
grant execute on function public.set_my_hunt_response(uuid, public.rsvp_status, text) to authenticated;
