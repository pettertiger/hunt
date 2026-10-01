-- Run manually in the DEVELOPMENT project's SQL Editor.
-- Jakt från båt is a mark without pass positions or a map.
insert into public.marks (team_id, name, is_active)
select t.id, 'Jakt från båt', true
from public.teams t
where t.name = 'Fän Jaktlag'
on conflict (team_id, name) do update set is_active = true;

insert into public.hunt_marks (team_id, hunt_id, mark_id, map_version_id)
select
  h.team_id,
  h.id,
  m.id,
  null
from public.hunts h
join public.teams t on t.id = h.team_id
join public.marks m on m.team_id = t.id and m.name = 'Jakt från båt'
where t.name = 'Fän Jaktlag'
  and h.title = 'Fän jakt'
  and h.hunt_date = date '2026-10-17'
  and not exists (
    select 1
    from public.hunt_marks existing_mark
    where existing_mark.hunt_id = h.id
      and existing_mark.mark_id = m.id
  );

insert into public.drive_marks (team_id, hunt_id, drive_id, mark_id)
select
  d.team_id,
  d.hunt_id,
  d.id,
  m.id
from public.drives d
join public.marks m on m.team_id = d.team_id and m.name = 'Jakt från båt'
where d.name = 'Drev 2'
  and not exists (
    select 1
    from public.drive_marks existing_mark
    where existing_mark.drive_id = d.id
      and existing_mark.mark_id = m.id
  );

select
  d.name as drive_name,
  m.name as mark_name,
  hm.map_version_id
from public.drive_marks dm
join public.drives d on d.id = dm.drive_id
join public.marks m on m.id = dm.mark_id
join public.hunt_marks hm on hm.hunt_id = dm.hunt_id and hm.mark_id = dm.mark_id
where m.name = 'Jakt från båt';
