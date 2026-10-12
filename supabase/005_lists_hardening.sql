-- Nearby Phase 2 hardening (from code review). Safe to run once after 004.

-- S1: accepting a request may only flip status; no rewriting the pair.
revoke update on public.friends from authenticated, anon;
grant update (status) on public.friends to authenticated;

-- S2: unfriending removes list access both ways.
create or replace function public.revoke_access_on_unfriend() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.list_access la
  using public.shared_lists sl join public.zones z on z.id = sl.zone_id
  where la.list_id = sl.id
    and ((z.owner_id = old.user_id   and la.friend_id = old.friend_id)
      or (z.owner_id = old.friend_id and la.friend_id = old.user_id));
  return old;
end $$;
drop trigger if exists friends_revoke_access on public.friends;
create trigger friends_revoke_access after delete on public.friends
  for each row execute function public.revoke_access_on_unfriend();

-- S3: claimers can't rewrite list_id/created_by, insert as someone else,
-- or claim on behalf of another user.
revoke update on public.list_items from authenticated, anon;
grant update (name, quantity, notes, status, claimed_by) on public.list_items to authenticated;
drop policy if exists "owner or claimers add items" on public.list_items;
create policy "owner or claimers add items" on public.list_items for insert to authenticated
  with check (created_by = (select auth.uid())
    and (public.owns_list(list_id) or public.list_permission(list_id) = 'claim'));
create or replace function public.list_items_claim_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.claimed_by is distinct from old.claimed_by and new.claimed_by is not null
     and new.claimed_by <> auth.uid() then
    raise exception 'can only claim for yourself';
  end if;
  return new;
end $$;
drop trigger if exists list_items_claim_guard on public.list_items;
create trigger list_items_claim_guard before update on public.list_items
  for each row execute function public.list_items_claim_guard();

-- S4: friendship check scoped to the caller (no public friend-graph probe).
create or replace function public.is_my_friend(b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.friends f where f.status = 'accepted'
    and least(f.user_id, f.friend_id) = least(auth.uid(), b)
    and greatest(f.user_id, f.friend_id) = greatest(auth.uid(), b));
$$;
drop policy if exists "owner manages access" on public.list_access;
create policy "owner manages access" on public.list_access for all to authenticated
  using (public.owns_list(list_id))
  with check (public.owns_list(list_id) and public.is_my_friend(friend_id));
drop function if exists public.are_friends(uuid, uuid);

-- S5: one shared list per place (the app assumes it).
create unique index if not exists shared_lists_zone_uidx on public.shared_lists (zone_id);
