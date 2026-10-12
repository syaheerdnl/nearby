-- Nearby Phase 2: friends and shared lists. Add-only (new tables, plus one
-- extra read policy on zones). Receipts/payments are Phase 3, not here.
--
-- RLS helpers are SECURITY DEFINER so policies on zones <-> shared_lists
-- don't recurse into each other.

-- ---------- friends ----------
create table if not exists public.friends (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users on delete cascade,
  friend_id uuid not null references auth.users on delete cascade,
  requested_by uuid not null references auth.users on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  constraint no_self_friend check (user_id <> friend_id),
  constraint requester_in_pair check (requested_by in (user_id, friend_id))
);
-- One row per pair, whichever way round it was sent.
create unique index if not exists friends_pair_uidx
  on public.friends (least(user_id, friend_id), greatest(user_id, friend_id));

alter table public.friends enable row level security;

create policy "see own friendships" on public.friends
  for select to authenticated
  using ((select auth.uid()) in (user_id, friend_id));

create policy "send a request" on public.friends
  for insert to authenticated
  with check (requested_by = (select auth.uid())
              and (select auth.uid()) in (user_id, friend_id)
              and status = 'pending');

-- Only the person who received the request can accept it.
create policy "accept a request" on public.friends
  for update to authenticated
  using ((select auth.uid()) in (user_id, friend_id)
         and requested_by <> (select auth.uid()))
  with check (status = 'accepted');

-- Either side can decline, cancel or unfriend.
create policy "remove a friendship" on public.friends
  for delete to authenticated
  using ((select auth.uid()) in (user_id, friend_id));

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.friends f
    where f.status = 'accepted'
      and least(f.user_id, f.friend_id) = least(a, b)
      and greatest(f.user_id, f.friend_id) = greatest(a, b));
$$;

-- ---------- shared lists ----------
create table if not exists public.shared_lists (
  id uuid primary key default gen_random_uuid(),
  zone_id uuid not null references public.zones on delete cascade,
  title text not null check (char_length(title) between 1 and 60),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists shared_lists_zone_idx on public.shared_lists (zone_id);

create table if not exists public.list_access (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shared_lists on delete cascade,
  friend_id uuid not null references auth.users on delete cascade,
  permission text not null default 'view' check (permission in ('view', 'claim')),
  created_at timestamptz not null default now(),
  unique (list_id, friend_id)
);

create table if not exists public.list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.shared_lists on delete cascade,
  name text not null check (char_length(name) between 1 and 120),
  quantity int not null default 1 check (quantity between 1 and 999),
  notes text,
  status text not null default 'open'
    check (status in ('open', 'claimed', 'bought', 'settled')),
  claimed_by uuid references auth.users on delete set null,
  created_by uuid not null default auth.uid() references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists list_items_list_idx on public.list_items (list_id);

-- Helpers (bypass RLS, always scoped to the caller).
create or replace function public.owns_zone(z uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.zones where id = z and owner_id = auth.uid());
$$;

create or replace function public.owns_list(l uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.shared_lists sl
    join public.zones z on z.id = sl.zone_id
    where sl.id = l and z.owner_id = auth.uid());
$$;

-- 'claim', 'view', or null for the caller on list l.
create or replace function public.list_permission(l uuid)
returns text language sql stable security definer set search_path = '' as $$
  select permission from public.list_access
  where list_id = l and friend_id = auth.uid();
$$;

-- Friends with any access to a list on this zone may read the zone
-- (name, position) so their phone can show it and watch it.
create or replace function public.zone_shared_with_me(z uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.shared_lists sl
    join public.list_access la on la.list_id = sl.id
    where sl.zone_id = z and la.friend_id = auth.uid());
$$;

alter table public.shared_lists enable row level security;
alter table public.list_access enable row level security;
alter table public.list_items enable row level security;

create policy "read lists I own or was given" on public.shared_lists
  for select to authenticated
  using (public.owns_zone(zone_id) or public.list_permission(id) is not null);
create policy "zone owner manages lists" on public.shared_lists
  for all to authenticated
  using (public.owns_zone(zone_id))
  with check (public.owns_zone(zone_id));

create policy "read access rows of my lists or my own" on public.list_access
  for select to authenticated
  using (public.owns_list(list_id) or friend_id = (select auth.uid()));
-- Owner shares only with accepted friends.
create policy "owner manages access" on public.list_access
  for all to authenticated
  using (public.owns_list(list_id))
  with check (public.owns_list(list_id)
              and public.are_friends((select auth.uid()), friend_id));
-- A friend can leave a list.
create policy "friend leaves a list" on public.list_access
  for delete to authenticated
  using (friend_id = (select auth.uid()));

create policy "read items of visible lists" on public.list_items
  for select to authenticated
  using (public.owns_list(list_id) or public.list_permission(list_id) is not null);
create policy "owner or claimers add items" on public.list_items
  for insert to authenticated
  with check (public.owns_list(list_id) or public.list_permission(list_id) = 'claim');
create policy "owner or claimers update items" on public.list_items
  for update to authenticated
  using (public.owns_list(list_id) or public.list_permission(list_id) = 'claim')
  with check (public.owns_list(list_id) or public.list_permission(list_id) = 'claim');
create policy "owner or creator deletes items" on public.list_items
  for delete to authenticated
  using (public.owns_list(list_id) or created_by = (select auth.uid()));

-- Extra read-only policy on zones for friends a list is shared with.
create policy "friends read zones shared with them" on public.zones
  for select to authenticated
  using (public.zone_shared_with_me(id));

-- touch updated_at (function exists from 001)
create trigger shared_lists_touch before update on public.shared_lists
  for each row execute function public.touch_updated_at();
create trigger list_items_touch before update on public.list_items
  for each row execute function public.touch_updated_at();

-- Live updates for list items (Part B).
alter publication supabase_realtime add table public.list_items;
