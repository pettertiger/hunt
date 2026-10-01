-- Initial schema for the single-team hunting app.
-- Participant invite links must be handled by a server-side Edge Function or
-- narrowly scoped RPC. Do not add direct anon policies for these tables.
-- Bootstrap the first team and admin membership from the Supabase SQL editor
-- after creating the admin's auth.users record.

create type public.hunt_status as enum ('draft', 'planned', 'completed', 'cancelled');
create type public.rsvp_status as enum ('unanswered', 'yes', 'no', 'unsure');
create type public.report_status as enum ('not_started', 'in_progress', 'complete');
create type public.rule_mode as enum ('open', 'quota', 'closed');
create type public.animal_sex as enum ('male', 'female');

create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  admin_user_id uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (id)
);

create table public.team_access (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);

create or replace function public.is_team_leader(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teams team_row
    where team_row.id = target_team_id
      and team_row.admin_user_id = (select auth.uid())
  ) or exists (
    select 1
    from public.team_access access_row
    where access_row.team_id = target_team_id
      and access_row.user_id = (select auth.uid())
  );
$$;

create or replace function public.is_team_admin(target_team_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.teams team_row
    where team_row.id = target_team_id
      and team_row.admin_user_id = (select auth.uid())
  );
$$;

create or replace function public.transfer_team_admin(
  target_team_id uuid,
  new_admin_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_admin_user_id uuid := (select auth.uid());
begin
  if current_admin_user_id is null
    or not public.is_team_admin(target_team_id) then
    raise exception using
      errcode = '42501',
      message = 'Only the current team admin can transfer admin access';
  end if;

  if new_admin_user_id = current_admin_user_id then
    return;
  end if;

  if not exists (
    select 1
    from public.team_access access_row
    where access_row.team_id = target_team_id
      and access_row.user_id = new_admin_user_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'The new admin must already be a team leader';
  end if;

  update public.teams
  set admin_user_id = new_admin_user_id
  where id = target_team_id;

  delete from public.team_access
  where team_id = target_team_id
    and user_id = new_admin_user_id;

  insert into public.team_access (team_id, user_id)
  values (target_team_id, current_admin_user_id)
  on conflict do nothing;
end;
$$;

revoke all on function public.is_team_leader(uuid) from public;
revoke all on function public.is_team_admin(uuid) from public;
revoke all on function public.transfer_team_admin(uuid, uuid) from public;
grant execute on function public.is_team_leader(uuid) to authenticated;
grant execute on function public.is_team_admin(uuid) to authenticated;
grant execute on function public.transfer_team_admin(uuid, uuid) to authenticated;

create table public.people (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  name text not null,
  usual_roles text[] not null default '{}',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, team_id)
);

create table public.dogs (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  owner_person_id uuid,
  name text not null,
  breed text,
  birth_year integer check (birth_year between 1900 and 2100),
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, team_id),
  foreign key (owner_person_id, team_id)
    references public.people(id, team_id) on delete restrict
);

create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  label text not null,
  created_at timestamptz not null default now(),
  unique (id, team_id),
  unique (team_id, label)
);

create table public.marks (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  unique (id, team_id),
  unique (team_id, name)
);

create table public.mark_map_versions (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  mark_id uuid not null,
  version_number integer not null check (version_number > 0),
  storage_path text not null,
  original_filename text not null,
  is_current boolean not null default false,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (id, mark_id, team_id),
  unique (mark_id, version_number),
  foreign key (mark_id, team_id)
    references public.marks(id, team_id) on delete cascade
);

create unique index one_current_map_per_mark
  on public.mark_map_versions(mark_id)
  where is_current;

create table public.passes (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  mark_id uuid not null,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, mark_id, team_id),
  unique (mark_id, name),
  foreign key (mark_id, team_id)
    references public.marks(id, team_id) on delete cascade
);

create table public.pass_positions (
  team_id uuid not null,
  mark_id uuid not null,
  pass_id uuid not null,
  map_version_id uuid not null,
  x numeric(8, 7) not null check (x between 0 and 1),
  y numeric(8, 7) not null check (y between 0 and 1),
  created_at timestamptz not null default now(),
  primary key (pass_id, map_version_id),
  foreign key (pass_id, mark_id, team_id)
    references public.passes(id, mark_id, team_id) on delete cascade,
  foreign key (map_version_id, mark_id, team_id)
    references public.mark_map_versions(id, mark_id, team_id) on delete cascade
);

create table public.species (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  name text not null,
  can_observe boolean not null default true,
  can_harvest boolean not null default true,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, team_id),
  unique (team_id, name),
  check (can_observe or can_harvest)
);

create table public.species_age_classes (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  species_id uuid not null,
  name text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (id, species_id, team_id),
  unique (species_id, name),
  foreign key (species_id, team_id)
    references public.species(id, team_id) on delete restrict
);

create table public.mark_species_rules (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  season_id uuid not null,
  mark_id uuid not null,
  species_id uuid not null,
  mode public.rule_mode not null,
  guidance text,
  revision integer not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  unique (id, team_id),
  unique (id, species_id, team_id),
  unique (season_id, mark_id, species_id),
  foreign key (season_id, team_id)
    references public.seasons(id, team_id) on delete cascade,
  foreign key (mark_id, team_id)
    references public.marks(id, team_id) on delete cascade,
  foreign key (species_id, team_id)
    references public.species(id, team_id) on delete cascade
);

create table public.mark_species_quota_categories (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  rule_id uuid not null,
  species_id uuid not null,
  category_name text not null,
  sex public.animal_sex,
  age_class_id uuid,
  available_count integer not null check (available_count >= 0),
  unique (id, team_id),
  unique (rule_id, category_name),
  foreign key (rule_id, species_id, team_id)
    references public.mark_species_rules(id, species_id, team_id) on delete cascade,
  foreign key (age_class_id, species_id, team_id)
    references public.species_age_classes(id, species_id, team_id) on delete restrict
);

create table public.hunts (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  season_id uuid not null,
  title text,
  hunt_date date not null,
  status public.hunt_status not null default 'draft',
  registration_open boolean not null default true,
  reply_deadline timestamptz,
  revision integer not null default 1 check (revision > 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, team_id),
  foreign key (season_id, team_id)
    references public.seasons(id, team_id) on delete restrict
);

create table public.hunt_marks (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  mark_id uuid not null,
  map_version_id uuid not null,
  unique (id, team_id),
  unique (id, team_id, hunt_id),
  unique (hunt_id, mark_id),
  foreign key (hunt_id, team_id)
    references public.hunts(id, team_id) on delete cascade,
  foreign key (mark_id, team_id)
    references public.marks(id, team_id) on delete restrict,
  foreign key (map_version_id, mark_id, team_id)
    references public.mark_map_versions(id, mark_id, team_id) on delete restrict
);

create table public.hunt_rule_snapshots (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_mark_id uuid not null,
  species_id uuid not null,
  mode public.rule_mode not null,
  guidance text,
  unique (id, team_id),
  unique (id, species_id, team_id),
  unique (hunt_mark_id, species_id),
  foreign key (hunt_mark_id, team_id)
    references public.hunt_marks(id, team_id) on delete cascade,
  foreign key (species_id, team_id)
    references public.species(id, team_id) on delete restrict
);

create table public.hunt_rule_quota_snapshots (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  rule_snapshot_id uuid not null,
  species_id uuid not null,
  category_name text not null,
  sex public.animal_sex,
  age_class_id uuid,
  available_count integer not null check (available_count >= 0),
  unique (rule_snapshot_id, category_name),
  foreign key (rule_snapshot_id, species_id, team_id)
    references public.hunt_rule_snapshots(id, species_id, team_id) on delete cascade,
  foreign key (age_class_id, species_id, team_id)
    references public.species_age_classes(id, species_id, team_id) on delete restrict
);

create table public.hunt_participants (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  person_id uuid,
  guest_name text,
  invite_token_hash text not null unique,
  revoked_at timestamptz,
  response public.rsvp_status not null default 'unanswered',
  response_comment text,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id, team_id),
  unique (id, team_id, hunt_id),
  unique (hunt_id, person_id),
  check (
    (person_id is not null and guest_name is null)
    or (person_id is null and nullif(btrim(guest_name), '') is not null)
  ),
  foreign key (hunt_id, team_id)
    references public.hunts(id, team_id) on delete cascade,
  foreign key (person_id, team_id)
    references public.people(id, team_id) on delete restrict
);

create table public.hunt_meals (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  meal_type text not null check (meal_type in ('lunch', 'dinner')),
  is_communal boolean not null default false,
  plan text,
  starts_at time,
  location text,
  responsible_participant_id uuid,
  revision integer not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  unique (id, team_id, hunt_id),
  unique (hunt_id, meal_type),
  foreign key (hunt_id, team_id)
    references public.hunts(id, team_id) on delete cascade,
  foreign key (responsible_participant_id, team_id, hunt_id)
    references public.hunt_participants(id, team_id, hunt_id) on delete restrict
);

create table public.meal_responses (
  team_id uuid not null,
  hunt_id uuid not null,
  meal_id uuid not null,
  participant_id uuid not null,
  attending boolean not null,
  private_comment text,
  updated_at timestamptz not null default now(),
  primary key (meal_id, participant_id),
  foreign key (meal_id, team_id, hunt_id)
    references public.hunt_meals(id, team_id, hunt_id) on delete cascade,
  foreign key (participant_id, team_id, hunt_id)
    references public.hunt_participants(id, team_id, hunt_id) on delete cascade
);

create table public.drives (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  name text not null,
  sort_order integer not null check (sort_order > 0),
  unique (id, team_id, hunt_id),
  unique (hunt_id, sort_order),
  foreign key (hunt_id, team_id)
    references public.hunts(id, team_id) on delete cascade
);

create table public.drive_marks (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  drive_id uuid not null,
  mark_id uuid not null,
  unique (drive_id, mark_id, team_id),
  unique (id, team_id, hunt_id),
  foreign key (drive_id, team_id, hunt_id)
    references public.drives(id, team_id, hunt_id) on delete cascade,
  foreign key (hunt_id, mark_id)
    references public.hunt_marks(hunt_id, mark_id) on delete cascade
);

create table public.drive_participants (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  drive_id uuid not null,
  participant_id uuid not null,
  assignment_status text not null default 'pending'
    check (assignment_status in ('pending', 'no_pass', 'assigned')),
  pass_id uuid,
  pass_mark_id uuid,
  unique (drive_id, participant_id),
  check (
    (assignment_status = 'assigned' and pass_id is not null and pass_mark_id is not null)
    or (assignment_status in ('pending', 'no_pass') and pass_id is null and pass_mark_id is null)
  ),
  foreign key (drive_id, team_id, hunt_id)
    references public.drives(id, team_id, hunt_id) on delete cascade,
  foreign key (participant_id, team_id, hunt_id)
    references public.hunt_participants(id, team_id, hunt_id) on delete cascade,
  foreign key (drive_id, pass_mark_id, team_id)
    references public.drive_marks(drive_id, mark_id, team_id) on delete restrict,
  foreign key (pass_id, pass_mark_id, team_id)
    references public.passes(id, mark_id, team_id) on delete restrict
);

create table public.hunt_dogs (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  dog_id uuid,
  guest_dog_name text,
  guest_dog_breed text,
  created_at timestamptz not null default now(),
  unique (id, team_id, hunt_id),
  check (
    (dog_id is not null and guest_dog_name is null)
    or (dog_id is null and nullif(btrim(guest_dog_name), '') is not null)
  ),
  foreign key (hunt_id, team_id)
    references public.hunts(id, team_id) on delete cascade,
  foreign key (dog_id, team_id)
    references public.dogs(id, team_id) on delete restrict
);

create table public.drive_dog_assignments (
  team_id uuid not null,
  hunt_id uuid not null,
  drive_id uuid not null,
  hunt_dog_id uuid not null,
  handler_participant_id uuid not null,
  primary key (drive_id, hunt_dog_id),
  foreign key (drive_id, team_id, hunt_id)
    references public.drives(id, team_id, hunt_id) on delete cascade,
  foreign key (hunt_dog_id, team_id, hunt_id)
    references public.hunt_dogs(id, team_id, hunt_id) on delete cascade,
  foreign key (handler_participant_id, team_id, hunt_id)
    references public.hunt_participants(id, team_id, hunt_id) on delete restrict
);

create table public.hunt_reports (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  status public.report_status not null default 'not_started',
  notes text,
  revision integer not null default 1 check (revision > 0),
  updated_at timestamptz not null default now(),
  unique (id, team_id, hunt_id),
  unique (hunt_id),
  foreign key (hunt_id, team_id)
    references public.hunts(id, team_id) on delete cascade
);

create table public.harvested_animals (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  report_id uuid not null,
  species_id uuid not null,
  sex public.animal_sex,
  age_class_id uuid,
  pass_id uuid not null,
  pass_mark_id uuid not null,
  shooter_participant_id uuid not null,
  rule_exception boolean not null default false,
  exception_reason text,
  created_at timestamptz not null default now(),
  check (
    (rule_exception and nullif(btrim(exception_reason), '') is not null)
    or (not rule_exception and exception_reason is null)
  ),
  foreign key (report_id, team_id, hunt_id)
    references public.hunt_reports(id, team_id, hunt_id) on delete cascade,
  foreign key (species_id, team_id)
    references public.species(id, team_id) on delete restrict,
  foreign key (age_class_id, species_id, team_id)
    references public.species_age_classes(id, species_id, team_id) on delete restrict,
  foreign key (pass_id, pass_mark_id, team_id)
    references public.passes(id, mark_id, team_id) on delete restrict,
  foreign key (hunt_id, pass_mark_id)
    references public.hunt_marks(hunt_id, mark_id) on delete restrict,
  foreign key (shooter_participant_id, team_id, hunt_id)
    references public.hunt_participants(id, team_id, hunt_id) on delete restrict
);

create table public.search_events (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  report_id uuid not null,
  species_id uuid not null,
  outcome text not null check (outcome in ('pending', 'found', 'not_found')),
  pass_id uuid,
  pass_mark_id uuid,
  shooter_participant_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  check ((pass_id is null) = (pass_mark_id is null)),
  foreign key (report_id, team_id, hunt_id)
    references public.hunt_reports(id, team_id, hunt_id) on delete cascade,
  foreign key (species_id, team_id)
    references public.species(id, team_id) on delete restrict,
  foreign key (pass_id, pass_mark_id, team_id)
    references public.passes(id, mark_id, team_id) on delete restrict,
  foreign key (hunt_id, pass_mark_id)
    references public.hunt_marks(hunt_id, mark_id) on delete restrict,
  foreign key (shooter_participant_id, team_id, hunt_id)
    references public.hunt_participants(id, team_id, hunt_id) on delete restrict
);

create table public.observations (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null,
  hunt_id uuid not null,
  report_id uuid not null,
  species_id uuid not null,
  quantity integer not null check (quantity > 0),
  drive_id uuid,
  pass_id uuid,
  pass_mark_id uuid,
  notes text,
  created_at timestamptz not null default now(),
  check ((pass_id is null) = (pass_mark_id is null)),
  foreign key (report_id, team_id, hunt_id)
    references public.hunt_reports(id, team_id, hunt_id) on delete cascade,
  foreign key (species_id, team_id)
    references public.species(id, team_id) on delete restrict,
  foreign key (drive_id, team_id, hunt_id)
    references public.drives(id, team_id, hunt_id) on delete restrict,
  foreign key (pass_id, pass_mark_id, team_id)
    references public.passes(id, mark_id, team_id) on delete restrict,
  foreign key (hunt_id, pass_mark_id)
    references public.hunt_marks(hunt_id, mark_id) on delete restrict
);

insert into storage.buckets (id, name, public)
values ('hunt-maps', 'hunt-maps', false)
on conflict (id) do update set public = false;

create policy leaders_manage_hunt_maps
  on storage.objects for all to authenticated
  using (
    bucket_id = 'hunt-maps'
    and exists (
      select 1
      from public.teams team_row
      where team_row.id::text = (storage.foldername(name))[1]
        and public.is_team_leader(team_row.id)
    )
  )
  with check (
    bucket_id = 'hunt-maps'
    and exists (
      select 1
      from public.teams team_row
      where team_row.id::text = (storage.foldername(name))[1]
        and public.is_team_leader(team_row.id)
    )
  );

revoke all on function public.is_team_leader(uuid) from public;
revoke all on function public.is_team_admin(uuid) from public;
grant execute on function public.is_team_leader(uuid) to authenticated;
grant execute on function public.is_team_admin(uuid) to authenticated;

alter table public.teams enable row level security;
alter table public.team_access enable row level security;
revoke all on public.teams, public.team_access from anon;
grant select on public.teams to authenticated;
grant update (name) on public.teams to authenticated;
grant select, insert, update, delete on public.team_access to authenticated;

create policy team_leaders_read_team
  on public.teams for select to authenticated
  using (public.is_team_leader(id));
create policy team_leaders_update_team
  on public.teams for update to authenticated
  using (public.is_team_leader(id))
  with check (public.is_team_leader(id));

create policy leaders_read_team_access
  on public.team_access for select to authenticated
  using (public.is_team_leader(team_id));
create policy admins_add_team_access
  on public.team_access for insert to authenticated
  with check (public.is_team_admin(team_id));
create policy admins_update_team_access
  on public.team_access for update to authenticated
  using (public.is_team_admin(team_id))
  with check (public.is_team_admin(team_id));
create policy admins_remove_team_access
  on public.team_access for delete to authenticated
  using (public.is_team_admin(team_id));

do $$
declare
  table_name text;
  team_tables text[] := array[
    'people', 'dogs', 'seasons', 'marks', 'mark_map_versions', 'passes',
    'pass_positions', 'species', 'species_age_classes', 'mark_species_rules',
    'mark_species_quota_categories', 'hunts', 'hunt_marks',
    'hunt_rule_snapshots', 'hunt_rule_quota_snapshots', 'hunt_participants',
    'hunt_meals', 'meal_responses', 'drives', 'drive_marks',
    'drive_participants', 'hunt_dogs', 'drive_dog_assignments',
    'hunt_reports', 'harvested_animals', 'search_events', 'observations'
  ];
begin
  foreach table_name in array team_tables loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('revoke all on public.%I from anon', table_name);
    execute format('grant select, insert, update, delete on public.%I to authenticated', table_name);
    execute format(
      'create policy leaders_manage_%1$I on public.%1$I for all to authenticated using (public.is_team_leader(team_id)) with check (public.is_team_leader(team_id))',
      table_name
    );
  end loop;
end;
$$;

comment on table public.team_access is
  'Non-admin leadership accounts only; teams.admin_user_id stores the single admin.';
comment on column public.hunt_participants.invite_token_hash is
  'Hash only; validate via a server-side Edge Function or narrowly scoped RPC. Never expose directly to anon.';
comment on table public.hunt_rule_quota_snapshots is
  'Manual quota snapshot for one hunt; harvested animals do not decrement these values.';
comment on table public.pass_positions is
  'Normalized PDF-page coordinates, not geographic coordinates.';