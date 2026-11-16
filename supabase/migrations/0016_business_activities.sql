-- =====================================================================
-- WASEL SUPER APP | أنواع النشاط تصير قابلة للإدارة من لوحة الإدارة
--
-- 1) جدول business_activities: كل نشاط له مفتاح ثابت واسم عربي ومجموعة وترتيب وحالة تفعيل.
-- 2) merchants.business_type يرتبط بهذا الجدول (مفتاح أجنبي) بدل القائمة الثابتة في القيد.
--    الأنواع الحالية تُزرع هنا كما هي، فلا يتغير أي صاحب حساب.
-- 3) merchant_set_business_type يرفض نشاطاً غير مفعّل.
-- التأثير: إضافة جدول وقيد، ولا يُحذف شيء. الإدارة فقط تكتب في الجدول (RLS).
-- =====================================================================

create table if not exists business_activities (
  key        text primary key,
  label      text not null,
  group_name text not null default 'أنشطة أخرى',
  sort       int  not null default 0,
  is_active  boolean not null default true
);

alter table business_activities enable row level security;
drop policy if exists activities_read on business_activities;
create policy activities_read on business_activities for select to authenticated using (is_active or is_admin());
drop policy if exists activities_admin on business_activities;
create policy activities_admin on business_activities for all to authenticated using (is_admin()) with check (is_admin());
grant select, insert, update, delete on business_activities to authenticated;
grant all on business_activities to service_role;

insert into business_activities (key, label, group_name, sort) values
  ('store',              'متجر',            'المحلات والمطاعم', 10),
  ('restaurant',         'مطعم',            'المحلات والمطاعم', 20),
  ('pitch_owner',        'صاحب ملعب خماسي', 'الحجوزات والمواعيد', 30),
  ('clinic',             'عيادة طبية',       'الحجوزات والمواعيد', 40),
  ('venue',              'صالة',            'الحجوزات والمواعيد', 50),
  ('provider',           'مقدم خدمة',        'الخدمات المنزلية والصيانة', 60),
  ('technician',         'فني',             'الخدمات المنزلية والصيانة', 70),
  ('mobile_repair',      'صيانة موبايلات',   'الخدمات المنزلية والصيانة', 80),
  ('cleaning_company',   'شركة تنظيف',       'الخدمات المنزلية والصيانة', 90),
  ('maintenance_center', 'مركز صيانة',       'الخدمات المنزلية والصيانة', 100),
  ('library',            'مكتبة',           'الخدمات المكتبية والتعليم', 110),
  ('institute',          'معهد',            'الخدمات المكتبية والتعليم', 120),
  ('print_shop',         'مطبعة',           'الخدمات المكتبية والتعليم', 130),
  ('employer',           'صاحب عمل',        'الخدمات المكتبية والتعليم', 140),
  ('photographer',       'مصور',            'الإعلام والمناسبات', 150),
  ('rental_center',      'مركز تأجير',       'الإعلام والمناسبات', 160),
  ('transport_company',  'شركة نقل',         'النقل والسفر', 170),
  ('travel_agency',      'شركة سياحة',       'النقل والسفر', 180)
on conflict (key) do nothing;

alter table merchants drop constraint if exists merchants_business_type_check;
alter table merchants drop constraint if exists merchants_business_type_fkey;
alter table merchants add constraint merchants_business_type_fkey
  foreign key (business_type) references business_activities (key);

create or replace function merchant_set_business_type(p_merchant_id uuid, p_type text)
returns merchants language plpgsql security definer set search_path = public as $$
declare r merchants;
begin
  if not (owns_merchant(p_merchant_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if not exists (select 1 from business_activities where key = p_type and is_active) then
    raise exception 'business_type_unknown';
  end if;
  if not is_admin() and exists (
       select 1 from service_requests q
        where q.provider_id = p_merchant_id and q.status in ('requested', 'accepted', 'in_progress')) then
    raise exception 'open_requests';
  end if;
  update merchants set business_type = p_type, activity_chosen = true
   where id = p_merchant_id returning * into r;
  if not found then raise exception 'merchant_not_found'; end if;
  return r;
end $$;

notify pgrst, 'reload schema';
