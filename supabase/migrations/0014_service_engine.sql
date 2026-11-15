-- =====================================================================
-- WASEL SUPER APP | المرحلة 2: المحرك المشترك للخدمات + حجز الملاعب
--
-- المحرك المشترك (service_requests):
--   كل خدمة من نوع "حجز/طلب من مقدم خدمة" تمر بنفس الدورة:
--   requested → accepted | rejected | cancelled
--   accepted  → in_progress | completed | cancelled
--   in_progress → completed | cancelled
--   كل تغيير يُسجَّل في service_request_events (سجل تدقيق) ويُرسل إشعاراً للطرف الآخر.
--   العمولة تُحسب عند completed فقط، من إعداد الخدمة في app_settings.
--
-- حجز الملاعب (pitches): الملعب يتبع مقدم خدمة من نوع pitch_owner. صاحب الملعب يحدد السعر
-- والساعات والحد الأدنى وسياسة الإلغاء بنفسه. لا توجد أرقام افتراضية وهمية.
-- منع الحجز المزدوج: التحقق عند القبول تحت قفل لكل ملعب، ولا يُقبل حجز يتداخل مع حجز مقبول.
-- التأثير: جداول وأعمدة جديدة ودوال. لا تغيير على الجداول القائمة إلا إضافة أعمدة اختيارية.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) الطلبات الموحدة
-- ---------------------------------------------------------------------
create table if not exists service_requests (
  id                uuid primary key default gen_random_uuid(),
  service_id        text not null references services (id) on delete restrict,
  customer_id       uuid not null references users (id) on delete restrict,
  provider_id       uuid not null references merchants (id) on delete restrict,
  area_id           uuid references service_areas (id) on delete set null,
  status            text not null default 'requested'
                    check (status in ('requested', 'accepted', 'rejected', 'in_progress', 'completed', 'cancelled')),
  payload           jsonb not null default '{}'::jsonb,
  amount            int not null default 0 check (amount >= 0),
  client_request_id uuid unique,
  reject_reason     text not null default '' check (char_length(reject_reason) <= 300),
  cancel_reason     text not null default '' check (char_length(cancel_reason) <= 300),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  responded_at      timestamptz,
  completed_at      timestamptz
);
create index if not exists service_requests_customer_idx on service_requests (customer_id, created_at desc);
create index if not exists service_requests_provider_idx on service_requests (provider_id, status, created_at desc);
create index if not exists service_requests_service_idx on service_requests (service_id, status);

create table if not exists service_request_events (
  id          bigint generated always as identity primary key,
  request_id  uuid not null references service_requests (id) on delete cascade,
  actor_id    uuid references users (id) on delete set null,
  from_status text,
  to_status   text not null,
  note        text not null default '',
  created_at  timestamptz not null default now()
);
create index if not exists service_request_events_req_idx on service_request_events (request_id, created_at);

create table if not exists service_commissions (
  id          bigint generated always as identity primary key,
  request_id  uuid not null unique references service_requests (id) on delete cascade,
  service_id  text not null references services (id),
  provider_id uuid not null references merchants (id) on delete restrict,
  base_amount int not null check (base_amount >= 0),
  model       text not null check (model in ('free', 'percent', 'fixed')),
  value       numeric(10,2) not null default 0,
  amount      int not null default 0 check (amount >= 0),
  created_at  timestamptz not null default now()
);

create table if not exists service_reviews (
  id          bigint generated always as identity primary key,
  request_id  uuid not null unique references service_requests (id) on delete cascade,
  customer_id uuid not null references users (id) on delete cascade,
  provider_id uuid not null references merchants (id) on delete cascade,
  rating      int not null check (rating between 1 and 5),
  comment     text not null default '' check (char_length(comment) <= 500),
  created_at  timestamptz not null default now()
);

alter table service_requests       enable row level security;
alter table service_request_events enable row level security;
alter table service_commissions    enable row level security;
alter table service_reviews        enable row level security;

-- القراءة: الزبون يرى طلباته، ومقدم الخدمة يرى طلبات محله، والإدارة ترى الكل
drop policy if exists service_requests_read on service_requests;
create policy service_requests_read on service_requests for select to authenticated
  using (customer_id = auth.uid() or owns_merchant(provider_id) or is_admin());
drop policy if exists service_events_read on service_request_events;
create policy service_events_read on service_request_events for select to authenticated
  using (exists (select 1 from service_requests r where r.id = request_id
                 and (r.customer_id = auth.uid() or owns_merchant(r.provider_id) or is_admin())));
drop policy if exists service_commissions_read on service_commissions;
create policy service_commissions_read on service_commissions for select to authenticated
  using (is_admin() or owns_merchant(provider_id));
drop policy if exists service_reviews_read on service_reviews;
create policy service_reviews_read on service_reviews for select to authenticated
  using (customer_id = auth.uid() or owns_merchant(provider_id) or is_admin());

-- الكتابة المباشرة ممنوعة: كل شيء عبر الدوال
revoke all on service_requests, service_request_events, service_commissions, service_reviews from authenticated, anon;
grant select on service_requests, service_request_events, service_commissions, service_reviews to authenticated;
grant all on service_requests, service_request_events, service_commissions, service_reviews to service_role;

-- ---------------------------------------------------------------------
-- 2) دورة الحالة: الانتقالات المسموحة وقواعدها
-- ---------------------------------------------------------------------
create or replace function _svc_transition_allowed(p_from text, p_to text)
returns boolean language sql immutable as $$
  select (p_from, p_to) in (
    ('requested', 'accepted'), ('requested', 'rejected'), ('requested', 'cancelled'),
    ('accepted', 'in_progress'), ('accepted', 'completed'), ('accepted', 'cancelled'),
    ('in_progress', 'completed'), ('in_progress', 'cancelled')
  );
$$;

-- يحوّل الحالة ويسجّل الحدث ويرسل الإشعار ويحسب العمولة عند الإتمام
create or replace function _svc_move(p_req uuid, p_to text, p_actor uuid, p_note text default '')
returns service_requests language plpgsql security definer set search_path = public as $$
declare r service_requests; m merchants; cfg jsonb; model text; val numeric; amt int; who_notify uuid; title text;
begin
  select * into r from service_requests where id = p_req for update;
  if not found then raise exception 'request_not_found'; end if;
  if not _svc_transition_allowed(r.status, p_to) then raise exception 'invalid_transition:%->%', r.status, p_to; end if;

  update service_requests set status = p_to, updated_at = now(),
         responded_at = case when p_to in ('accepted', 'rejected') then now() else responded_at end,
         completed_at = case when p_to = 'completed' then now() else completed_at end
   where id = r.id returning * into r;

  insert into service_request_events (request_id, actor_id, from_status, to_status, note)
  values (r.id, p_actor, null, p_to, coalesce(p_note, ''));

  -- العمولة: مرة واحدة عند الإتمام (unique على request_id)
  if p_to = 'completed' then
    select * into m from merchants where id = r.provider_id;
    cfg := coalesce((select value -> r.service_id from app_settings where key = 'service_commissions'), '{}'::jsonb);
    model := coalesce(cfg ->> 'model', 'free');
    val := coalesce((cfg ->> 'value')::numeric, 0);
    amt := case model
             when 'percent' then round(r.amount * least(greatest(val, 0), 50) / 100.0)::int
             when 'fixed' then least(greatest(val, 0), 2147483647)::int
             else 0 end;
    insert into service_commissions (request_id, service_id, provider_id, base_amount, model, value, amount)
    values (r.id, r.service_id, r.provider_id, r.amount, model, val, amt)
    on conflict (request_id) do nothing;
  end if;

  -- الإشعار للطرف الآخر
  if p_actor = r.customer_id then
    who_notify := (select owner_id from merchants where id = r.provider_id);
  else
    who_notify := r.customer_id;
  end if;
  title := case p_to
    when 'accepted' then 'تم قبول الحجز'
    when 'rejected' then 'تم رفض الطلب'
    when 'in_progress' then 'بدأت الخدمة'
    when 'completed' then 'انتهت الخدمة'
    when 'cancelled' then 'تم إلغاء الطلب'
    else 'تحديث على طلبك' end;
  perform notify_user(who_notify, title, '', jsonb_build_object('type', 'service_request', 'id', r.id, 'status', p_to));
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 3) الملاعب
-- ---------------------------------------------------------------------
create table if not exists pitches (
  id                  uuid primary key default gen_random_uuid(),
  merchant_id         uuid not null references merchants (id) on delete cascade,
  name_ar             text not null check (char_length(btrim(name_ar)) between 2 and 120),
  description         text not null default '' check (char_length(description) <= 500),
  price_per_hour      int not null default 0 check (price_per_hour >= 0),
  min_minutes         int not null default 60 check (min_minutes between 30 and 480),
  open_hour           int not null default 8 check (open_hour between 0 and 23),
  close_hour          int not null default 23 check (close_hour between 1 and 24),
  cancel_before_hours int not null default 2 check (cancel_before_hours between 0 and 168),
  cancellation_policy text not null default '' check (char_length(cancellation_policy) <= 500),
  is_active           boolean not null default false,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  check (open_hour < close_hour),
  check (not is_active or price_per_hour > 0)
);
create index if not exists pitches_merchant_idx on pitches (merchant_id);

alter table pitches enable row level security;
drop policy if exists pitches_read on pitches;
create policy pitches_read on pitches for select to authenticated
  using ((is_active and exists (select 1 from merchants m where m.id = merchant_id and m.status = 'approved'))
         or owns_merchant(merchant_id) or is_admin());
revoke all on pitches from authenticated, anon;
grant select on pitches to authenticated;
grant all on pitches to service_role;

-- صاحب الملعب (أو الإدارة) يحفظ بيانات الملعب. الإيقاف والتفعيل من نفس الدالة.
create or replace function upsert_pitch(
  p_id uuid, p_merchant_id uuid, p_name text, p_description text, p_price_per_hour int,
  p_min_minutes int, p_open_hour int, p_close_hour int, p_cancel_before_hours int,
  p_cancellation_policy text, p_is_active boolean
) returns pitches language plpgsql security definer set search_path = public as $$
declare r pitches; m merchants;
begin
  select * into m from merchants where id = p_merchant_id;
  if not found then raise exception 'merchant_not_found'; end if;
  if not (owns_merchant(p_merchant_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if m.business_type <> 'pitch_owner' then raise exception 'not_pitch_owner'; end if;
  if m.status <> 'approved' and coalesce(p_is_active, false) then raise exception 'merchant_not_approved'; end if;
  if p_id is null then
    insert into pitches (merchant_id, name_ar, description, price_per_hour, min_minutes, open_hour, close_hour,
                         cancel_before_hours, cancellation_policy, is_active)
    values (p_merchant_id, btrim(p_name), coalesce(p_description, ''), p_price_per_hour, p_min_minutes, p_open_hour,
            p_close_hour, p_cancel_before_hours, coalesce(p_cancellation_policy, ''), coalesce(p_is_active, false))
    returning * into r;
  else
    -- إنشاء بمعرّف محدد أو تحديث ملعب موجود لنفس الصاحب فقط
    insert into pitches (id, merchant_id, name_ar, description, price_per_hour, min_minutes, open_hour, close_hour,
                         cancel_before_hours, cancellation_policy, is_active)
    values (p_id, p_merchant_id, btrim(p_name), coalesce(p_description, ''), p_price_per_hour, p_min_minutes, p_open_hour,
            p_close_hour, p_cancel_before_hours, coalesce(p_cancellation_policy, ''), coalesce(p_is_active, false))
    on conflict (id) do update set name_ar = excluded.name_ar, description = excluded.description,
           price_per_hour = excluded.price_per_hour, min_minutes = excluded.min_minutes, open_hour = excluded.open_hour,
           close_hour = excluded.close_hour, cancel_before_hours = excluded.cancel_before_hours,
           cancellation_policy = excluded.cancellation_policy, is_active = excluded.is_active, updated_at = now()
     where pitches.merchant_id = p_merchant_id
    returning * into r;
    if r.id is null then raise exception 'pitch_not_found'; end if;
  end if;
  return r;
end $$;

-- الساعات المحجوزة (مقبولة فقط) ليوم معيّن، بتوقيت بغداد. لا تكشف أي بيانات للزبون.
create or replace function pitch_busy_slots(p_pitch_id uuid, p_day date)
returns table (starts_at timestamptz, ends_at timestamptz) language sql stable security definer set search_path = public as $$
  select (r.payload->>'starts_at')::timestamptz, (r.payload->>'ends_at')::timestamptz
    from service_requests r
   where r.service_id = 'pitch_booking' and r.status in ('accepted', 'in_progress', 'completed')
     and (r.payload->>'pitch_id')::uuid = p_pitch_id
     and (r.payload->>'starts_at')::timestamptz >= (p_day::timestamp at time zone 'Asia/Baghdad')
     and (r.payload->>'starts_at')::timestamptz < ((p_day + 1)::timestamp at time zone 'Asia/Baghdad')
   order by 1;
$$;

-- الزبون يطلب حجزاً. لا يُحجز شيء هنا: الحجز يتأكد عند قبول صاحب الملعب.
create or replace function pitch_book_request(
  p_pitch_id uuid, p_starts_at timestamptz, p_minutes int, p_client_request_id uuid
) returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); p pitches; r service_requests; ends timestamptz; hr_start int; hr_end numeric; amt int;
begin
  if not exists (select 1 from services where id = 'pitch_booking' and is_active) then raise exception 'service_inactive'; end if;
  -- إعادة الإرسال بنفس المعرّف ترجّع الطلب الأصلي
  if p_client_request_id is not null then
    select * into r from service_requests where client_request_id = p_client_request_id and customer_id = uid;
    if found then return r; end if;
  end if;
  select * into p from pitches where id = p_pitch_id;
  if not found or not p.is_active then raise exception 'pitch_unavailable'; end if;
  if p_starts_at <= now() then raise exception 'start_in_past'; end if;
  if p_minutes is null or p_minutes < p.min_minutes or p_minutes > 480 or p_minutes % 30 <> 0 then raise exception 'invalid_duration'; end if;
  ends := p_starts_at + make_interval(mins => p_minutes);
  hr_start := extract(hour from (p_starts_at at time zone 'Asia/Baghdad'))::int;
  hr_end := extract(hour from (ends at time zone 'Asia/Baghdad')) + extract(minute from (ends at time zone 'Asia/Baghdad')) / 60.0;
  -- الحجز داخل يوم واحد بتوقيت بغداد؛ انتهاؤه عند منتصف الليل (00:00 اليوم التالي) مسموح فقط إذا الإغلاق 24
  if (ends at time zone 'Asia/Baghdad')::date <> (p_starts_at at time zone 'Asia/Baghdad')::date then
    if not (p.close_hour = 24 and (ends at time zone 'Asia/Baghdad')::time = time '00:00') then raise exception 'outside_hours'; end if;
    hr_end := 24;
  end if;
  if hr_start < p.open_hour or hr_end > p.close_hour then raise exception 'outside_hours'; end if;
  amt := round(p.price_per_hour * p_minutes / 60.0)::int;
  -- الوقت المتاح الآن لا يُحجز مسبقاً: نتحقق من التعارض مع المقبول فقط
  if exists (select 1 from service_requests r2 where r2.service_id = 'pitch_booking'
              and r2.status in ('accepted', 'in_progress', 'completed')
              and (r2.payload->>'pitch_id')::uuid = p_pitch_id
              and (r2.payload->>'starts_at')::timestamptz < ends
              and (r2.payload->>'ends_at')::timestamptz > p_starts_at) then
    raise exception 'slot_taken';
  end if;
  insert into service_requests (service_id, customer_id, provider_id, payload, amount, client_request_id)
  values ('pitch_booking', uid, p.merchant_id,
          jsonb_build_object('pitch_id', p.id, 'pitch_name', p.name_ar, 'starts_at', p_starts_at, 'ends_at', ends, 'minutes', p_minutes),
          amt, p_client_request_id)
  returning * into r;
  insert into service_request_events (request_id, actor_id, from_status, to_status) values (r.id, uid, null, 'requested');
  perform notify_user((select owner_id from merchants where id = p.merchant_id), 'طلب حجز ملعب جديد', p.name_ar,
                      jsonb_build_object('type', 'service_request', 'id', r.id, 'status', 'requested'));
  return r;
end $$;

-- صاحب الملعب يقبل أو يرفض. القبول يتحقق من التعارض تحت قفل الملعب.
create or replace function service_respond(p_request_id uuid, p_accept boolean, p_reason text default '')
returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests; pid uuid;
begin
  select * into r from service_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if not (owns_merchant(r.provider_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if r.status <> 'requested' then raise exception 'invalid_transition:%', r.status; end if;
  if p_accept then
    if r.service_id = 'pitch_booking' then
      pid := (r.payload->>'pitch_id')::uuid;
      perform pg_advisory_xact_lock(hashtext(pid::text));
      if exists (select 1 from service_requests r2 where r2.service_id = 'pitch_booking' and r2.id <> r.id
                  and r2.status in ('accepted', 'in_progress', 'completed')
                  and (r2.payload->>'pitch_id')::uuid = pid
                  and (r2.payload->>'starts_at')::timestamptz < (r.payload->>'ends_at')::timestamptz
                  and (r2.payload->>'ends_at')::timestamptz > (r.payload->>'starts_at')::timestamptz) then
        raise exception 'slot_taken';
      end if;
    end if;
    return _svc_move(r.id, 'accepted', uid, '');
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  update service_requests set reject_reason = btrim(p_reason) where id = r.id;
  return _svc_move(r.id, 'rejected', uid, btrim(p_reason));
end $$;

-- تغيير الحالة بعد القبول (بدء/إتمام) من مقدم الخدمة أو الإدارة
create or replace function service_set_status(p_request_id uuid, p_to text)
returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests;
begin
  select * into r from service_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if not (owns_merchant(r.provider_id) or is_admin()) then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_to not in ('in_progress', 'completed') then raise exception 'invalid_status'; end if;
  return _svc_move(p_request_id, p_to, uid, '');
end $$;

-- إلغاء: الزبون يلغي قبل الموعد بالمدة التي يحددها صاحب الملعب، ومقدم الخدمة يلغي بسبب
create or replace function service_cancel(p_request_id uuid, p_reason text default '')
returns service_requests language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests; p pitches; lead_h int;
begin
  select * into r from service_requests where id = p_request_id;
  if not found then raise exception 'request_not_found'; end if;
  if r.customer_id = uid then
    if r.service_id = 'pitch_booking' then
      select * into p from pitches where id = (r.payload->>'pitch_id')::uuid;
      lead_h := coalesce(p.cancel_before_hours, 0);
      if r.status in ('accepted') and now() > (r.payload->>'starts_at')::timestamptz - make_interval(hours => lead_h) then
        raise exception 'cancellation_window_closed';
      end if;
    end if;
  elsif not (owns_merchant(r.provider_id) or is_admin()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  update service_requests set cancel_reason = btrim(coalesce(p_reason, '')) where id = r.id;
  return _svc_move(r.id, 'cancelled', uid, btrim(coalesce(p_reason, '')));
end $$;

-- تقييم بعد الإتمام (مرة واحدة)
create or replace function service_rate(p_request_id uuid, p_rating int, p_comment text default '')
returns service_reviews language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user(); r service_requests; v service_reviews;
begin
  select * into r from service_requests where id = p_request_id and customer_id = uid;
  if not found or r.status <> 'completed' then raise exception 'cannot_rate'; end if;
  if p_rating is null or p_rating < 1 or p_rating > 5 then raise exception 'invalid_rating'; end if;
  insert into service_reviews (request_id, customer_id, provider_id, rating, comment)
  values (r.id, uid, r.provider_id, p_rating, left(coalesce(p_comment, ''), 500))
  returning * into v;
  return v;
end $$;

grant execute on function pitch_book_request(uuid, timestamptz, int, uuid) to authenticated;
grant execute on function service_respond(uuid, boolean, text) to authenticated;
grant execute on function service_set_status(uuid, text) to authenticated;
grant execute on function service_cancel(uuid, text) to authenticated;
grant execute on function service_rate(uuid, int, text) to authenticated;
grant execute on function upsert_pitch(uuid, uuid, text, text, int, int, int, int, int, text, boolean) to authenticated;
grant execute on function pitch_busy_slots(uuid, date) to authenticated;
revoke execute on function _svc_move(uuid, text, uuid, text) from public, anon, authenticated;
revoke execute on function _svc_transition_allowed(text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) تفعيل خدمة الملاعب بمحركها الآن (التفعيل الفعلي من الإدارة)
-- ---------------------------------------------------------------------
update services set engine = 'booking', updated_at = now() where id = 'pitch_booking';

notify pgrst, 'reload schema';
