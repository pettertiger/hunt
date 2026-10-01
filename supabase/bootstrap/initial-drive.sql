-- Run manually once in the DEVELOPMENT project's SQL Editor.
-- Creates the first drive for the planned Fän hunt.
insert into public.drives (team_id, hunt_id, name, sort_order)
select
  h.team_id,
  h.id,
  'Drev 1',
  1
from public.hunts h
join public.teams t on t.id = h.team_id
where t.name = 'Fän Jaktlag'
  and h.title = 'Fän jakt'
  and h.hunt_date = date '2026-10-17'
  and not exists (
    select 1
    from public.drives existing_drive
    where existing_drive.hunt_id = h.id
      and existing_drive.sort_order = 1
  );

select d.id, d.name, d.sort_order, h.title, h.hunt_date
from public.drives d
join public.hunts h on h.id = d.hunt_id
where d.name = 'Drev 1';
