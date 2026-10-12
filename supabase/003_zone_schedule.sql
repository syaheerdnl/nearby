-- Nearby: "How often" and "Only between these times". Add-only.
-- once_only: after the first alert, the app switches that place's reminders off.
-- active_from / active_to: minutes after local midnight (0-1439). Both null =
-- any time. from > to means the window runs past midnight (22:00 to 06:00).
alter table public.zones
  add column if not exists once_only boolean not null default false,
  add column if not exists active_from smallint
    check (active_from between 0 and 1439),
  add column if not exists active_to smallint
    check (active_to between 0 and 1439);

alter table public.zones
  drop constraint if exists zones_active_window_both;
alter table public.zones
  add constraint zones_active_window_both
    check ((active_from is null) = (active_to is null));
