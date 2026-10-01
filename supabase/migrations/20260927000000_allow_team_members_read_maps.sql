-- Allow authenticated team members to read private map objects.
create or replace function public.is_team_member(target_team_id uuid)
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

revoke all on function public.is_team_member(uuid) from public;
grant execute on function public.is_team_member(uuid) to authenticated;

create policy team_members_read_hunt_maps
  on storage.objects for select to authenticated
  using (
    bucket_id = 'hunt-maps'
    and exists (
      select 1
      from public.teams team_row
      where team_row.id::text = (storage.foldername(name))[1]
        and public.is_team_member(team_row.id)
    )
  );
