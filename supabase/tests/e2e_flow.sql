-- =====================================================================
-- اختبار شامل لدورة العمل والصلاحيات (يُشغَّل على قاعدة محلية فيها supabase_stub)
--   psql -v ON_ERROR_STOP=1 -f tests/e2e_flow.sql
-- كل خطوة تنفَّذ بدور "authenticated" وهوية مستخدم محددة، يعني RLS فعّالة.
-- =====================================================================
\set ON_ERROR_STOP 1
\set QUIET 1

create schema if not exists t;
grant usage on schema t to authenticated;

create or replace function t.ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond is distinct from true then raise exception 'FAIL: %', msg; end if;
  raise notice 'PASS: %', msg;
end $$;

-- ينفّذ أمر ويتأكد إنه فشل برسالة تحتوي النمط
create or replace function t.fails(cmd text, pattern text, msg text) returns void language plpgsql as $$
begin
  begin
    execute cmd;
  exception when others then
    if sqlerrm ilike '%' || pattern || '%' then raise notice 'PASS: % (%)', msg, sqlerrm; return; end if;
    raise exception 'FAIL: % — unexpected error: %', msg, sqlerrm;
  end;
  raise exception 'FAIL: % — command succeeded but should fail', msg;
end $$;

create or replace function t.login(uid uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), false);
end $$;
grant execute on all functions in schema t to authenticated;

create table t.ids (k text primary key, v uuid);
grant select, insert, update on t.ids to authenticated;
create or replace function t.id(key text) returns uuid language sql stable as $$ select v from t.ids where k = key $$;

-- ---------------------------------------------------------------------
-- 1) إنشاء الحسابات (يعادل التسجيل من التطبيق)
-- ---------------------------------------------------------------------
insert into auth.users (email, raw_user_meta_data) values
  ('9647700000001@phone.wasel.app', '{"full_name":"مدير المنصة","phone":"07700000001"}'),
  ('9647700000002@phone.wasel.app', '{"full_name":"صاحب المطعم","phone":"07700000002"}'),
  ('9647700000003@phone.wasel.app', '{"full_name":"زبون أول","phone":"07700000003"}'),
  ('9647700000004@phone.wasel.app', '{"full_name":"مندوب توصيل","phone":"07700000004"}'),
  ('9647700000005@phone.wasel.app', '{"full_name":"سائق تكسي","phone":"07700000005"}'),
  ('9647700000006@phone.wasel.app', '{"full_name":"زبون ثاني","phone":"07700000006"}'),
  ('9647700000007@phone.wasel.app', '{"full_name":"فني سباكة","phone":"07700000007"}'),
  ('9647700000008@phone.wasel.app', '{"full_name":"سائق تكتك","phone":"07700000008"}');
insert into t.ids select 'admin', id from auth.users where email like '%0001@%';
insert into t.ids select 'owner', id from auth.users where email like '%0002@%';
insert into t.ids select 'cust', id from auth.users where email like '%0003@%';
insert into t.ids select 'courier', id from auth.users where email like '%0004@%';
insert into t.ids select 'taxi', id from auth.users where email like '%0005@%';
insert into t.ids select 'cust2', id from auth.users where email like '%0006@%';
insert into t.ids select 'plumber', id from auth.users where email like '%0007@%';
insert into t.ids select 'tuktuk', id from auth.users where email like '%0008@%';

select t.ok((select count(*) from users) = 8, 'التسجيل ينشئ ملف المستخدم تلقائياً');
select t.ok((select count(*) from user_roles where role = 'customer') = 8, 'كل حساب جديد ياخذ دور مستهلك');

-- أول مدير يُعيَّن يدوياً من SQL (موثّق بالـ README)
insert into user_roles (user_id, role) values (t.id('admin'), 'admin');

set role authenticated;

-- ---------------------------------------------------------------------
-- 2) صلاحيات الأدوار
-- ---------------------------------------------------------------------
select t.login(t.id('cust'));
select t.fails($$insert into user_roles values (auth.uid(), 'admin')$$, 'row-level security', 'المستهلك ما يگدر يمنح نفسه دور مدير');
select t.fails($$select admin_set_role(auth.uid(), 'admin', true)$$, 'forbidden', 'المستهلك ما يگدر يستدعي دوال الإدارة');
select t.fails($$update users set is_active = false where id = auth.uid()$$, 'forbidden', 'المستخدم ما يگدر يغيّر حالة حسابه');
select t.ok((select count(*) from users) = 1, 'المستهلك يشوف ملفه فقط');

-- ---------------------------------------------------------------------
-- 3) الإدارة: منطقة + محل + ربط تاجر + سائقين
-- ---------------------------------------------------------------------
select t.login(t.id('admin'));
with x as (insert into service_areas (name, city, center_lat, center_lng, radius_km)
  values ('الكرادة', 'بغداد', 33.3030, 44.4350, 6) returning id) insert into t.ids select 'area', id from x;

with x as (insert into merchants (category_id, area_id, name, address_text, lat, lng, phone, delivery_fee, min_order, delivery_radius_km)
  values ('restaurants', t.id('area'), 'مطعم التجربة', 'شارع 62', 33.3050, 44.4320, '07700000002', 1500, 3000, 4)
  returning id) insert into t.ids select 'rest', id from x;
select admin_link_merchant_owner(t.id('rest'), t.id('owner'));

with x as (insert into merchants (category_id, area_id, name, lat, lng, status)
  values ('home_services', t.id('area'), 'سباكة الأمانة', 33.30, 44.43, 'approved') returning id) insert into t.ids select 'provider', id from x;
select admin_link_merchant_owner(t.id('provider'), t.id('plumber'));
insert into merchant_services select t.id('provider'), id from home_services where name = 'سباكة';

select admin_upsert_driver(t.id('courier'), 'courier', t.id('area'), '', 'دراجة', 'أحمر', true);
select admin_upsert_driver(t.id('taxi'), 'taxi', t.id('area'), 'بغداد 12345', 'كيا', 'أبيض', true);
select admin_upsert_driver(t.id('tuktuk'), 'tuktuk', t.id('area'), '', 'تكتك', 'أصفر', true);
select t.ok((select (admin_stats()->>'merchants_pending')::int) = 1, 'إحصائيات الإدارة تحسب المحلات غير المعتمدة');

-- ---------------------------------------------------------------------
-- 4) المحل غير المعتمد ما يظهر للمستهلك
-- ---------------------------------------------------------------------
select t.login(t.id('cust'));
select t.ok(not exists (select 1 from merchants where id = t.id('rest')), 'المحل غير المعتمد مخفي عن المستهلك');

-- التاجر يضيف منتجات لمحله (حتى قبل الاعتماد)
select t.login(t.id('owner'));
select t.ok(exists (select 1 from merchants where id = t.id('rest')), 'التاجر يشوف محله قبل الاعتماد');
with x as (insert into product_categories (merchant_id, name) values (t.id('rest'), 'المشويات') returning id) insert into t.ids select 'pcat', id from x;
with x as (insert into products (merchant_id, category_id, name, price) values (t.id('rest'), t.id('pcat'), 'تكة لحم', 7000) returning id) insert into t.ids select 'p1', id from x;
with x as (insert into products (merchant_id, name, price, stock) values (t.id('rest'), 'شوربة عدس', 1500, 3) returning id) insert into t.ids select 'p2', id from x;
select t.fails($$insert into products (merchant_id, name, price) values (t.id('provider'), 'منتج دخيل', 1000)$$,
               'row-level security', 'التاجر ما يگدر يضيف منتج لمحل غيره');
-- RLS تجعل محاولة التاجر اعتماد محله بلا أثر (0 صفوف):
update merchants set status = 'approved' where id = t.id('rest');
select t.ok((select status from merchants where id = t.id('rest')) = 'pending', 'محاولة التاجر اعتماد محله ما تأثر');

-- الإدارة تعتمد المحل
select t.login(t.id('admin'));
update merchants set status = 'approved' where id = t.id('rest');

select t.login(t.id('cust'));
select t.ok(exists (select 1 from merchants where id = t.id('rest')), 'بعد الاعتماد يظهر المحل للمستهلك');
select t.ok((select count(*) from products where merchant_id = t.id('rest')) = 2, 'منتجات التاجر تظهر للمستهلك');

-- ---------------------------------------------------------------------
-- 5) الطلب: عنوان + إرسال + حماية الأسعار
-- ---------------------------------------------------------------------
with x as (insert into addresses (user_id, label, details, landmark, lat, lng)
  values (auth.uid(), 'البيت', 'زقاق 12 دار 7', 'قرب الجامع', 33.3020, 44.4370) returning id) insert into t.ids select 'addr', id from x;
with x as (insert into addresses (user_id, label, lat, lng) values (auth.uid(), 'بعيد', 33.40, 44.30) returning id) insert into t.ids select 'far', id from x;

select t.fails(format($$select place_order(%L, %L, '[{"product_id":"%s","qty":1}]', '', gen_random_uuid())$$,
               t.id('rest'), t.id('addr'), t.id('p2')), 'below_min_order', 'الحد الأدنى للطلب مطبّق');
select t.fails(format($$select place_order(%L, %L, '[{"product_id":"%s","qty":1}]', '', gen_random_uuid())$$,
               t.id('rest'), t.id('far'), t.id('p1')), 'out_of_delivery_area', 'منع الطلب خارج نطاق التوصيل');

insert into t.ids values ('ref', gen_random_uuid());
insert into t.ids select 'order', (place_order(t.id('rest'), t.id('addr'),
  format('[{"product_id":"%s","qty":2,"price":1},{"product_id":"%s","qty":1}]', t.id('p1'), t.id('p2'))::jsonb,
  'بدون بصل', t.id('ref'))).id;
select t.ok((select total from orders where id = t.id('order')) = 2*7000 + 1500 + 1500,
            'السعر يُحسب بالخادم ويتجاهل أي سعر من التطبيق');
select t.ok((select (place_order(t.id('rest'), t.id('addr'), '[]', '', t.id('ref'))).id) = t.id('order'),
            'إعادة الإرسال بنفس المرجع ترجع نفس الطلب (بدون تكرار)');
select t.ok((select stock from products where id = t.id('p2')) = 2, 'المخزون ينقص عند الطلب');
update orders set total = 1, status = 'delivered' where id = t.id('order');
select t.ok((select total from orders where id = t.id('order')) = 17000, 'المستهلك ما يگدر يعدّل الطلب مباشرة');

select t.login(t.id('cust2'));
select t.ok(not exists (select 1 from orders where id = t.id('order')), 'زبون ثاني ما يشوف طلب غيره');
select t.ok(not exists (select 1 from addresses where user_id = t.id('cust')), 'زبون ثاني ما يشوف عناوين غيره');

-- ---------------------------------------------------------------------
-- 6) التاجر يستلم ويقبل ويجهّز
-- ---------------------------------------------------------------------
select t.login(t.id('owner'));
select t.ok(exists (select 1 from orders where id = t.id('order')), 'الطلب الجديد يظهر عند المحل');
select t.ok(exists (select 1 from notifications where data->>'id' = t.id('order')::text), 'التاجر وصله إشعار بالطلب');
select t.ok((select customer_phone from orders where id = t.id('order')) = '07700000003', 'التاجر يشوف رقم الزبون بالطلب');
select t.fails(format($$select merchant_set_order_status(%L, 'ready')$$, t.id('order')), 'invalid_transition', 'ما يصير تخطي الحالات');
select merchant_set_order_status(t.id('order'), 'accepted');
select merchant_set_order_status(t.id('order'), 'preparing');

select t.login(t.id('courier'));
select t.ok(not exists (select 1 from delivery_tasks where order_id = t.id('order')), 'المهمة ما تظهر للمندوب قبل جاهزية الطلب');

select t.login(t.id('owner'));
select merchant_set_order_status(t.id('order'), 'ready');
select t.ok((select (merchant_stats(t.id('rest'))->>'active')::int) = 1, 'إحصائيات التاجر تعمل');

-- ---------------------------------------------------------------------
-- 7) المندوب يقبل ويوصل
-- ---------------------------------------------------------------------
select t.login(t.id('taxi'));
select t.ok(not exists (select 1 from delivery_tasks where order_id = t.id('order')), 'سائق التكسي ما يشوف مهام توصيل الطلبات');

select t.login(t.id('courier'));
select driver_set_available(true, 33.3060, 44.4300);
insert into t.ids select 'task', id from delivery_tasks where order_id = t.id('order');
select t.ok(t.id('task') is not null, 'المندوب يشوف المهمة المتاحة');
select driver_accept_task(t.id('task'));

select t.login(t.id('tuktuk'));
select t.fails(format($$select driver_accept_task(%L)$$, t.id('task')), 'task_taken', 'المهمة المقبولة ما ينگدر ياخذها غيره');
select t.ok(not exists (select 1 from delivery_tasks where id = t.id('task')), 'بعد القبول تختفي المهمة عن باقي السواق');

select t.login(t.id('courier'));
select driver_update_location(33.3040, 44.4330);
select driver_update_task(t.id('task'), 'picked_up');
select driver_update_task(t.id('task'), 'on_the_way');

select t.login(t.id('cust'));
select t.ok((select driver_name from orders where id = t.id('order')) = 'مندوب توصيل', 'الزبون يشوف اسم المندوب');
select t.ok((select driver_lat from orders where id = t.id('order')) = 33.3040, 'الزبون يشوف موقع المندوب المحدّث');
select t.ok((select status from orders where id = t.id('order')) = 'on_the_way', 'حالة الطلب تتزامن مع المهمة');

select t.login(t.id('courier'));
select driver_update_task(t.id('task'), 'delivered');

select t.login(t.id('cust'));
select t.ok((select status from orders where id = t.id('order')) = 'delivered', 'الطلب اكتمل');
select t.ok((select count(*) from order_status_history where order_id = t.id('order')) = 7, 'سجل الحالات كامل (7 مراحل)');
select t.ok((select count(*) from notifications where data->>'id' = t.id('order')::text) >= 6, 'الزبون وصلته إشعارات كل الحالات');
select rate_order(t.id('order'), 5, 'ممتاز');

select t.login(t.id('admin'));
select t.ok((select rating_avg from merchants where id = t.id('rest')) = 5, 'التقييم ينعكس على المحل');
select t.ok((select order_count from merchants where id = t.id('rest')) = 1, 'عدد طلبات المحل يزيد');

-- ---------------------------------------------------------------------
-- 8) رفض طلب مع سبب + إلغاء من الزبون
-- ---------------------------------------------------------------------
select t.login(t.id('cust'));
insert into t.ids select 'order2', (place_order(t.id('rest'), t.id('addr'),
  format('[{"product_id":"%s","qty":2}]', t.id('p2'))::jsonb, '', gen_random_uuid())).id;
select t.login(t.id('owner'));
select t.fails(format($$select merchant_set_order_status(%L, 'cancelled')$$, t.id('order2')), 'reason_required', 'الرفض يحتاج سبب');
select merchant_set_order_status(t.id('order2'), 'cancelled', 'المادة خلصت');
select t.ok((select stock from products where id = t.id('p2')) = 2, 'المخزون يرجع عند الرفض');

select t.login(t.id('cust'));
insert into t.ids select 'order3', (place_order(t.id('rest'), t.id('addr'),
  format('[{"product_id":"%s","qty":1}]', t.id('p1'))::jsonb, '', gen_random_uuid())).id;
select customer_cancel_order(t.id('order3'));
select t.ok((select status from orders where id = t.id('order3')) = 'cancelled', 'الزبون يلغي قبل الموافقة');

-- المحل موقف الاستقبال
select t.login(t.id('owner'));
select merchant_update_profile(t.id('rest'), null, null, null, false, null, null, null);
select t.login(t.id('cust'));
select t.fails(format($$select place_order(%L, %L, '[{"product_id":"%s","qty":1}]', '', gen_random_uuid())$$,
               t.id('rest'), t.id('addr'), t.id('p1')), 'merchant_closed', 'المحل الموقف ما يستقبل طلبات');

-- ---------------------------------------------------------------------
-- 9) التكسي والتكتك
-- ---------------------------------------------------------------------
select t.login(t.id('cust'));
select t.ok(((estimate_fare('taxi', 33.30, 44.43, 33.32, 44.40))->>'fare')::int > 0, 'تقدير الأجرة يعمل');
insert into t.ids select 'ride', (request_ride('taxi', 'البيت', 33.30, 44.43, 'السعدون', 33.32, 44.40)).id;
select t.fails($$select request_ride('taxi', 'a', 33.30, 44.43, 'b', 33.31, 44.41)$$, 'ride_already_active', 'رحلة وحدة نشطة لكل زبون');

select t.login(t.id('tuktuk'));
select driver_set_available(true, 33.30, 44.43);
select t.ok(not exists (select 1 from rides where id = t.id('ride')), 'التكتك ما يشوف طلبات التكسي');

select t.login(t.id('taxi'));
select driver_set_available(true, 33.301, 44.431);
select t.ok(exists (select 1 from rides where id = t.id('ride')), 'سائق التكسي يشوف طلب الرحلة');
select driver_accept_ride(t.id('ride'));
select driver_update_ride(t.id('ride'), 'arrived');
select driver_update_ride(t.id('ride'), 'in_progress');
select driver_update_location(33.31, 44.42);
select driver_update_ride(t.id('ride'), 'completed');

select t.login(t.id('cust'));
select t.ok((select status from rides where id = t.id('ride')) = 'completed', 'الرحلة اكتملت');
select t.ok((select driver_vehicle from rides where id = t.id('ride')) like '%كيا%', 'الزبون يشوف بيانات المركبة');
select t.ok((select fare from rides where id = t.id('ride')) % 250 = 0, 'الأجرة مقرّبة لأقرب 250');

insert into t.ids select 'ride2', (request_ride('tuktuk', 'البيت', 33.30, 44.43, 'السوق', 33.305, 44.425)).id;
select t.login(t.id('tuktuk'));
select driver_accept_ride(t.id('ride2'));
select t.login(t.id('cust'));
select customer_cancel_ride(t.id('ride2'));
select t.ok((select status from rides where id = t.id('ride2')) = 'cancelled', 'الزبون يلغي رحلة التكتك');

-- الإدارة تغيّر التسعير إلى أجرة ثابتة
select t.login(t.id('admin'));
update app_settings set value = jsonb_set(value, '{taxi,mode}', '"fixed"') where key = 'ride_pricing';
select t.login(t.id('cust'));
select t.ok(((estimate_fare('taxi', 33.30, 44.43, 33.40, 44.30))->>'fare')::int = 5000, 'الأجرة الثابتة من الإدارة تُطبَّق');

-- ---------------------------------------------------------------------
-- 10) توصيل الأغراض
-- ---------------------------------------------------------------------
insert into t.ids select 'parcel', (create_errand('parcel', 'البيت', 33.30, 44.43, 'بيت أهلي', 33.31, 44.42,
  'أوراق', 'ظرف أوراق رسمية', '07711111111', 'سلّمه باليد')).id;
select t.login(t.id('tuktuk'));
select t.ok(exists (select 1 from delivery_tasks where id = t.id('parcel')), 'التكتك يشوف مهام توصيل الأغراض');
select driver_accept_task(t.id('parcel'));
select driver_update_task(t.id('parcel'), 'picked_up');
select driver_update_task(t.id('parcel'), 'on_the_way');
select driver_update_task(t.id('parcel'), 'delivered');
select t.login(t.id('cust'));
select t.ok((select status from delivery_tasks where id = t.id('parcel')) = 'delivered', 'توصيل الغرض اكتمل');

-- ---------------------------------------------------------------------
-- 11) الخدمات المنزلية
-- ---------------------------------------------------------------------
insert into t.ids select 'booking', (book_service((select id from home_services where name = 'سباكة'), t.id('provider'),
  'البيت', 33.30, 44.43, 'تسريب مي بالمطبخ', array['bookings/' || auth.uid() || '/1.jpg'], now() + interval '1 day')).id;
select t.fails(format($$select book_service((select id from home_services where name = 'كهرباء'), %L, '', 33.3, 44.4, 'x', '{}', now() + interval '1 day')$$,
               t.id('provider')), 'provider_does_not_offer_service', 'ما يصير تحجز خدمة ما يقدمها المزوّد');
select t.login(t.id('owner'));
select t.ok(not exists (select 1 from service_bookings where id = t.id('booking')), 'تاجر ثاني ما يشوف طلبات الخدمة');
select t.login(t.id('plumber'));
select provider_update_booking(t.id('booking'), 'accepted', 'باچر الساعة 10');
select provider_update_booking(t.id('booking'), 'in_progress');
select provider_update_booking(t.id('booking'), 'completed');
select t.login(t.id('cust'));
select t.ok((select status from service_bookings where id = t.id('booking')) = 'completed', 'طلب الخدمة المنزلية اكتمل');

-- ---------------------------------------------------------------------
-- 12) رفع الصور
-- ---------------------------------------------------------------------
select t.login(t.id('owner'));
insert into storage.objects (bucket_id, name) values ('media', 'merchants/' || t.id('rest') || '/p1.jpg');
select t.fails(format($$insert into storage.objects (bucket_id, name) values ('media', 'merchants/%s/x.jpg')$$, t.id('provider')),
               'row-level security', 'التاجر ما يرفع صور لمحل غيره');
select t.login(t.id('cust'));
insert into storage.objects (bucket_id, name) values ('media', 'bookings/' || auth.uid() || '/a.jpg');
select t.fails(format($$insert into storage.objects (bucket_id, name) values ('media', 'bookings/%s/a.jpg')$$, t.id('cust2')),
               'row-level security', 'المستخدم ما يرفع صور باسم غيره');

-- ---------------------------------------------------------------------
-- 13) تعطيل حساب
-- ---------------------------------------------------------------------
select t.login(t.id('admin'));
update users set is_active = false where id = t.id('cust2');
select t.login(t.id('cust2'));
select t.fails($$select request_ride('taxi', 'a', 33.30, 44.43, 'b', 33.32, 44.40)$$, 'account_disabled', 'الحساب المعطّل ما يگدر يطلب');

-- ---------------------------------------------------------------------
-- 14) تقارير الإدارة (بيانات حقيقية للرسوم)
-- ---------------------------------------------------------------------
select t.login(t.id('admin'));
select t.ok(jsonb_array_length(admin_reports(14)->'daily') = 14, 'تقرير يومي لـ 14 يوم بدون فجوات');
select t.ok((select sum((d->>'delivered')::int) from jsonb_array_elements(admin_reports(14)->'daily') d) = 1, 'عدد الطلبات المسلّمة بالتقرير مطابق');
select t.ok((select sum((d->>'sales')::int) from jsonb_array_elements(admin_reports(14)->'daily') d) = 17000 - 1500, 'مبيعات التقرير = المسلّم بدون التوصيل');
select t.ok((admin_reports(14)->'by_status'->>'cancelled')::int = 2, 'توزيع الحالات صحيح');
select t.ok(admin_reports(14)->'top_merchants'->0->>'name' = 'مطعم التجربة', 'أفضل المحلات من البيانات الفعلية');
select t.login(t.id('cust'));
select t.fails($$select admin_reports(14)$$, 'forbidden', 'المستهلك ما يشوف تقارير الإدارة');

-- ---------------------------------------------------------------------
-- 15) الدعم داخل التطبيق
-- ---------------------------------------------------------------------
select t.login(t.id('cust'));
select support_send('customer', 'وين طلبي؟', 'W1001');
select support_send('customer', 'رسالة ثانية');
select t.ok((select count(*) from support_threads where user_id = auth.uid()) = 1, 'محادثة دعم وحدة لكل مستخدم بكل تطبيق');
select t.ok((select unread_for_admin from support_threads where user_id = auth.uid()) = 2, 'عداد غير المقروء للإدارة صحيح');
select t.ok((select order_code from support_messages order by id limit 1) = 'W1001', 'رقم الطلب ينحفظ مع الرسالة');
select t.fails($$select support_send('customer', '   ')$$, 'empty_message', 'رسالة فارغة مرفوضة');
select t.fails($$select support_reply((select id from support_threads limit 1), 'x')$$, 'forbidden', 'المستهلك ما يگدر يرد كإدارة');
select t.fails($$insert into support_messages (thread_id, body) select id, 'x' from support_threads limit 1$$, 'permission denied', 'ما ينكتب على الرسائل مباشرة');
select t.login(t.id('owner'));
select t.ok((select count(*) from support_messages) = 0, 'المستخدم ما يشوف محادثات غيره');
select t.login(t.id('admin'));
select t.ok((select count(*) from support_messages) = 2, 'الإدارة تشوف رسائل الدعم');
select support_reply((select id from support_threads where user_id = t.id('cust')), 'طلبك بالطريق');
select support_mark_read((select id from support_threads where user_id = t.id('cust')));
select t.ok((select unread_for_admin from support_threads where user_id = t.id('cust')) = 0, 'الإدارة علّمت المحادثة مقروءة');
select t.login(t.id('cust'));
select t.ok((select unread_for_user from support_threads where user_id = auth.uid()) = 1, 'المستخدم عنده رد غير مقروء');
select t.ok(exists (select 1 from notifications where user_id = auth.uid() and data->>'type' = 'support'), 'رد الدعم يوصل كإشعار');
select t.ok((select from_admin from support_messages order by id desc limit 1), 'رد الإدارة ظاهر للمستخدم');
select t.login(t.id('cust2'));
select t.fails($$select support_send('customer', 'مرحبا')$$, 'account_disabled', 'الحساب الموقوف ما يراسل (يتواصل بالواتساب)');

reset role;
select 'ALL TESTS PASSED' as result;
