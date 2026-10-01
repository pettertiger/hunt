-- Run manually in the DEVELOPMENT project's SQL Editor after initial-team.sql.
-- Adds named Fän passes only; map positions are added separately after visual placement.
-- Safe to rerun: existing passes with the same mark/name are left unchanged.

do $passes$
declare
  v_team_id uuid;
  v_mark_id uuid;
begin
  select id into strict v_team_id
  from public.teams
  where name = 'Fän Jaktlag';

  select id into strict v_mark_id
  from public.marks
  where marks.team_id = v_team_id
    and name = 'Fän';

  insert into public.passes (team_id, mark_id, name)
  select v_team_id, v_mark_id, pass.name
  from (values
    ('1T'), ('2P'), ('3P'), ('4P'), ('5P'), ('6T'), ('7P'), ('8'),
    ('9P'), ('10S'), ('11P'), ('12P'), ('13'), ('14T'), ('15'), ('16'),
    ('17P'), ('18'), ('19'), ('20'), ('21'), ('22P'), ('23'), ('24'),
    ('25'), ('26'), ('27'), ('28T')
  ) as pass(name)
  on conflict (mark_id, name) do nothing;
end;
$passes$;