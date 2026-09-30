create or replace function public.create_guest_invite(
  target_hunt_id uuid,
  target_guest_name text,
  target_token_hash text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  participant_id uuid;
begin
  select h.team_id
  into target_team_id
  from public.hunts h
  where h.id = target_hunt_id
    and public.is_team_leader(h.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can create guest invites';
  end if;

  if nullif(btrim(target_guest_name), '') is null or length(btrim(target_guest_name)) > 160 then
    raise exception using errcode = '23514', message = 'Guest name must be between 1 and 160 characters';
  end if;

  if target_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '23514', message = 'Invite token hash must be a SHA-256 hex digest';
  end if;

  insert into public.hunt_participants (
    team_id, hunt_id, guest_name, invite_token_hash
  ) values (
    target_team_id, target_hunt_id, btrim(target_guest_name), target_token_hash
  ) returning id into participant_id;

  return participant_id;
end;
$$;

create or replace function public.get_guest_invite(target_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  invitation jsonb;
begin
  if target_token_hash !~ '^[0-9a-f]{64}$' then
    return null;
  end if;

  select jsonb_build_object(
    'guestName', hp.guest_name,
    'response', hp.response::text,
    'responseComment', hp.response_comment,
    'hunt', jsonb_build_object(
      'title', coalesce(h.title, 'Jakt'),
      'huntDate', h.hunt_date,
      'status', h.status::text,
      'registrationOpen', h.registration_open,
      'meals', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'type', meal.meal_type,
            'plan', meal.plan,
            'startsAt', meal.starts_at,
            'location', meal.location
          ) order by meal.meal_type
        )
        from public.hunt_meals meal
        where meal.hunt_id = h.id
          and meal.is_communal
      ), '[]'::jsonb)
    )
  )
  into invitation
  from public.hunt_participants hp
  join public.hunts h on h.id = hp.hunt_id and h.team_id = hp.team_id
  where hp.invite_token_hash = target_token_hash
    and hp.guest_name is not null
    and hp.revoked_at is null;

  return invitation;
end;
$$;

create or replace function public.respond_guest_invite(
  target_token_hash text,
  target_response public.rsvp_status,
  target_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  response_data jsonb;
begin
  if target_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = '42501', message = 'Invite not found';
  end if;

  if target_response not in ('yes', 'no', 'unsure') then
    raise exception using errcode = '23514', message = 'Choose yes, no, or unsure';
  end if;

  if length(coalesce(target_comment, '')) > 1000 then
    raise exception using errcode = '23514', message = 'Comment must be at most 1000 characters';
  end if;

  update public.hunt_participants hp
  set response = target_response,
      response_comment = nullif(btrim(target_comment), ''),
      responded_at = now()
  from public.hunts h
  where hp.hunt_id = h.id
    and hp.team_id = h.team_id
    and hp.invite_token_hash = target_token_hash
    and hp.guest_name is not null
    and hp.revoked_at is null
    and h.registration_open
    and h.status not in ('completed', 'cancelled')
  returning jsonb_build_object(
    'response', hp.response::text,
    'responseComment', hp.response_comment,
    'respondedAt', hp.responded_at
  ) into response_data;

  if response_data is null then
    raise exception using errcode = '42501', message = 'Invite is invalid, revoked, or closed';
  end if;

  return response_data;
end;
$$;

create or replace function public.revoke_guest_invite(target_participant_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
begin
  select hp.team_id
  into target_team_id
  from public.hunt_participants hp
  where hp.id = target_participant_id
    and hp.guest_name is not null
    and hp.revoked_at is null
    and public.is_team_leader(hp.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can revoke guest invites';
  end if;

  update public.hunt_participants
  set revoked_at = now()
  where id = target_participant_id;
end;
$$;

revoke all on function public.create_guest_invite(uuid, text, text) from public;
revoke all on function public.get_guest_invite(text) from public;
revoke all on function public.respond_guest_invite(text, public.rsvp_status, text) from public;
revoke all on function public.revoke_guest_invite(uuid) from public;

grant execute on function public.create_guest_invite(uuid, text, text) to authenticated;
grant execute on function public.get_guest_invite(text) to anon, authenticated;
grant execute on function public.respond_guest_invite(text, public.rsvp_status, text) to anon, authenticated;
grant execute on function public.revoke_guest_invite(uuid) to authenticated;