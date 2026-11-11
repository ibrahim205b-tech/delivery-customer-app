-- =====================================================================
-- WASEL | تخزين الصور (Supabase Storage)
-- =====================================================================
-- حاوية عامة للقراءة "media". الرفع مقيّد بالمسار:
--   merchants/<merchant_id>/...  ← صاحب المحل أو الإدارة
--   promotions/...               ← الإدارة
--   bookings/<user_id>/...       ← المستخدم نفسه (صور طلب الخدمة)

insert into storage.buckets (id, name, public)
values ('media', 'media', true)
on conflict (id) do nothing;

create or replace function public.can_upload_media(object_name text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare parts text[] := string_to_array(object_name, '/');
begin
  if auth.uid() is null then return false; end if;
  if is_admin() then return true; end if;
  if parts[1] = 'merchants' and array_length(parts, 1) >= 3 then
    begin
      return owns_merchant(parts[2]::uuid);
    exception when invalid_text_representation then
      return false;
    end;
  end if;
  if parts[1] = 'bookings' and array_length(parts, 1) >= 3 then
    return parts[2] = auth.uid()::text;
  end if;
  return false;
end $$;

create policy media_read on storage.objects for select
  using (bucket_id = 'media');
create policy media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and public.can_upload_media(name));
create policy media_update on storage.objects for update to authenticated
  using (bucket_id = 'media' and public.can_upload_media(name))
  with check (bucket_id = 'media' and public.can_upload_media(name));
create policy media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'media' and public.can_upload_media(name));
