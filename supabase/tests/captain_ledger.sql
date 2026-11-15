-- =====================================================================
-- اختبار دفتر حساب الكابتن (0009): العمولة، عدم التكرار، التسديد، الصلاحيات
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/captain_ledger.sql
-- مستقل عن e2e_flow.sql (حسابات وبيانات خاصة به) ويمكن تشغيله أكثر من مرة لأنه ينظّف نفسه.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

-- تنظيف من تشغيل سابق
reset role;
delete from driver_ledger_entries where driver_id in (select id from users where phone like '0770999%');
delete from driver_commissions where driver_id in (select id from users where phone like '0770999%');
delete from rides where customer_id in (select id from users where phone like '0770999%');
delete from delivery_tasks where customer_id in (select id from users where phone like '0770999%');
delete from drivers where id in (select id from users where phone like '0770999%');
delete from auth.users where email like '977099%@phone.wasel.app';
delete from service_areas where name = 'منطقة اختبار الكابتن';

create schema if not exists cl;
create or replace function cl.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'PASS: %', msg;
end $$;
create or replace function cl.fails(cmd text, pattern text, msg text) returns void language plpgsql as $$
begin
  begin execute cmd;
  exception when others then
    if sqlerrm ilike '%' || pattern || '%' then raise notice 'PASS: % (%)', msg, sqlerrm; return; end if;
    raise exception 'FAIL: % — unexpected error: %', msg, sqlerrm;
  end;
  raise exception 'FAIL: % — command succeeded but should fail', msg;
end $$;
create or replace function cl.login(uid uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), false); end $$;
grant usage on schema cl to authenticated;
grant execute on all functions in schema cl to authenticated;
drop table if exists cl.ids;
create table cl.ids (k text primary key, v uuid);
grant select on cl.ids to authenticated;
create or replace function cl.id(key text) returns uuid language sql stable as $$ select v from cl.ids where k = key $$;

-- ---------------------------------------------------------------------
-- إعداد (كمالك القاعدة): مدير + كابتنان + زبون + إعداد العمولة مفعّل 10%
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('0c000001-0000-4000-8000-000000000001', '9770990000001@phone.wasel.app', '{"full_name":"مدير اختبار","phone":"07709990001"}'),
  ('0c000002-0000-4000-8000-000000000002', '9770990000002@phone.wasel.app', '{"full_name":"كابتن أ","phone":"07709990002"}'),
  ('0c000003-0000-4000-8000-000000000003', '9770990000003@phone.wasel.app', '{"full_name":"كابتن ب","phone":"07709990003"}'),
  ('0c000004-0000-4000-8000-000000000004', '9770990000004@phone.wasel.app', '{"full_name":"زبون اختبار","phone":"07709990004"}'),
  ('0c000005-0000-4000-8000-000000000005', '9770990000005@phone.wasel.app', '{"full_name":"مندوب اختبار","phone":"07709990005"}');
insert into cl.ids select 'adm', id from auth.users where email like '%0001@phone.wasel.app' and email like '977099%';
insert into cl.ids select 'k1', id from auth.users where email like '%0002@phone.wasel.app' and email like '977099%';
insert into cl.ids select 'k2', id from auth.users where email like '%0003@phone.wasel.app' and email like '977099%';
insert into cl.ids select 'cust', id from auth.users where email like '%0004@phone.wasel.app' and email like '977099%';
insert into cl.ids select 'courier', id from auth.users where email like '%0005@phone.wasel.app' and email like '977099%';

insert into service_areas (id, name, city, center_lat, center_lng, radius_km, is_active)
values ('e0000000-0000-4000-8000-0000000000aa', 'منطقة اختبار الكابتن', 'بغداد', 33.3100, 44.4300, 20, true);

insert into user_roles (user_id, role) values (cl.id('adm'), 'admin'), (cl.id('k1'), 'driver'), (cl.id('k2'), 'driver'), (cl.id('courier'), 'driver');
insert into drivers (id, vehicle_type, area_id, is_active, is_available) values
  (cl.id('k1'), 'taxi', 'e0000000-0000-4000-8000-0000000000aa', true, true), (cl.id('k2'), 'taxi', 'e0000000-0000-4000-8000-0000000000aa', true, true), (cl.id('courier'), 'courier', 'e0000000-0000-4000-8000-0000000000aa', true, true);
update app_settings set value = '{"enabled": true, "percent": 10}' where key = 'driver_commission';

-- رحلة 1: تكسي أجرتها 12,500 (تكمل)
insert into rides (id, customer_id, vehicle, area_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, distance_km, fare, status)
values ('a0000000-0000-4000-8000-000000000001', cl.id('cust'), 'taxi', 'e0000000-0000-4000-8000-0000000000aa', 33.31, 44.43, 33.32, 44.44, 3.2, 12500, 'requested');
-- رحلة 2: تُلغى بعد القبول
insert into rides (id, customer_id, vehicle, area_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, distance_km, fare, status)
values ('a0000000-0000-4000-8000-000000000002', cl.id('cust'), 'taxi', 'e0000000-0000-4000-8000-0000000000aa', 33.31, 44.43, 33.33, 44.45, 4.1, 9000, 'requested');
-- رحلة 3: تكمل بعد تعطيل العمولة (تُسجَّل بصفر)
insert into rides (id, customer_id, vehicle, area_id, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, distance_km, fare, status)
values ('a0000000-0000-4000-8000-000000000003', cl.id('cust'), 'taxi', 'e0000000-0000-4000-8000-0000000000aa', 33.31, 44.43, 33.34, 44.46, 2.0, 6000, 'requested');
-- توصيل مندوب 4,000 (يُكمل)
insert into delivery_tasks (id, kind, customer_id, driver_id, status, pickup_lat, pickup_lng, dropoff_lat, dropoff_lng, fee, customer_name, customer_phone)
values ('b0000000-0000-4000-8000-000000000001', 'courier', cl.id('cust'), cl.id('courier'), 'on_the_way', 33.31, 44.43, 33.32, 44.44, 4000, 'زبون', '07709990004');

-- ---------------------------------------------------------------------
-- 1) الكابتن يقبل ويكمل رحلة عبر الدوال الفعلية
-- ---------------------------------------------------------------------
set role authenticated;
select cl.login(cl.id('k1'));
select driver_accept_ride('a0000000-0000-4000-8000-000000000001');
select driver_update_ride('a0000000-0000-4000-8000-000000000001', 'arrived');
select driver_update_ride('a0000000-0000-4000-8000-000000000001', 'in_progress');
select driver_update_ride('a0000000-0000-4000-8000-000000000001', 'completed');

reset role;
select cl.ok((select count(*) from driver_commissions where ride_id = 'a0000000-0000-4000-8000-000000000001') = 1, 'إكمال الرحلة يسجّل عمولة واحدة');
select cl.ok((select amount from driver_commissions where ride_id = 'a0000000-0000-4000-8000-000000000001') = 1250, 'العمولة = 10% من 12,500 = 1,250');
select cl.ok((select percent from driver_commissions where ride_id = 'a0000000-0000-4000-8000-000000000001') = 10, 'النسبة تُثبَّت على الصف');

-- إعادة الإكمال: الدالة ترفض، وحتى التحديث المباشر ما يكرّر الصف
set role authenticated;
select cl.login(cl.id('k1'));
select cl.fails($$select driver_update_ride('a0000000-0000-4000-8000-000000000001', 'completed')$$, 'invalid_transition', 'الرحلة المكتملة ما تنكمل مرة ثانية');
reset role;
update rides set status = 'completed' where id = 'a0000000-0000-4000-8000-000000000001';
select cl.ok((select count(*) from driver_commissions where ride_id = 'a0000000-0000-4000-8000-000000000001') = 1, 'التحديث المكرر لا يكرّر العمولة');

-- ---------------------------------------------------------------------
-- 2) الإلغاء بعد القبول ما يولّد عمولة
-- ---------------------------------------------------------------------
set role authenticated;
select cl.login(cl.id('k1'));
select driver_accept_ride('a0000000-0000-4000-8000-000000000002');
select driver_update_ride('a0000000-0000-4000-8000-000000000002', 'cancelled');
reset role;
select cl.ok(not exists (select 1 from driver_commissions where ride_id = 'a0000000-0000-4000-8000-000000000002'), 'الرحلة الملغاة ما تنحسب عليها عمولة');

-- ---------------------------------------------------------------------
-- 3) تعطيل العمولة: الرحلة الجديدة تُسجَّل بصفر (أثر محاسبي)، ثم نرجّع الإعداد
-- ---------------------------------------------------------------------
update app_settings set value = '{"enabled": false, "percent": 10}' where key = 'driver_commission';
set role authenticated;
select cl.login(cl.id('k1'));
select driver_accept_ride('a0000000-0000-4000-8000-000000000003');
select driver_update_ride('a0000000-0000-4000-8000-000000000003', 'arrived');
select driver_update_ride('a0000000-0000-4000-8000-000000000003', 'in_progress');
select driver_update_ride('a0000000-0000-4000-8000-000000000003', 'completed');
reset role;
select cl.ok((select amount from driver_commissions where ride_id = 'a0000000-0000-4000-8000-000000000003') = 0, 'بعد التعطيل: العمولة صفر');
update app_settings set value = '{"enabled": true, "percent": 10}' where key = 'driver_commission';

-- ---------------------------------------------------------------------
-- 4) توصيل مندوب: عمولة مرة واحدة، والتكرار لا يضيف شي
-- ---------------------------------------------------------------------
update delivery_tasks set status = 'delivered' where id = 'b0000000-0000-4000-8000-000000000001';
update delivery_tasks set status = 'delivered' where id = 'b0000000-0000-4000-8000-000000000001';
select cl.ok((select count(*) from driver_commissions where task_id = 'b0000000-0000-4000-8000-000000000001') = 1, 'توصيل المندوب يسجّل عمولة مرة واحدة');
select cl.ok((select amount from driver_commissions where task_id = 'b0000000-0000-4000-8000-000000000001') = 400, 'عمولة التوصيل = 10% من 4,000');

-- ---------------------------------------------------------------------
-- 5) المستحق: 1,250 + 400 = 1,650 (الرحلة 3 بصفر، والملغاة لا تدخل)
-- ---------------------------------------------------------------------
select cl.ok((select sum(amount) from driver_commissions where driver_id = cl.id('k1')) = 1250, 'عمولات كابتن أ = 1,250');
select cl.ok((select sum(amount) from driver_commissions where driver_id = cl.id('courier')) = 400, 'عمولات المندوب = 400');

-- ---------------------------------------------------------------------
-- 6) العزل والصلاحيات
-- ---------------------------------------------------------------------
set role authenticated;
select cl.login(cl.id('k2'));
select cl.ok((select count(*) from driver_commissions) = 0, 'كابتن ب ما يشوف عمولات كابتن أ');
select cl.fails($$insert into driver_commissions (driver_id, ride_id, fare, percent, amount) values (auth.uid(), 'a0000000-0000-4000-8000-000000000002', 1, 1, 1)$$, 'permission denied', 'الكابتن ما يگدر يكتب بدفتر العمولات مباشرة');
select cl.fails($$update driver_commissions set amount = 0$$, 'permission denied', 'ما يگدر يعدّل عمولة');
select cl.fails($$select admin_add_driver_payment(auth.uid(), 1, 'محاولة')$$, 'forbidden', 'الكابتن ما يگدر يسجّل تسديد');

select cl.login(cl.id('k1'));
select cl.ok((select (driver_account() -> 'summary' ->> 'owed')::int) = 1250, 'الكابتن يشوف المستحق عليه بوضوح = 1,250');

-- ---------------------------------------------------------------------
-- 7) الإدارة: حد التسديد، التكرار، التصحيح بسبب
-- ---------------------------------------------------------------------
select cl.login(cl.id('adm'));
select cl.fails(format($$select admin_add_driver_payment(%L, 1500, 'زيادة')$$, cl.id('k1')), 'amount_exceeds_owed', 'ما يگدر يسجّل تسديد أكبر من المستحق');
select cl.fails(format($$select admin_add_driver_payment(%L, 0, 'صفر')$$, cl.id('k1')), 'invalid_amount', 'التسديد لازم يكون أكبر من صفر');

select admin_add_driver_payment(cl.id('k1'), 400, 'استلام نقدي', '11111111-1111-4111-8111-111111111111');
select admin_add_driver_payment(cl.id('k1'), 400, 'استلام نقدي', '11111111-1111-4111-8111-111111111111');
reset role;
select cl.ok((select count(*) from driver_ledger_entries where request_id = '11111111-1111-4111-8111-111111111111') = 1, 'إعادة إرسال نفس التسديد ما تكرّره');
set role authenticated;
select cl.login(cl.id('adm'));
select cl.ok((select (admin_driver_account(cl.id('k1')) -> 'summary' ->> 'owed')::int) = 850, 'بعد تسديد 400 يتبقى 850');

select cl.fails(format($$select admin_add_driver_adjustment(%L, 100, 'قصير')$$, cl.id('k1')), 'reason_required', 'التصحيح يحتاج سبب واضح');
select admin_add_driver_adjustment(cl.id('k1'), 200, 'رحلة مكررة سُجلت بالخطأ، تعويض لصالح الكابتن');
select cl.ok((select (admin_driver_account(cl.id('k1')) -> 'summary' ->> 'owed')::int) = 1050, 'التصحيح يظهر كصف مستقل ويعدّل المستحق = 1,050');
select admin_add_driver_payment(cl.id('k1'), 1050, 'تسديد كامل');
select cl.ok((select (admin_driver_account(cl.id('k1')) -> 'summary' ->> 'owed')::int) = 0, 'بعد التسديد الكامل المستحق صفر');

select cl.ok((select count(*) from driver_ledger_entries where driver_id = cl.id('k1')) = 3, 'كل حركة صف مستقل (تسديد، تصحيح، تسديد)');
select cl.ok((select count(*) from driver_ledger_entries where driver_id = cl.id('k1') and kind = 'payment' and delta < 0) = 2, 'التسديدات مخزنة سالبة');

-- نسبة العمولة من لوحة الإدارة
select cl.fails($$select admin_set_driver_commission(true, 80)$$, 'invalid_percent', 'النسبة ما تتجاوز 50%');
select cl.ok((select (admin_set_driver_commission(true, 12) ->> 'percent')::numeric) = 12, 'الإدارة تغيّر النسبة');
update app_settings set value = '{"enabled": true, "percent": 10}' where key = 'driver_commission';

-- الإدارة ترى قائمة الكباتن والمستحق
select cl.ok((select count(*) from jsonb_array_elements(admin_driver_accounts())) >= 3, 'قائمة الكباتن للإدارة تظهر الكل');

reset role;
delete from driver_ledger_entries where driver_id in (cl.id('k1'), cl.id('k2'), cl.id('courier'));
delete from driver_commissions where driver_id in (cl.id('k1'), cl.id('k2'), cl.id('courier'));
delete from rides where customer_id = cl.id('cust');
delete from delivery_tasks where customer_id = cl.id('cust');
delete from drivers where id in (cl.id('k1'), cl.id('k2'), cl.id('courier'));
delete from service_areas where name = 'منطقة اختبار الكابتن';
delete from user_roles where user_id in (cl.id('adm'), cl.id('k1'), cl.id('k2'), cl.id('courier'));
delete from auth.users where email like '977099%@phone.wasel.app';
\echo ✔ كل اختبارات دفتر الكابتن نجحت
