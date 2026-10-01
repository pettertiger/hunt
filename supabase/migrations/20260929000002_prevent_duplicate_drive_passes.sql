create unique index if not exists drive_participants_one_assigned_pass_per_drive
  on public.drive_participants(drive_id, pass_id)
  where assignment_status = 'assigned'
    and pass_id is not null;
