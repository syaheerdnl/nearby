-- Fix for 006: receipt photo uploads were always refused (RLS 403).
-- In the upload policy, the unqualified `name` inside the subquery on
-- list_items resolved to list_items.name (the item's name) instead of the
-- uploaded file's path, so the folder check never matched. Qualify it.
-- Replaces only this one policy. Safe to re-run.

drop policy if exists "buyer uploads receipt photo" on storage.objects;
create policy "buyer uploads receipt photo" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'receipts'
              and exists (select 1 from public.list_items li
                          where li.id = ((storage.foldername(objects.name))[2])::uuid
                            and li.list_id = ((storage.foldername(objects.name))[1])::uuid
                            and li.claimed_by = (select auth.uid())));
