-- Nearby: Phase 1 schema (profiles, zones, zone_reminders) with row-level security.
-- Run once in Supabase: SQL Editor > New query > paste > Run.
--
-- Deviation from CLAUDE.md section 4: zones also store latitude/longitude as plain
-- numbers. The app reads and writes those; a trigger keeps the PostGIS `location`
-- column in sync, so the geography column is still there for Phase 2 queries.
-- Ids are generated on the phone (offline-first), so inserts always send `id`.

create extension if not exists postgis with schema extensions;

-- ---------- profiles ----------
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text unique not null check (username ~ '^[a-z0-9_]{3,20}$'),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles are readable by signed-in users"
  on public.profiles for select to authenticated
  using (true);

create policy "users update their own profile"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Create the profile row at sign-up, from the username the app sends in metadata.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, username)
  values (new.id, lower(new.raw_user_meta_data ->> 'username'));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- zones ----------
create table public.zones (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null check (char_length(name) between 1 and 60),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  location extensions.geography(point, 4326),
  radius_meters int not null default 150 check (radius_meters between 100 and 5000),
  trigger_type text not null check (trigger_type in ('enter', 'exit', 'dwell')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index zones_owner_id_idx on public.zones (owner_id);
create index zones_location_idx on public.zones using gist (location);

create function public.zones_before_write()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.location := extensions.st_setsrid(
    extensions.st_makepoint(new.longitude, new.latitude), 4326
  )::extensions.geography;
  new.updated_at := now();
  return new;
end;
$$;

create trigger zones_before_write
  before insert or update on public.zones
  for each row execute function public.zones_before_write();

alter table public.zones enable row level security;

create policy "owners manage their zones"
  on public.zones for all to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

-- ---------- zone_reminders ----------
create table public.zone_reminders (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.zones on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  body text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index zone_reminders_zone_id_idx on public.zone_reminders (zone_id);

create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger zone_reminders_touch
  before update on public.zone_reminders
  for each row execute function public.touch_updated_at();

alter table public.zone_reminders enable row level security;

create policy "owners manage reminders of their zones"
  on public.zone_reminders for all to authenticated
  using (exists (
    select 1 from public.zones z
    where z.id = zone_reminders.zone_id and z.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.zones z
    where z.id = zone_reminders.zone_id and z.owner_id = (select auth.uid())
  ));
