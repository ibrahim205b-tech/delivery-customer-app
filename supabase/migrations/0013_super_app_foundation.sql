-- =====================================================================
-- WASEL SUPER APP | المرحلة 1: الأساس (تصنيفات الخدمات، الكتالوج، نوع النشاط، البحث)
--
-- 1) service_groups: تصنيفات «اكتشف خدمات واصل» (10 تصنيفات).
-- 2) services: كتالوج الخدمات. كل خدمة لها "محرك" (engine) يحدد كيف تُنفَّذ:
--    order = طلب متجر، task = مهمة مندوب، ride = رحلة، booking = حجز/خدمة، none = بانتظار التنفيذ.
--    الخدمة لا تظهر للزبون إلا إذا فعّلتها الإدارة (is_active)، وهكذا لا تظهر واجهة بلا تنفيذ.
-- 3) merchants.business_type: نوع النشاط (متجر، مزود خدمة، ملعب، مصور...). الحالي يبقى كما هو.
-- 4) إعدادات العمولة لكل خدمة في app_settings (service_commissions) وقابلة للتعديل من الإدارة.
--    القيم الافتراضية بدون نسب مخترعة: كل خدمة بنموذج "بدون عمولة" حتى تحدد الإدارة النموذج والقيمة.
-- التأثير: إضافة جداول وأعمدة وتعبئة نوع النشاط للمحلات القائمة. لا حذف لأي بيانات أو وظائف.
-- =====================================================================

-- ---------------------------------------------------------------------
-- التصنيفات
-- ---------------------------------------------------------------------
create table if not exists service_groups (
  id          text primary key,
  name_ar     text not null,
  sort_order  int not null default 0,
  is_active   boolean not null default true
);

insert into service_groups (id, name_ar, sort_order) values
  ('bookings',  'الحجوزات والمواعيد', 1),
  ('jobs',      'الوظائف وفرص العمل', 2),
  ('transport', 'النقل والتوصيل', 3),
  ('shopping',  'التسوق والمتاجر', 4),
  ('home',      'الخدمات المنزلية والصيانة', 5),
  ('office',    'الخدمات المكتبية والمعاملات', 6),
  ('education', 'التعليم والمعاهد', 7),
  ('events',    'التصوير والمناسبات', 8),
  ('travel',    'السفر والسياحة', 9),
  ('finance',   'الخدمات المالية والتسليم النقدي', 10)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- الكتالوج
-- ---------------------------------------------------------------------
create table if not exists services (
  id                 text primary key,
  group_id           text not null references service_groups (id) on delete restrict,
  name_ar            text not null check (char_length(btrim(name_ar)) between 2 and 80),
  description        text not null default '' check (char_length(description) <= 300),
  keywords           text not null default '' check (char_length(keywords) <= 300),
  engine             text not null default 'none' check (engine in ('none', 'order', 'task', 'ride', 'booking')),
  requires_approval  boolean not null default true,
  is_active          boolean not null default false,
  sort_order         int not null default 0,
  updated_at         timestamptz not null default now()
);
create index if not exists services_group_idx on services (group_id, sort_order);

-- الخدمات الأولية: كلها معطّلة حتى تُنفَّذ. الخدمات التي تعمل حالياً مرتبطة بمحركاتها الفعلية.
insert into services (id, group_id, name_ar, description, keywords, engine, is_active, sort_order) values
  -- تعمل حالياً على المحركات القائمة
  ('parcel_delivery', 'transport', 'توصيل الأمانات', 'توصيل غرض بين شخصين: استلام وتسليم وصورة وعنوان', 'توصيل امانات غرض طرد', 'task', true, 1),
  ('courier_errand',  'transport', 'مندوب يشتري لك', 'مندوب يذهب يشتري أو يستلم لك شي', 'مندوب مشتريات شراء', 'task', true, 2),
  ('home_services',   'home',      'الصيانة المنزلية والحرف', 'فنيون للكهرباء والسباكة والنجارة وغيرها', 'صيانة سباكة كهرباء نجارة فني', 'booking', true, 1),
  ('restaurants',     'shopping',  'المطاعم', 'طلب طعام من المطاعم القريبة', 'طعام مطعم اكل', 'order', true, 1),
  ('stores',          'shopping',  'المحلات والسوبرماركت', 'مشتريات من المحلات والسوبرماركت', 'محل سوبرماركت بقالة', 'order', true, 2),
  -- مخطط لها: معطّلة حتى تُبنى وتُختبر
  ('pitch_booking',   'bookings',  'حجز ملاعب الخماسي', 'حجز ملعب بالساعة مع تأكيد صاحب الملعب', 'ملعب خماسي كرة حجز', 'none', false, 1),
  ('doctor_booking',  'bookings',  'حجز الأطباء والمضمدين', 'حجز إلكتروني أو حجز دور حضورياً', 'طبيب دكتور حجز عيادة مضمد', 'none', false, 2),
  ('restaurant_booking', 'bookings', 'حجز المطاعم والصالات', 'حجز صالة وتجهيز طلب مسبق', 'حجز مطعم صالة عزيمة', 'none', false, 3),
  ('institute_seats', 'education', 'المعاهد وحجز المقاعد', 'دليل المعاهد وحجز المقاعد في الدورات', 'معهد دورة مقعد تعليم', 'none', false, 1),
  ('photographers',   'events',    'المصورون', 'حجز مصور للمباريات والأعراس والمنتجات', 'مصور تصوير فيديو عرس', 'none', false, 1),
  ('documents',       'office',    'معاملاتك علينا', 'استنساخ وطباعة وتوصيل المستمسكات', 'معاملة مستمسكات استنساخ طباعة', 'none', false, 1),
  ('print_custom',    'shopping',  'الطباعة حسب الطلب', 'طباعة ملابس وتصاميم شخصية', 'طباعة تصميم ملابس تيشيرت', 'none', false, 4),
  ('clothing_store',  'shopping',  'سوق الملابس', 'متجر ملابس متعدد التجار', 'ملابس احذية حقائب', 'order', false, 5),
  ('device_installments', 'shopping', 'الأجهزة بالتقسيط', 'موبايلات وحاسبات وأجهزة بالتقسيط من التجار', 'موبايل حاسبة تقسيط جهاز', 'order', false, 6),
  ('school_lines',    'transport', 'خطوط المدارس', 'اشتراكات نقل دورية للمدارس', 'مدرسة خط نقل طالب', 'ride', false, 4),
  ('staff_lines',     'transport', 'خطوط الموظفين', 'اشتراكات نقل دورية للموظفين', 'موظف خط نقل دوام', 'ride', false, 5),
  ('heavy_transport', 'transport', 'كيا الحمل والستوت', 'نقل الأثاث والحمولات الكبيرة', 'كيا حمل ستوت نقل اثاث', 'ride', false, 6),
  ('package_delivery_big', 'transport', 'الأغراض الكبيرة', 'توصيل طرود متوسطة وكبيرة', 'طرد كبير شحن', 'task', false, 7),
  ('phone_repair',    'home',      'صيانة الموبايلات من المنزل', 'استلام الجهاز وتشخيصه وإعادته', 'موبايل تصليح صيانة شاشة', 'task', false, 2),
  ('carpet_cleaning', 'home',      'غسل الفرشات والسجاد', 'تنظيف الفرشات والسجاد والكنب والستائر', 'غسل فرشة سجاد تنظيف كنب', 'booking', false, 3),
  ('ps_rental',       'events',    'تأجير أجهزة البلايستيشن', 'تأجير من المراكز المتعاقدة مع تأمين مسترد', 'بلايستيشن ألعاب تأجير', 'booking', false, 2),
  ('digital_topup',   'finance',   'الرصيد والبطاقات الإلكترونية', 'تعبئة رصيد وبطاقات رقمية', 'رصيد تعبئة كارت بطاقة', 'order', false, 1),
  ('salary_delivery', 'finance',   'راتبك لباب بيتك', 'استلام المبلغ المستحق من المكتبة وتسليمه للبيت', 'راتب مبلغ تسليم', 'task', false, 2),
  ('jobs',            'jobs',      'وظائف واصل', 'منصة توظيف محلية: إعلانات وطلبات تقديم', 'وظيفة توظيف عمل شغل', 'none', false, 1),
  ('travel_campaigns','travel',    'السفر والسياحة', 'حملات سياحية موثّقة', 'سفر سياحة رحلة حملة', 'booking', false, 1)
on conflict (id) do nothing;

-- ---------------------------------------------------------------------
-- نوع النشاط للتاجر/مقدم الخدمة
-- ---------------------------------------------------------------------
alter table merchants add column if not exists business_type text not null default 'store'
  check (business_type in ('store', 'restaurant', 'provider', 'pitch_owner', 'venue', 'library', 'institute',
                           'photographer', 'technician', 'employer', 'maintenance_center', 'rental_center', 'travel_agency'));

-- المحلات القائمة مرتبطة بتصنيفها الحالي: مزودو الخدمات المنزلية نوع provider، والباقي store
update merchants set business_type = 'provider' where category_id = 'home_services' and business_type = 'store';
update merchants set business_type = 'restaurant' where category_id = 'restaurants' and business_type = 'store';

-- ---------------------------------------------------------------------
-- الصلاحيات
-- ---------------------------------------------------------------------
alter table service_groups enable row level security;
alter table services enable row level security;

drop policy if exists service_groups_read on service_groups;
create policy service_groups_read on service_groups for select to authenticated using (true);
drop policy if exists service_groups_admin on service_groups;
create policy service_groups_admin on service_groups for all to authenticated using (is_admin()) with check (is_admin());

-- الزبون والمستخدمون يقرؤون الخدمات المفعّلة فقط. الإدارة ترى الكل.
drop policy if exists services_read on services;
create policy services_read on services for select to authenticated using (is_active or is_admin());
drop policy if exists services_admin on services;
create policy services_admin on services for all to authenticated using (is_admin()) with check (is_admin());

grant select on service_groups, services to authenticated;
grant all on service_groups, services to service_role;

-- ---------------------------------------------------------------------
-- الإدارة: تشغيل/إيقاف وتعديل الخدمة (بدون أي تغيير آخر)
-- ---------------------------------------------------------------------
create or replace function admin_update_service(
  p_id text, p_is_active boolean, p_name_ar text default null, p_description text default null
) returns services language plpgsql security definer set search_path = public as $$
declare r services;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_is_active and not exists (select 1 from services where id = p_id and engine <> 'none') then
    -- لا نفعّل خدمة بلا محرك تنفيذ: هذا يخفي وعداً لا نقدر على الوفاء به
    raise exception 'service_not_implemented';
  end if;
  update services set is_active = p_is_active,
         name_ar = coalesce(nullif(btrim(p_name_ar), ''), name_ar),
         description = coalesce(p_description, description),
         updated_at = now()
   where id = p_id returning * into r;
  if not found then raise exception 'service_not_found'; end if;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- البحث الموحد: خدمات مفعّلة + محلات/مقدمو خدمات معتمدون بالاسم أو الوصف
-- ---------------------------------------------------------------------
create or replace function search_services(p_query text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q text := '%' || btrim(coalesce(p_query, '')) || '%';
begin
  if char_length(btrim(coalesce(p_query, ''))) < 2 then return jsonb_build_object('services', '[]'::jsonb, 'merchants', '[]'::jsonb); end if;
  return jsonb_build_object(
    'services', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name_ar, 'group', s.group_id, 'engine', s.engine, 'description', s.description) order by s.sort_order), '[]'::jsonb)
                   from services s
                  where s.is_active and (s.name_ar ilike q or s.keywords ilike q or s.description ilike q)),
    'merchants', (select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'name', m.name, 'business_type', m.business_type, 'category_id', m.category_id) order by m.name), '[]'::jsonb)
                    from (select * from merchants where status = 'approved' and name ilike q limit 20) m)
  );
end $$;

-- ---------------------------------------------------------------------
-- إعدادات العمولة لكل خدمة (قابلة للتعديل من الإدارة، بدون نسب افتراضية مخترعة)
--   model: free (مجانية) | percent (نسبة من المبلغ) | fixed (مبلغ ثابت لكل عملية)
-- ---------------------------------------------------------------------
insert into app_settings (key, value)
select 'service_commissions', jsonb_object_agg(id, jsonb_build_object('model', 'free', 'value', 0)) from services
on conflict (key) do nothing;

create or replace function admin_set_service_commission(p_service_id text, p_model text, p_value numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur jsonb;
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_model not in ('free', 'percent', 'fixed') then raise exception 'invalid_model'; end if;
  if p_value is null or p_value < 0 then raise exception 'invalid_value'; end if;
  if p_model = 'percent' and p_value > 50 then raise exception 'invalid_percent'; end if;
  if not exists (select 1 from services where id = p_service_id) then raise exception 'service_not_found'; end if;
  select value into cur from app_settings where key = 'service_commissions';
  cur := coalesce(cur, '{}'::jsonb) || jsonb_build_object(p_service_id, jsonb_build_object('model', p_model, 'value', p_value));
  insert into app_settings (key, value, updated_at) values ('service_commissions', cur, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  return cur -> p_service_id;
end $$;

grant execute on function admin_update_service(text, boolean, text, text) to authenticated;
grant execute on function search_services(text) to authenticated;
grant execute on function admin_set_service_commission(text, text, numeric) to authenticated;

notify pgrst, 'reload schema';
