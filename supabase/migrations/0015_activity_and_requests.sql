-- =====================================================================
-- WASEL SUPER APP | الخطوة 1 و2: اختيار صاحب الخدمة لنشاطه + طلب عام لكل الخدمات
--
-- 1) merchants.activity_chosen: هل اختار صاحب الحساب نشاطه بنفسه؟
--    الحسابات الحالية تعتبر مختارة (لا تُجبر على الاختيار من جديد).
-- 2) أنواع نشاط إضافية (عيادة، مطبعة، مصلح موبايل، شركة تنظيف، شركة نقل).
-- 3) merchant_set_business_type: صاحب الحساب أو الإدارة يختار النشاط.
--    ممنوع تغييره إذا كان عنده طلبات خدمات مفتوحة.
-- 4) service_provider_types: أي نوع نشاط يقدم أي خدمة.
-- 5) svc_create_request: الزبون يرسل طلباً عاماً لمقدم خدمة مناسب (payload حسب الخدمة).
-- 6) service_set_amount: مقدم الخدمة يحدد السعر قبل القبول.
-- التأثير: إضافة أعمدة وجداول ودوال، وقيد أنواع النشاط يتوسع (لا يُحذف شيء).
-- =====================================================================

alter table merchants add column if not exists activity_chosen boolean not null default false;
update merchants set activity_chosen = true where activity_chosen = false;

alter table merchants drop constraint if exists merchants_business_type_check;
alter table merchants add constraint merchants_business_type_check check (business_type in (
  'store', 'restaurant', 'provider', 'pitch_owner', 'venue', 'library', 'institute',
  'photographer', 'technician', 'employer', 'maintenance_center', 'rental_center', 'travel_agency',
  'clinic', 'print_shop', 'mobile_repair', 'cleaning_company', 'transport_company'
));

-- ---------------------------------------------------------------------
-- أنواع الخدمة لكل نشاط
-- ---------------------------------------------------------------------
create table if not exists service_provider_types (
  service_id    text not null references services (id) on delete cascade,
  business_type text not null,
  primary key (service_id, business_type)
);
alter table service_provider_types enable row level security;
drop policy if exists spt_read on service_provider_types;
create policy spt_read on service_provider_types for select to authenticated using (true);
grant select on service_provider_types to authenticated;
grant all on service_provider_types to service_role;

insert into service_provider_types (service_id, business_type) values
  ('clothing_store', 'store'), ('device_installments', 'store'),
  ('print_custom', 'print_shop'),
  ('phone_repair', 'mobile_repair'),
  ('carpet_cleaning', 'cleaning_company'),
  ('photographers', 'photographer'),
  ('institute_seats', 'institute'),
  ('documents', 'library'),
  ('ps_rental', 'rental_center'),
  ('heavy_transport', 'transport_company'),
  ('travel_campaigns', 'travel_agency'),
  ('doctor_booking', 'clinic'),
  ('restaurant_booking', 'restaurant'),
  ('restaurant_booking', 'venue'),
  ('home_services', 'provider'),
  ('home_services', 'technician')
on conflict do nothing;

-- ---------------------------------------------------------------------
-- اختيار النشاط
-- ---------------------------------------------------------------------
create or replace function merchant_set_business_type(p_merchant_id uuid, p_type text)
returns merchants language plpgsql security definer set search_path = public as $$
declare r merchants;
begin
  if not (owns_merchant(p_merchant_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
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

-- ---------------------------------------------------------------------
-- الطلب العام: الزبون يطلب خدمة من مقدم مناسب
-- ---------------------------------------------------------------------
create or replace function svc_create_request(
  p_service_id text, p_provider_id uuid, p_payload jsonb, p_client_request_id uuid
) returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests; m merchants; sv services;
begin
  select * into sv from services where id = p_service_id;
  if not found or not sv.is_active then raise exception 'service_inactive'; end if;
  if sv.engine = 'none' then raise exception 'service_not_implemented'; end if;
  if p_client_request_id is not null then
    select * into r from service_requests where client_request_id = p_client_request_id and customer_id = uid;
    if found then return r; end if;
  end if;
  select * into m from merchants where id = p_provider_id;
  if not found or m.status <> 'approved' then raise exception 'provider_unavailable'; end if;
  if not exists (select 1 from service_provider_types t where t.service_id = p_service_id and t.business_type = m.business_type) then
    raise exception 'provider_not_for_service';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' or p_payload = '{}'::jsonb then raise exception 'payload_required'; end if;
  insert into service_requests (service_id, customer_id, provider_id, payload, amount, client_request_id)
  values (p_service_id, uid, p_provider_id, p_payload, 0, p_client_request_id)
  returning * into r;
  insert into service_request_events (request_id, actor_id, from_status, to_status) values (r.id, uid, null, 'requested');
  perform notify_user(m.owner_id, 'طلب خدمة جديد', sv.name_ar, jsonb_build_object('type', 'service_request', 'id', r.id, 'status', 'requested'));
  return r;
end $$;

-- مقدم الخدمة يحدد السعر قبل القبول (فقط والطلب ما زال بانتظار الرد)
create or replace function service_set_amount(p_request_id uuid, p_amount int)
returns service_requests language plpgsql security definer set search_path = public as $$
declare r service_requests;
begin
  if p_amount is null or p_amount < 0 then raise exception 'invalid_amount'; end if;
  select * into r from service_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if not (owns_merchant(r.provider_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if r.status <> 'requested' then raise exception 'invalid_transition:%', r.status; end if;
  update service_requests set amount = p_amount, updated_at = now() where id = r.id returning * into r;
  return r;
end $$;

grant execute on function merchant_set_business_type(uuid, text) to authenticated;
grant execute on function svc_create_request(text, uuid, jsonb, uuid) to authenticated;
grant execute on function service_set_amount(uuid, int) to authenticated;

-- مقدمو خدمة معتمدون لخدمة معيّنة (للزبون)
create or replace function providers_for_service(p_service_id text)
returns setof merchants language sql stable security definer set search_path = public as $$
  select m.* from merchants m
   where m.status = 'approved'
     and m.business_type in (select business_type from service_provider_types where service_id = p_service_id)
   order by m.name;
$$;
grant execute on function providers_for_service(text) to authenticated;

notify pgrst, 'reload schema';

-- الخدمات التي تستخدم الطلب العام: محركها "booking" (الطلب بالتفاصيل ثم تسعير من المقدم)
update services set engine = 'booking'
 where id in ('photographers', 'print_custom', 'phone_repair', 'carpet_cleaning', 'institute_seats',
              'documents', 'ps_rental', 'heavy_transport', 'travel_campaigns', 'doctor_booking', 'restaurant_booking')
   and engine = 'none';
