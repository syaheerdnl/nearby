-- Nearby Phase 3: receipts and settle up. Add-only, safe to re-run.
-- Flow: the friend who bought an item adds a receipt (photo + amount),
-- the list owner pays them outside the app and marks it paid, which
-- settles the item. Nearby never moves money.

-- ---------- Tables ----------

create table if not exists public.receipts (
  id uuid primary key default gen_random_uuid(),
  list_item_id uuid not null unique references public.list_items on delete cascade,
  uploaded_by uuid not null default auth.uid() references auth.users on delete cascade,
  -- Storage path in the private 'receipts' bucket (name kept from the CLAUDE.md
  -- schema); the app turns it into a short-lived signed URL to show it.
  image_url text not null check (char_length(image_url) between 1 and 300),
  amount numeric(10,2) not null check (amount > 0 and amount < 100000),
  created_at timestamptz not null default now()
);

create table if not exists public.payment_records (
  id uuid primary key default gen_random_uuid(),
  receipt_id uuid not null unique references public.receipts on delete cascade,
  payer_id uuid not null default auth.uid() references auth.users on delete cascade,
  payee_id uuid not null references auth.users on delete cascade,
  method text check (method in ('qr', 'bank')),
  settled boolean not null default true,
  settled_at timestamptz not null default now(),
  check (payer_id <> payee_id)
);

-- Kept apart from profiles: profiles is readable by every signed-in user
-- (username search), bank details must only reach friends.
create table if not exists public.payment_details (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  bank_name text check (char_length(bank_name) <= 60),
  account_name text check (char_length(account_name) <= 80),
  account_number text check (account_number ~ '^[0-9 -]{4,30}$'),
  qr_path text check (char_length(qr_path) <= 300),
  updated_at timestamptz not null default now()
);

-- ---------- Helpers (bypass RLS, scoped to the caller) ----------

-- The list an item belongs to, so policies can reuse owns_list/list_permission.
create or replace function public.item_list(i uuid)
returns uuid language sql stable security definer set search_path = '' as $$
  select list_id from public.list_items where id = i;
$$;

create or replace function public.can_see_list(l uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select public.owns_list(l) or public.list_permission(l) is not null;
$$;

-- ---------- RLS ----------

alter table public.receipts enable row level security;
alter table public.payment_records enable row level security;
alter table public.payment_details enable row level security;

drop policy if exists "list members read receipts" on public.receipts;
create policy "list members read receipts" on public.receipts
  for select to authenticated
  using (public.can_see_list(public.item_list(list_item_id)));

-- Only the buyer, only for an item they bought.
drop policy if exists "buyer adds receipt" on public.receipts;
create policy "buyer adds receipt" on public.receipts
  for insert to authenticated
  with check (
    uploaded_by = (select auth.uid())
    and exists (select 1 from public.list_items li
                where li.id = list_item_id
                  and li.status = 'bought'
                  and li.claimed_by = (select auth.uid())));

-- The buyer can fix a receipt (photo/amount) until it is paid.
drop policy if exists "buyer edits unpaid receipt" on public.receipts;
create policy "buyer edits unpaid receipt" on public.receipts
  for update to authenticated
  using (uploaded_by = (select auth.uid())
         and not exists (select 1 from public.payment_records pr
                         where pr.receipt_id = receipts.id))
  with check (uploaded_by = (select auth.uid()));
revoke update on public.receipts from authenticated, anon;
grant update (image_url, amount) on public.receipts to authenticated;

drop policy if exists "payer and payee read payments" on public.payment_records;
create policy "payer and payee read payments" on public.payment_records
  for select to authenticated
  using (payer_id = (select auth.uid()) or payee_id = (select auth.uid()));

-- Only the list owner pays, and only the receipt's uploader can be paid.
drop policy if exists "owner records payment" on public.payment_records;
create policy "owner records payment" on public.payment_records
  for insert to authenticated
  with check (
    payer_id = (select auth.uid())
    and exists (select 1 from public.receipts r
                where r.id = receipt_id
                  and r.uploaded_by = payee_id
                  and public.owns_list(public.item_list(r.list_item_id))));
-- No update/delete policies: a payment record is final.

drop policy if exists "me and friends read payment details" on public.payment_details;
create policy "me and friends read payment details" on public.payment_details
  for select to authenticated
  using (user_id = (select auth.uid()) or public.is_my_friend(user_id));
drop policy if exists "I manage my payment details" on public.payment_details;
create policy "I manage my payment details" on public.payment_details
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- ---------- Settling ----------

-- A payment settles its item in the same transaction.
create or replace function public.settle_item_on_payment() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('nearby.settling', 'on', true);
  update public.list_items li set status = 'settled', updated_at = now()
  from public.receipts r
  where r.id = new.receipt_id and li.id = r.list_item_id;
  perform set_config('nearby.settling', 'off', true);
  return new;
end $$;
drop trigger if exists payment_settles_item on public.payment_records;
create trigger payment_settles_item after insert on public.payment_records
  for each row execute function public.settle_item_on_payment();

-- Settled is final, and only a payment can settle an item.
create or replace function public.list_items_settled_guard() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status = 'settled' then
    raise exception 'this item is already paid for';
  end if;
  if new.status = 'settled'
     and coalesce(current_setting('nearby.settling', true), 'off') <> 'on' then
    raise exception 'items are settled by recording a payment';
  end if;
  return new;
end $$;
drop trigger if exists list_items_settled_guard on public.list_items;
create trigger list_items_settled_guard before update on public.list_items
  for each row execute function public.list_items_settled_guard();

-- ---------- Storage (private buckets, signed URLs in the app) ----------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('payment-qr', 'payment-qr', false, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- receipts/{list_id}/{item_id}/{file}: list members read, the buyer uploads.
drop policy if exists "list members read receipt photos" on storage.objects;
create policy "list members read receipt photos" on storage.objects
  for select to authenticated
  using (bucket_id = 'receipts'
         and public.can_see_list(((storage.foldername(name))[1])::uuid));
drop policy if exists "buyer uploads receipt photo" on storage.objects;
create policy "buyer uploads receipt photo" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts'
              and exists (select 1 from public.list_items li
                          where li.id = ((storage.foldername(name))[2])::uuid
                            and li.list_id = ((storage.foldername(name))[1])::uuid
                            and li.claimed_by = (select auth.uid())));

-- payment-qr/{user_id}/{file}: I and my friends read, only I write.
drop policy if exists "me and friends read payment qr" on storage.objects;
create policy "me and friends read payment qr" on storage.objects
  for select to authenticated
  using (bucket_id = 'payment-qr'
         and (((storage.foldername(name))[1])::uuid = (select auth.uid())
              or public.is_my_friend(((storage.foldername(name))[1])::uuid)));
drop policy if exists "I upload my payment qr" on storage.objects;
create policy "I upload my payment qr" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'payment-qr'
              and ((storage.foldername(name))[1])::uuid = (select auth.uid()));
drop policy if exists "I replace my payment qr" on storage.objects;
create policy "I replace my payment qr" on storage.objects
  for update to authenticated
  using (bucket_id = 'payment-qr'
         and ((storage.foldername(name))[1])::uuid = (select auth.uid()));
drop policy if exists "I delete my payment qr" on storage.objects;
create policy "I delete my payment qr" on storage.objects
  for delete to authenticated
  using (bucket_id = 'payment-qr'
         and ((storage.foldername(name))[1])::uuid = (select auth.uid()));

-- Realtime: the list screen already listens to list_items; settling updates
-- that row, so payments show up live without a new channel.
