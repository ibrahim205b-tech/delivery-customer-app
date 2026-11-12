-- =====================================================================
-- WASEL | تقارير الإدارة (بيانات حقيقية للرسوم البيانية)
-- =====================================================================
-- يشغَّل بعد 0001..0005. آمن للتشغيل أكثر من مرة (create or replace).

create or replace function admin_reports(p_days int default 14)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  days int := least(greatest(coalesce(p_days, 14), 1), 90);
  start_day date := ((now() at time zone 'Asia/Baghdad')::date - (days - 1));
begin
  if not is_admin() then raise exception 'forbidden' using errcode = '42501'; end if;
  return jsonb_build_object(
    'days', days,
    -- لكل يوم: كل الطلبات، المسلّمة، الملغاة، ومبيعات المسلّمة (بدون التوصيل)
    'daily', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'day', d::date,
               'orders', coalesce(x.orders, 0),
               'delivered', coalesce(x.delivered, 0),
               'cancelled', coalesce(x.cancelled, 0),
               'sales', coalesce(x.sales, 0),
               'rides', coalesce(r.rides, 0)) order by d), '[]'::jsonb)
      from generate_series(start_day, start_day + (days - 1), interval '1 day') d
      left join (
        select (created_at at time zone 'Asia/Baghdad')::date as day,
               count(*) as orders,
               count(*) filter (where status = 'delivered') as delivered,
               count(*) filter (where status = 'cancelled') as cancelled,
               sum(subtotal) filter (where status = 'delivered') as sales
        from orders
        where created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by 1
      ) x on x.day = d::date
      left join (
        select (created_at at time zone 'Asia/Baghdad')::date as day, count(*) as rides
        from rides
        where created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by 1
      ) r on r.day = d::date
    ),
    -- توزيع حالات الطلبات بالفترة
    'by_status', (
      select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (
        select status::text, count(*) n from orders
        where created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by status
      ) s
    ),
    -- الطلبات حسب القسم
    'by_category', (
      select coalesce(jsonb_agg(jsonb_build_object('category', c.name, 'orders', t.n) order by t.n desc), '[]'::jsonb) from (
        select m.category_id, count(*) n from orders o join merchants m on m.id = o.merchant_id
        where o.created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by m.category_id
      ) t join merchant_categories c on c.id = t.category_id
    ),
    -- أفضل المحلات بالطلبات المسلّمة
    'top_merchants', (
      select coalesce(jsonb_agg(jsonb_build_object('name', name, 'delivered', n, 'sales', sales) order by n desc), '[]'::jsonb) from (
        select m.name, count(*) n, sum(o.subtotal) sales from orders o join merchants m on m.id = o.merchant_id
        where o.status = 'delivered' and o.created_at >= start_day::timestamp at time zone 'Asia/Baghdad'
        group by m.name order by n desc limit 5
      ) t
    )
  );
end $$;

revoke execute on function admin_reports(int) from public, anon;
grant execute on function admin_reports(int) to authenticated, service_role;

-- خريطة العمليات: مواقع السائقين المتاحين وآخر ظهور (للإدارة فقط عبر RLS على drivers)
-- لا تحتاج دالة: الإدارة تقرأ drivers + users مباشرة.

-- تحديث ذاكرة PostgREST حتى تظهر الدالة فوراً للتطبيقات
notify pgrst, 'reload schema';
