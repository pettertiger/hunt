-- Run manually once in the DEVELOPMENT project's SQL Editor.
-- Enables the Fän mark for Drev 1.
insert into public.drive_marks (team_id, hunt_id, drive_id, mark_id)
select
  d.team_id,
  d.hunt_id,
  d.id,
  m.id
from public.drives d
join public.marks m
  on m.team_id = d.team_id
where d.name = 'Drev 1'
  and m.name = 'Fän'
  and not exists (
    select 1
    from public.drive_marks existing_mark
    where existing_mark.drive_id = d.id
      and existing_mark.mark_id = m.id
  );

select
  d.name as drive_name,
  m.name as mark_name
from public.drive_marks dm
join public.drives d on d.id = dm.drive_id
join public.marks m on m.id = dm.mark_id
where d.name = 'Drev 1';
