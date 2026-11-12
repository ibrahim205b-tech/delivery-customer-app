-- =====================================================================
-- WASEL | واصل — مراسلة الدعم داخل التطبيق
-- محادثة وحدة لكل مستخدم بكل تطبيق (مستهلك / تاجر / سائق) مع إدارة واصل.
-- الكتابة عبر دوال بالخادم فقط؛ القراءة بـ RLS (صاحب المحادثة أو الإدارة).
-- =====================================================================

create table if not exists support_threads (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references users (id) on delete cascade,
  app              text not null check (app in ('customer', 'merchant', 'driver')),
  status           text not null default 'open' check (status in ('open', 'closed')),
  last_message     text not null default '',
  last_message_at  timestamptz not null default now(),
  unread_for_admin int not null default 0,
  unread_for_user  int not null default 0,
  created_at       timestamptz not null default now(),
  unique (user_id, app)
);
create index if not exists support_threads_recent_idx on support_threads (last_message_at desc);

create table if not exists support_messages (
  id          bigint generated always as identity primary key,
  thread_id   uuid not null references support_threads (id) on delete cascade,
  sender_id   uuid references users (id) on delete set null,
  from_admin  boolean not null default false,
  body        text not null check (char_length(btrim(body)) between 1 and 2000),
  order_code  text,
  created_at  timestamptz not null default now()
);
create index if not exists support_messages_thread_idx on support_messages (thread_id, id);

alter table support_threads  enable row level security;
alter table support_messages enable row level security;

drop policy if exists support_threads_read on support_threads;
create policy support_threads_read on support_threads for select to authenticated
  using (user_id = auth.uid() or is_admin());

drop policy if exists support_messages_read on support_messages;
create policy support_messages_read on support_messages for select to authenticated
  using (exists (select 1 from support_threads t where t.id = thread_id and (t.user_id = auth.uid() or is_admin())));

grant select on support_threads, support_messages to authenticated;
grant all on support_threads, support_messages to service_role;

-- إرسال رسالة من المستخدم (ينشئ المحادثة إذا ما موجودة، ويعيد فتحها إذا مسكّرة)
create or replace function support_send(p_app text, p_body text, p_order_code text default null)
returns support_messages language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  th support_threads;
  msg support_messages;
  b text := btrim(coalesce(p_body, ''));
begin
  if p_app not in ('customer', 'merchant', 'driver') then raise exception 'invalid_app'; end if;
  if char_length(b) = 0 then raise exception 'empty_message'; end if;
  if char_length(b) > 2000 then raise exception 'message_too_long'; end if;
  insert into support_threads (user_id, app) values (uid, p_app)
    on conflict (user_id, app) do nothing;
  select * into th from support_threads where user_id = uid and app = p_app;
  insert into support_messages (thread_id, sender_id, from_admin, body, order_code)
    values (th.id, uid, false, b, nullif(btrim(coalesce(p_order_code, '')), ''))
    returning * into msg;
  update support_threads set status = 'open', last_message = left(b, 140), last_message_at = msg.created_at,
         unread_for_admin = unread_for_admin + 1
   where id = th.id;
  return msg;
end $$;

-- رد الإدارة (يوصل للمستخدم كإشعار أيضاً)
create or replace function support_reply(p_thread uuid, p_body text)
returns support_messages language plpgsql security definer set search_path = public as $$
declare
  uid uuid := require_user();
  th support_threads;
  msg support_messages;
  b text := btrim(coalesce(p_body, ''));
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if char_length(b) = 0 then raise exception 'empty_message'; end if;
  if char_length(b) > 2000 then raise exception 'message_too_long'; end if;
  select * into th from support_threads where id = p_thread;
  if not found then raise exception 'not_found'; end if;
  insert into support_messages (thread_id, sender_id, from_admin, body)
    values (th.id, uid, true, b) returning * into msg;
  update support_threads set last_message = left(b, 140), last_message_at = msg.created_at,
         unread_for_user = unread_for_user + 1
   where id = th.id;
  perform notify_user(th.user_id, 'رد من دعم واصل', left(b, 140), jsonb_build_object('type', 'support', 'app', th.app));
  return msg;
end $$;

-- تعليم المحادثة كمقروءة (المستخدم لمحادثته، والإدارة لأي محادثة)
create or replace function support_mark_read(p_thread uuid)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := require_user();
begin
  if is_admin() then
    update support_threads set unread_for_admin = 0 where id = p_thread;
  end if;
  update support_threads set unread_for_user = 0 where id = p_thread and user_id = uid;
end $$;

-- الإدارة تسكّر أو تفتح محادثة
create or replace function support_set_status(p_thread uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform require_user();
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  if p_status not in ('open', 'closed') then raise exception 'invalid_status'; end if;
  update support_threads set status = p_status where id = p_thread;
end $$;

revoke execute on function support_send(text, text, text), support_reply(uuid, text), support_mark_read(uuid), support_set_status(uuid, text) from public, anon;
grant execute on function support_send(text, text, text), support_reply(uuid, text), support_mark_read(uuid), support_set_status(uuid, text) to authenticated, service_role;

-- رقم واتساب الدعم (إعداد قابل للتعديل من تطبيق الإدارة)
insert into app_settings (key, value) values ('support', '{"phone": "", "whatsapp": ""}')
on conflict (key) do update set value = app_settings.value || jsonb_build_object('whatsapp', coalesce(app_settings.value->>'whatsapp', ''));

-- التحديثات اللحظية
do $$ begin
  alter publication supabase_realtime add table support_threads, support_messages;
exception when duplicate_object then null;
end $$;

notify pgrst, 'reload schema';
