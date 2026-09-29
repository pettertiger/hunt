create or replace function public.save_hunt_report(
  target_hunt_id uuid,
  target_status public.report_status,
  target_notes text
)
returns public.hunt_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_team_id uuid;
  report public.hunt_reports;
begin
  select h.team_id
  into target_team_id
  from public.hunts h
  where h.id = target_hunt_id
    and public.is_team_leader(h.team_id);

  if target_team_id is null then
    raise exception using errcode = '42501', message = 'Only team leaders can save hunt reports';
  end if;

  insert into public.hunt_reports (team_id, hunt_id, status, notes, updated_at)
  values (target_team_id, target_hunt_id, target_status, nullif(btrim(target_notes), ''), now())
  on conflict (hunt_id) do update
  set status = excluded.status,
      notes = excluded.notes,
      updated_at = excluded.updated_at
  returning * into report;

  return report;
end;
$$;

revoke all on function public.save_hunt_report(uuid, public.report_status, text) from public;
grant execute on function public.save_hunt_report(uuid, public.report_status, text) to authenticated;
