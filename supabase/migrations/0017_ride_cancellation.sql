-- =====================================================================
-- WASEL | إلغاء الرحلات + منع إساءة الاستخدام (0017)
--
-- 1) cancel_reasons: أسباب الإلغاء (للزبون وللسائق) معرّفة في الجدول، والإدارة تقدر تعدّلها.
-- 2) ride_cancellations: سجل إلغاء واحد لكل رحلة (unique) = لا عدّ مكرر.
--    يحفظ الطرف (زبون/سائق/إدارة/نظام)، والمسؤول عن العدّ، والسبب، والملاحظة، والوقت من الخادم.
-- 3) user_restrictions: الإيقاف المؤقت. الزبون 24 ساعة، والسائق 25 دقيقة. ينتهي حسب وقت الخادم.
--    قيد unique يمنع تكرار الإيقاف لنفس العتبة في نفس اليوم.
-- 4) العدّ يومي بتوقيت بغداد (Asia/Baghdad)، عبر baghdad_day_start().
-- 5) cancel_ride: الدالة الوحيدة لإلغاء الرحلة من الزبون أو السائق. تقفل المستخدم ثم الرحلة.
-- 6) الإدارة: admin_cancel_ride (لا يُعد على أحد)، admin_lift_restriction، وسجل تدقيق admin_audit_log.
-- 7) expire_stale_ride_requests: ينهي طلبات بلا سائق تجاوزت المهلة. لا يُعد على السائق.
--    غير مجدولة بعد (تحتاج قرار منك لتشغيلها تلقائياً).
-- التأثير: إضافة جداول ودوال. الإلغاء القديم (بدون سبب) يُرفض حتى تُحدَّث التطبيقات.
-- =====================================================================

-- ---------------------------------------------------------------------
-- أدوات الوقت
-- ---------------------------------------------------------------------
create or replace function baghdad_day_start(ts timestamptz default now())
returns timestamptz language sql immutable as $$
  select date_trunc('day', ts at time zone 'Asia/Baghdad') at time zone 'Asia/Baghdad';
$$;

-- ---------------------------------------------------------------------
-- أسباب الإلغاء
-- ---------------------------------------------------------------------
create table if not exists cancel_reasons (
  id          text not null,
  party       text not null check (party in ('customer', 'driver')),
  label       text not null,
  needs_note  boolean not null default false,
  sort        int not null default 0,
  is_active   boolean not null default true,
  primary key (party, id)
);
alter table cancel_reasons enable row level security;
drop policy if exists cancel_reasons_read on cancel_reasons;
create policy cancel_reasons_read on cancel_reasons for select to authenticated using (is_active or is_admin());
drop policy if exists cancel_reasons_admin on cancel_reasons;
create policy cancel_reasons_admin on cancel_reasons for all to authenticated using (is_admin()) with check (is_admin());
grant select, insert, update, delete on cancel_reasons to authenticated;
grant all on cancel_reasons to service_role;

insert into cancel_reasons (id, party, label, needs_note, sort) values
  ('changed_mind',    'customer', 'غيرت رأيي.',                    false, 10),
  ('driver_late',     'customer', 'السائق تأخر.',                  false, 20),
  ('other_transport', 'customer', 'وجدت وسيلة نقل أخرى.',           false, 30),
  ('wrong_location',  'customer', 'أدخلت موقعاً خاطئاً.',          false, 40),
  ('fare_unfair',     'customer', 'الأجرة غير مناسبة.',             false, 50),
  ('emergency',       'customer', 'لدي ظرف طارئ.',                 false, 60),
  ('other',           'customer', 'سبب آخر.',                      true,  70),
  ('no_answer',       'driver',   'الزبون لا يرد على الاتصال.',     false, 10),
  ('unclear_location','driver',   'موقع الزبون غير واضح.',          false, 20),
  ('cannot_reach',    'driver',   'تعذر الوصول إلى موقع الزبون.',    false, 30),
  ('vehicle_issue',   'driver',   'مشكلة في المركبة.',             false, 40),
  ('emergency',       'driver',   'ظرف طارئ.',                     false, 50),
  ('customer_asked',  'driver',   'الزبون طلب إلغاء الرحلة.',       false, 60),
  ('other',           'driver',   'سبب آخر.',                      true,  70)
on conflict (party, id) do nothing;

-- ---------------------------------------------------------------------
-- سجل الإلغاء: صف واحد لكل رحلة
-- ---------------------------------------------------------------------
create table if not exists ride_cancellations (
  id                 uuid primary key default gen_random_uuid(),
  ride_id            uuid not null unique references rides (id),
  party              text not null check (party in ('customer', 'driver', 'admin', 'system')),
  actor_id           uuid references users (id),
  responsible_id     uuid references users (id),   -- الطرف الذي يُعدّ عليه الإلغاء (زبون أو سائق)، فارغ للإدارة والنظام
  reason_code        text not null,
  reason_label       text not null,
  note               text not null default '',
  ride_status_before ride_status not null,
  cancelled_at       timestamptz not null default now(),
  constraint ride_cancellations_responsible_check check (
    (party in ('customer', 'driver') and responsible_id is not null) or
    (party in ('admin', 'system') and responsible_id is null))
);
create index if not exists ride_cancellations_resp_idx on ride_cancellations (responsible_id, party, cancelled_at);
create index if not exists ride_cancellations_time_idx on ride_cancellations (cancelled_at desc);
alter table ride_cancellations enable row level security;
drop policy if exists ride_cancellations_admin_read on ride_cancellations;
create policy ride_cancellations_admin_read on ride_cancellations for select to authenticated using (is_admin());
grant select on ride_cancellations to authenticated;
grant all on ride_cancellations to service_role;

-- ---------------------------------------------------------------------
-- الإيقاف المؤقت
-- ---------------------------------------------------------------------
create table if not exists user_restrictions (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references users (id),
  kind          text not null check (kind in ('customer_rides', 'driver_dispatch')),
  trigger_count int  not null,
  day_start     timestamptz not null,               -- بداية يوم بغداد الذي حدث فيه الإيقاف
  starts_at     timestamptz not null default now(),
  ends_at       timestamptz not null,
  reason        text not null,
  lifted_at     timestamptz,
  lifted_by     uuid references users (id),
  lift_reason   text not null default '',
  constraint user_restrictions_once unique (user_id, kind, day_start, trigger_count)
);
create index if not exists user_restrictions_active_idx on user_restrictions (user_id, kind) where lifted_at is null;
alter table user_restrictions enable row level security;
drop policy if exists user_restrictions_admin_read on user_restrictions;
create policy user_restrictions_admin_read on user_restrictions for select to authenticated using (is_admin());
grant select on user_restrictions to authenticated;
grant all on user_restrictions to service_role;

-- ---------------------------------------------------------------------
-- سجل تدقيق إجراءات الإدارة
-- ---------------------------------------------------------------------
create table if not exists admin_audit_log (
  id          bigserial primary key,
  actor_id    uuid references users (id),
  action      text not null,
  target_type text not null default '',
  target_id   text not null default '',
  details     jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now()
);
alter table admin_audit_log enable row level security;
drop policy if exists admin_audit_read on admin_audit_log;
create policy admin_audit_read on admin_audit_log for select to authenticated using (is_admin());
grant select on admin_audit_log to authenticated;
grant all on admin_audit_log to service_role;

-- ---------------------------------------------------------------------
-- مساعدات الإيقاف والعدّ
-- ---------------------------------------------------------------------
create or replace function active_restriction(p_user uuid, p_kind text)
returns user_restrictions language sql stable security definer set search_path = public as $$
  select * from user_restrictions
   where user_id = p_user and kind = p_kind and lifted_at is null and ends_at > now()
   order by ends_at desc limit 1;
$$;

create or replace function cancellations_today(p_user uuid, p_party text)
returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from ride_cancellations
   where responsible_id = p_user and party = p_party and cancelled_at >= baghdad_day_start();
$$;

-- الإيقافات النشطة للمستخدم الحالي (للعرض والعدّ التنازلي)
create or replace function my_restrictions()
returns setof user_restrictions language sql stable security definer set search_path = public as $$
  select * from user_restrictions
   where user_id = auth.uid() and lifted_at is null and ends_at > now()
   order by ends_at;
$$;

-- ---------------------------------------------------------------------
-- طلب الرحلة: يُرفض أثناء إيقاف الزبون
-- ---------------------------------------------------------------------
create or replace function request_ride(
  p_vehicle vehicle_type,
  p_pickup_text text, p_pickup_lat double precision, p_pickup_lng double precision,
  p_dropoff_text text, p_dropoff_lat double precision, p_dropoff_lng double precision
) returns rides language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); u users; r rides; km double precision; aid uuid;
begin
  if p_vehicle not in ('taxi', 'tuktuk') then raise exception 'invalid_vehicle'; end if;
  if (active_restriction(uid, 'customer_rides')).id is not null then raise exception 'customer_restricted'; end if;
  if exists (select 1 from rides where customer_id = uid and status in ('requested', 'accepted', 'arrived', 'in_progress')) then
    raise exception 'ride_already_active';
  end if;
  aid := area_for_point(p_pickup_lat, p_pickup_lng);
  if aid is null then raise exception 'outside_service_area'; end if;
  km := distance_km(p_pickup_lat, p_pickup_lng, p_dropoff_lat, p_dropoff_lng);
  if km < 0.1 then raise exception 'same_location'; end if;
  select * into u from users where id = uid;
  insert into rides (customer_id, vehicle, area_id, pickup_text, pickup_lat, pickup_lng, dropoff_text, dropoff_lat, dropoff_lng,
                     distance_km, fare, customer_name, customer_phone)
  values (uid, p_vehicle, aid, coalesce(p_pickup_text, ''), p_pickup_lat, p_pickup_lng,
          coalesce(p_dropoff_text, ''), p_dropoff_lat, p_dropoff_lng, round(km::numeric, 2),
          compute_fare(setting('ride_pricing') -> p_vehicle::text, km), u.full_name, coalesce(u.phone, ''))
  returning * into r;
  return r;
end $$;

-- ---------------------------------------------------------------------
-- قبول السائق: يُرفض أثناء إيقاف استقبال الطلبات
-- ---------------------------------------------------------------------
create or replace function driver_accept_ride(p_ride_id uuid)
returns rides language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); u users; r rides;
begin
  if (active_restriction(d.id, 'driver_dispatch')).id is not null then raise exception 'driver_restricted'; end if;
  if driver_has_active_job(d.id) then raise exception 'already_on_job'; end if;
  if not exists (select 1 from rides where id = p_ride_id and area_id is not null and area_id = my_driver_area()) then
    raise exception 'outside_service_area';
  end if;
  select * into u from users where id = d.id;
  update rides set driver_id = d.id, status = 'accepted', accepted_at = now(), updated_at = now(),
                   driver_name = u.full_name, driver_phone = u.phone, driver_vehicle = vehicle_label(d.id),
                   driver_lat = d.last_lat, driver_lng = d.last_lng
   where id = p_ride_id and status = 'requested' and driver_id is null and vehicle = d.vehicle_type
  returning * into r;
  if not found then raise exception 'ride_taken'; end if;
  perform notify_user(r.customer_id, 'السائق قبل رحلتك', coalesce(u.full_name, '') || ' جاي إليك',
                      jsonb_build_object('type', 'ride', 'id', r.id));
  return r;
end $$;

-- ---------------------------------------------------------------------
-- الإلغاء القديم بلا سبب: مرفوض، والتطبيق يجب أن يستخدم cancel_ride
-- ---------------------------------------------------------------------
create or replace function customer_cancel_ride(p_ride_id uuid)
returns rides language plpgsql security definer set search_path = public as $$
begin
  raise exception 'cancel_reason_required';
end $$;

create or replace function driver_update_ride(p_ride_id uuid, p_status ride_status)
returns rides language plpgsql security definer set search_path = public as $$
declare d drivers := current_driver(); r rides;
begin
  if p_status = 'cancelled' then raise exception 'cancel_reason_required'; end if;
  select * into r from rides where id = p_ride_id and driver_id = d.id for update;
  if not found then raise exception 'ride_not_found'; end if;
  if not (
       (r.status = 'accepted'    and p_status = 'arrived')
    or (r.status = 'arrived'     and p_status = 'in_progress')
    or (r.status = 'in_progress' and p_status = 'completed')
  ) then raise exception 'invalid_transition:%->%', r.status, p_status; end if;
  update rides set status = p_status, updated_at = now(),
                   completed_at = case when p_status = 'completed' then now() else completed_at end
   where id = r.id returning * into r;
  perform notify_user(r.customer_id,
    case p_status when 'arrived' then 'السائق وصل لمكانك'
                  when 'in_progress' then 'بدأت الرحلة'
                  else 'وصلت بالسلامة · الأجرة ' || r.fare || ' د.ع' end,
    '', jsonb_build_object('type', 'ride', 'id', r.id));
  return r;
end $$;

-- ---------------------------------------------------------------------
-- إلغاء الرحلة (الزبون أو السائق) مع السبب
-- ---------------------------------------------------------------------
create or replace function cancel_ride(p_ride_id uuid, p_reason text, p_note text default '')
returns rides language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  r rides; prev ride_status; pty text; resp uuid; rs cancel_reasons;
  n int; span interval; note text := left(btrim(coalesce(p_note, '')), 300);
  rk text; msg_title text; msg_body text; rstr user_restrictions;
begin
  -- قفل المستخدم أولاً ثم الرحلة (ترتيب ثابت يمنع التعارض)
  perform pg_advisory_xact_lock(hashtext('ride_cancel:' || uid::text));

  select * into r from rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found'; end if;

  if uid = r.customer_id then pty := 'customer'; resp := uid;
  elsif r.driver_id is not null and uid = r.driver_id then pty := 'driver'; resp := uid;
  else raise exception 'forbidden' using errcode = '42501';
  end if;

  if r.status = 'cancelled' then raise exception 'ride_already_cancelled'; end if;
  if r.status not in ('requested', 'accepted', 'arrived') then raise exception 'cannot_cancel_now'; end if;
  -- السائق يلغي فقط رحلة تم تعيينها له (accepted أو arrived)
  if pty = 'driver' and r.status not in ('accepted', 'arrived') then raise exception 'cannot_cancel_now'; end if;

  select * into rs from cancel_reasons where cancel_reasons.party = pty and cancel_reasons.id = p_reason and is_active;
  if not found then raise exception 'invalid_cancel_reason'; end if;
  if rs.needs_note and char_length(note) < 5 then raise exception 'note_required'; end if;

  prev := r.status;
  update rides set status = 'cancelled', updated_at = now() where id = r.id returning * into r;

  begin
    insert into ride_cancellations (ride_id, party, actor_id, responsible_id, reason_code, reason_label, note, ride_status_before)
    values (r.id, pty, uid, resp, rs.id, rs.label, note, prev);
  exception when unique_violation then
    raise exception 'ride_already_cancelled';
  end;

  -- إشعار الطرف الآخر
  if pty = 'customer' and r.driver_id is not null then
    perform notify_user(r.driver_id, 'الزبون ألغى الرحلة', rs.label, jsonb_build_object('type', 'ride', 'id', r.id));
  elsif pty = 'driver' then
    perform notify_user(r.customer_id, 'السائق ألغى الرحلة', rs.label, jsonb_build_object('type', 'ride', 'id', r.id));
  end if;

  -- العدّ اليومي والإيقاف عند كل 10 إلغاءات في اليوم
  n := cancellations_today(resp, pty);
  if n > 0 and n % 10 = 0 then
    if pty = 'customer' then
      rk := 'customer_rides'; span := interval '24 hours';
    else
      rk := 'driver_dispatch'; span := interval '25 minutes';
    end if;
    insert into user_restrictions (user_id, kind, trigger_count, day_start, starts_at, ends_at, reason)
    values (resp, rk, n, baghdad_day_start(), now(), now() + span,
            'تكرار إلغاء الرحلات (' || n || ' خلال اليوم)')
    on conflict (user_id, kind, day_start, trigger_count) do nothing
    returning * into rstr;
    if found then
      if pty = 'customer' then
        msg_title := 'تم إيقاف طلب الرحلات مؤقتاً';
        msg_body := 'تم إيقاف إمكانية طلب الرحلات مؤقتاً بسبب تسجيل ' || n || ' حالات إلغاء خلال اليوم. '
                 || 'يمكنك استخدام خدمة التكسي مجدداً بعد انتهاء مدة الإيقاف (تنتهي الساعة '
                 || to_char(rstr.ends_at at time zone 'Asia/Baghdad', 'HH24:MI') || ' بتوقيت بغداد).';
      else
        msg_title := 'تم إيقاف استقبال الطلبات مؤقتاً';
        msg_body := 'تم إيقاف استقبال طلبات الرحلات لمدة 25 دقيقة بسبب تكرار إلغاء الرحلات. '
                 || 'سيعود حسابك لاستقبال الطلبات تلقائياً بعد انتهاء المدة.';
      end if;
      perform notify_user(resp, msg_title, msg_body, jsonb_build_object('type', 'restriction', 'kind', rk, 'ends_at', rstr.ends_at));
    end if;
  end if;

  return r;
end $$;

-- ---------------------------------------------------------------------
-- الإدارة: إلغاء بلا عدّ، وإيقاف الإيقاف، والتدقيق
-- ---------------------------------------------------------------------
create or replace function admin_cancel_ride(p_ride_id uuid, p_reason text)
returns rides language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r rides; prev ride_status; v_reason text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if char_length(v_reason) < 3 then raise exception 'reason_required'; end if;
  select * into r from rides where id = p_ride_id for update;
  if not found then raise exception 'ride_not_found'; end if;
  if r.status = 'cancelled' then raise exception 'ride_already_cancelled'; end if;
  if r.status not in ('requested', 'accepted', 'arrived') then raise exception 'cannot_cancel_now'; end if;
  prev := r.status;
  update rides set status = 'cancelled', updated_at = now() where id = r.id returning * into r;
  insert into ride_cancellations (ride_id, party, actor_id, responsible_id, reason_code, reason_label, note, ride_status_before)
  values (r.id, 'admin', uid, null, 'admin', v_reason, '', prev);
  insert into admin_audit_log (actor_id, action, target_type, target_id, details)
  values (uid, 'ride.cancel', 'ride', r.id::text, jsonb_build_object('reason', v_reason, 'status_before', prev));
  perform notify_user(r.customer_id, 'ألغت الإدارة الرحلة', v_reason, jsonb_build_object('type', 'ride', 'id', r.id));
  if r.driver_id is not null then
    perform notify_user(r.driver_id, 'ألغت الإدارة الرحلة', v_reason, jsonb_build_object('type', 'ride', 'id', r.id));
  end if;
  return r;
end $$;

create or replace function admin_lift_restriction(p_restriction_id uuid, p_reason text)
returns user_restrictions language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); rs user_restrictions; v_reason text := left(btrim(coalesce(p_reason, '')), 300);
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if char_length(v_reason) < 5 then raise exception 'reason_required'; end if;
  select * into rs from user_restrictions where id = p_restriction_id for update;
  if not found then raise exception 'restriction_not_found'; end if;
  if rs.lifted_at is not null or rs.ends_at <= now() then raise exception 'restriction_not_active'; end if;
  update user_restrictions set lifted_at = now(), lifted_by = uid, lift_reason = v_reason
   where id = rs.id returning * into rs;
  insert into admin_audit_log (actor_id, action, target_type, target_id, details)
  values (uid, 'restriction.lift', 'user_restriction', rs.id::text,
          jsonb_build_object('user_id', rs.user_id, 'kind', rs.kind, 'reason', v_reason));
  perform notify_user(rs.user_id, 'تم رفع الإيقاف عن حسابك', v_reason, jsonb_build_object('type', 'restriction_lifted'));
  return rs;
end $$;

-- ---------------------------------------------------------------------
-- انتهاء طلبات بلا سائق (بدون عدّ على أحد)
-- ---------------------------------------------------------------------
create or replace function expire_stale_ride_requests(p_older_than interval default interval '15 minutes')
returns int language plpgsql security definer set search_path = public as $$
declare n int := 0; r rides;
begin
  for r in
    select * from rides where status = 'requested' and driver_id is null and created_at < now() - p_older_than
    for update skip locked
  loop
    update rides set status = 'cancelled', updated_at = now() where id = r.id;
    insert into ride_cancellations (ride_id, party, actor_id, responsible_id, reason_code, reason_label, note, ride_status_before)
    values (r.id, 'system', null, null, 'expired', 'انتهت مهلة الطلب بدون سائق', '', 'requested');
    perform notify_user(r.customer_id, 'انتهت مهلة طلبك', 'ما لقينا سائق متاح. حاول مرة ثانية.', jsonb_build_object('type', 'ride', 'id', r.id));
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- لوحة الإدارة: ملخصات وقوائم (من قاعدة البيانات مباشرة)
-- ---------------------------------------------------------------------
create or replace function admin_cancellation_summary()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare ds timestamptz := baghdad_day_start();
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'day_start', ds,
    'today_total', (select count(*) from ride_cancellations where cancelled_at >= ds),
    'today_customer', (select count(*) from ride_cancellations where cancelled_at >= ds and party = 'customer'),
    'today_driver', (select count(*) from ride_cancellations where cancelled_at >= ds and party = 'driver'),
    'today_admin', (select count(*) from ride_cancellations where cancelled_at >= ds and party = 'admin'),
    'today_system', (select count(*) from ride_cancellations where cancelled_at >= ds and party = 'system'),
    'restricted_customers', (select count(*) from user_restrictions where kind = 'customer_rides' and lifted_at is null and ends_at > now()),
    'restricted_drivers', (select count(*) from user_restrictions where kind = 'driver_dispatch' and lifted_at is null and ends_at > now()),
    'reasons_today', coalesce((
        select jsonb_agg(jsonb_build_object('party', party, 'reason', reason_label, 'count', c) order by c desc)
          from (select party, reason_label, count(*) c from ride_cancellations
                 where cancelled_at >= ds group by party, reason_label) x), '[]'::jsonb)
  );
end $$;

create or replace function admin_list_cancellations(p_party text default null, p_search text default null, p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s text := lower(btrim(coalesce(p_search, '')));
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(t) order by t.cancelled_at desc) from (
      select c.id, c.cancelled_at, c.party, c.reason_label, c.note, c.ride_status_before,
             c.ride_id, r.pickup_text, r.dropoff_text, r.fare,
             cu.full_name as customer_name, cu.phone as customer_phone,
             du.full_name as driver_name, du.phone as driver_phone
        from ride_cancellations c
        join rides r on r.id = c.ride_id
        join users cu on cu.id = r.customer_id
        left join users du on du.id = r.driver_id
       where (p_party is null or p_party = '' or c.party = p_party)
         and (s = '' or r.id::text like s || '%' or lower(cu.full_name) like '%' || s || '%'
              or cu.phone like '%' || s || '%' or lower(coalesce(du.full_name, '')) like '%' || s || '%'
              or coalesce(du.phone, '') like '%' || s || '%')
       order by c.cancelled_at desc
       limit least(greatest(p_limit, 1), 300)
    ) t), '[]'::jsonb);
end $$;

create or replace function admin_list_restrictions(p_active_only boolean default true, p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(t) order by t.starts_at desc) from (
      select x.id, x.kind, x.starts_at, x.ends_at, x.reason, x.trigger_count, x.lifted_at, x.lift_reason,
             u.id as user_id, u.full_name, u.phone
        from user_restrictions x join users u on u.id = x.user_id
       where (not p_active_only or (x.lifted_at is null and x.ends_at > now()))
       order by x.starts_at desc
       limit least(greatest(p_limit, 1), 300)
    ) t), '[]'::jsonb);
end $$;

create or replace function admin_audit_list(p_limit int default 100)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(row_to_json(t) order by t.created_at desc) from (
      select a.id, a.created_at, a.action, a.target_type, a.target_id, a.details, u.full_name as actor_name
        from admin_audit_log a left join users u on u.id = a.actor_id
       order by a.created_at desc
       limit least(greatest(p_limit, 1), 300)
    ) t), '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- الصلاحيات
-- ---------------------------------------------------------------------
grant execute on function cancel_ride(uuid, text, text) to authenticated;
grant execute on function admin_cancel_ride(uuid, text) to authenticated;
grant execute on function admin_lift_restriction(uuid, text) to authenticated;
grant execute on function my_restrictions() to authenticated;
grant execute on function admin_cancellation_summary() to authenticated;
grant execute on function admin_list_cancellations(text, text, int) to authenticated;
grant execute on function admin_list_restrictions(boolean, int) to authenticated;
grant execute on function admin_audit_list(int) to authenticated;
grant execute on function expire_stale_ride_requests(interval) to service_role;
revoke execute on function expire_stale_ride_requests(interval) from public, authenticated;
grant execute on function request_ride(vehicle_type, text, double precision, double precision, text, double precision, double precision) to authenticated;
grant execute on function driver_accept_ride(uuid) to authenticated;

notify pgrst, 'reload schema';
