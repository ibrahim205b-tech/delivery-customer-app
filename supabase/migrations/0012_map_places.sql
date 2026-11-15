-- =====================================================================
-- WASEL MAPS | المرحلة 4: نقاط الاستدلال والملاحظات الجغرافية (map_places)
--
-- الحالات: draft (مسودة/اقتراح) · approved (معتمد) · rejected (مرفوض)
-- القواعد:
-- 1) أي مستخدم يقترح نقطة (suggest_map_place) → تدخل كـ draft دائماً. لا اعتماد تلقائي.
-- 2) الاعتماد/الرفض للإدارة فقط (admin_review_map_place) ويُسجَّل من راجع ووقته.
-- 3) الرفض يحتاج سبباً مكتوباً.
-- 4) الزبون والسائق يقرؤون النقاط المعتمدة فقط. مسوداتهم يشوفونها هم فقط.
-- 5) لا كتابة مباشرة على الجدول من أي دور تطبيقي؛ كل الكتابة عبر دوال محددة.
-- 6) الإحداثيات يجب أن تقع ضمن حدود العراق التقريبية (تمنع الخطأ الواضح).
-- لا تُضاف أي نقطة تلقائياً من هذا الملف: الجدول فارغ، والإدارة تضيف ما تتحقق منه.
-- التأثير: جدول جديد وإضافات دوال، لا يغيّر أي جدول قائم.
-- =====================================================================

create table if not exists map_places (
  id            uuid primary key default gen_random_uuid(),
  name_ar       text not null check (char_length(btrim(name_ar)) between 2 and 120),
  kind          text not null check (kind in ('landmark', 'district', 'street', 'store', 'service_point', 'hard_access', 'driver_note')),
  description   text not null default '' check (char_length(description) <= 500),
  lat           double precision not null check (lat between 29 and 38),
  lng           double precision not null check (lng between 38 and 49),
  area_id       uuid references service_areas (id) on delete set null,
  status        text not null default 'draft' check (status in ('draft', 'approved', 'rejected')),
  rejection_reason text not null default '',
  created_by    uuid references users (id) on delete set null,
  reviewed_by   uuid references users (id) on delete set null,
  reviewed_at   timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (status <> 'approved' or (reviewed_by is not null and reviewed_at is not null)),
  check (status <> 'rejected' or char_length(btrim(rejection_reason)) >= 5)
);
create index if not exists map_places_status_idx on map_places (status);
create index if not exists map_places_area_idx on map_places (area_id);

alter table map_places enable row level security;

drop policy if exists map_places_read on map_places;
create policy map_places_read on map_places for select to authenticated
  using (status = 'approved' or created_by = auth.uid() or is_admin());

-- الكتابة المباشرة ممنوعة لكل الأدوار التطبيقية
revoke all on map_places from authenticated, anon;
grant select on map_places to authenticated;
grant all on map_places to service_role;

-- ---------------------------------------------------------------------
-- اقتراح نقطة: تدخل كمسودة دائماً
-- ---------------------------------------------------------------------
create or replace function suggest_map_place(
  p_name text, p_kind text, p_lat double precision, p_lng double precision, p_description text default ''
) returns map_places language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r map_places; aid uuid;
begin
  if p_kind not in ('landmark', 'district', 'street', 'store', 'service_point', 'hard_access', 'driver_note') then raise exception 'invalid_kind'; end if;
  aid := area_for_point(p_lat, p_lng);
  insert into map_places (name_ar, kind, description, lat, lng, area_id, status, created_by)
  values (btrim(coalesce(p_name, '')), p_kind, left(btrim(coalesce(p_description, '')), 500), p_lat, p_lng, aid, 'draft', uid)
  returning * into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- الإدارة: إضافة/تعديل مسودة أو نقطة، ثم المراجعة
-- ---------------------------------------------------------------------
create or replace function admin_save_map_place(
  p_id uuid, p_name text, p_kind text, p_lat double precision, p_lng double precision, p_description text default ''
) returns map_places language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r map_places; aid uuid;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_kind not in ('landmark', 'district', 'street', 'store', 'service_point', 'hard_access', 'driver_note') then raise exception 'invalid_kind'; end if;
  aid := area_for_point(p_lat, p_lng);
  if p_id is null then
    insert into map_places (name_ar, kind, description, lat, lng, area_id, status, created_by)
    values (btrim(coalesce(p_name, '')), p_kind, left(btrim(coalesce(p_description, '')), 500), p_lat, p_lng, aid, 'draft', uid)
    returning * into r;
  else
    -- التعديل يعيد النقطة لمسودة حتى تُراجَع من جديد (ما نعتمد تغييراً لم نراجعه)
    update map_places set name_ar = btrim(coalesce(p_name, '')), kind = p_kind,
           description = left(btrim(coalesce(p_description, '')), 500), lat = p_lat, lng = p_lng, area_id = aid,
           status = 'draft', reviewed_by = null, reviewed_at = null, rejection_reason = '', updated_at = now()
     where id = p_id returning * into r;
    if not found then raise exception 'place_not_found'; end if;
  end if;
  return r;
end $$;

create or replace function admin_review_map_place(p_id uuid, p_status text, p_reason text default '')
returns map_places language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r map_places;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('approved', 'rejected') then raise exception 'invalid_status'; end if;
  if p_status = 'rejected' and char_length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'reason_required'; end if;
  update map_places set status = p_status,
         reviewed_by = uid, reviewed_at = now(),
         rejection_reason = case when p_status = 'rejected' then btrim(p_reason) else '' end,
         updated_at = now()
   where id = p_id returning * into r;
  if not found then raise exception 'place_not_found'; end if;
  return r;
end $$;

create or replace function admin_delete_map_place(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  -- نحذف المسودات والمرفوضة فقط. المعتمدة تُرفض أولاً حتى يبقى أثر المراجعة.
  delete from map_places where id = p_id and status <> 'approved';
  if not found then raise exception 'cannot_delete_approved_or_missing'; end if;
end $$;

grant execute on function suggest_map_place(text, text, double precision, double precision, text) to authenticated;
grant execute on function admin_save_map_place(uuid, text, text, double precision, double precision, text) to authenticated;
grant execute on function admin_review_map_place(uuid, text, text) to authenticated;
grant execute on function admin_delete_map_place(uuid) to authenticated;

notify pgrst, 'reload schema';
