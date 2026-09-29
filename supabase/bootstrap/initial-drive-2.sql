-- Run manually once in the DEVELOPMENT project's SQL Editor.
-- Creates Drev 2 and enables the Fän mark for it.
with new_drive as (
  insert into public.drives (team_id, hunt_id, name, sort_order)
  select
    h.team_id,
    h.id,
    'Drev 2',
    2
  from public.hunts h
  join public.teams t on t.id = h.team_id
  where t.name = 'Fän Jaktlag'
    and h.title = 'Fän jakt'
    and h.hunt_date = date '2026-10-17'
    and not exists (
      select 1
      from public.drives existing_drive
      where existing_drive.hunt_id = h.id
        and existing_drive.sort_order = 2
    )
  returning id, team_id, hunt_id
)
insert into public.drive_marks (team_id, hunt_id, drive_id, mark_id)
select
  d.team_id,
  d.hunt_id,
  d.id,
  m.id
from new_drive d
join public.marks m on m.team_id = d.team_id and m.name = 'Fän'
where not exists (
  select 1
  from public.drive_marks existing_mark
  where existing_mark.drive_id = d.id
    and existing_mark.mark_id = m.id
);

select
  d.name as drive_name,
  m.name as mark_name,
  d.sort_order
from public.drive_marks dm
join public.drives d on d.id = dm.drive_id
join public.marks m on m.id = dm.mark_id
where d.name in ('Drev 1', 'Drev 2')
order by d.sort_order;
