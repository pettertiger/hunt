-- Run manually once in the DEVELOPMENT project's SQL Editor.
-- Replace the placeholder with an email that already exists in auth.users.
-- This file is outside supabase/migrations and is not auto-applied by GitHub.

do $bootstrap$
declare
  admin_email text := lower('REPLACE_WITH_YOUR_AUTH_EMAIL');
  admin_id uuid;
  team_id uuid;
begin
  if admin_email = 'replace_with_your_auth_email' then
    raise exception 'Edit admin_email before running this bootstrap';
  end if;

  select users.id
    into admin_id
  from auth.users as users
  where lower(users.email) = admin_email;

  if admin_id is null then
    raise exception 'No Supabase Auth user found for the configured admin email';
  end if;

  if (select count(*) from public.teams) > 0 then
    raise exception 'A team already exists; bootstrap is intentionally one-time';
  end if;

  insert into public.teams (name, admin_user_id)
  values ('Fän Jaktlag', admin_id)
  returning id into team_id;

  insert into public.seasons (team_id, label)
  values (team_id, '2026/2027');

  insert into public.marks (team_id, name)
  values (team_id, 'Fän');
end;
$bootstrap$;
