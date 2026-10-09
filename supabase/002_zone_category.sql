-- Nearby: place types (home, shop, masjid...). Add-only: existing rows become 'other'.
alter table public.zones
  add column if not exists category text not null default 'other'
  check (category in ('home', 'shop', 'masjid', 'work', 'school', 'other'));
