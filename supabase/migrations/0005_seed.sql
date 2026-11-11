-- =====================================================================
-- WASEL | بيانات الإعداد الأساسية (ليست بيانات وهمية)
-- =====================================================================
-- الأقسام، أنواع الخدمات المنزلية، والإعدادات الافتراضية.
-- المحلات والمناطق والسائقون تضيفهم الإدارة من تطبيق WASEL ADMIN.

insert into merchant_categories (id, name, kind, icon, sort) values
  ('restaurants',  'المطاعم',           'store',        'restaurant', 1),
  ('supermarket',  'السوبر ماركت',      'store',        'supermarket', 2),
  ('home_services','الأعمال المنزلية',   'home_service', 'home_repair', 3),
  ('sweets',       'الحلويات',          'store',        'sweets', 4),
  ('mobiles',      'الموبايلات',        'store',        'mobile', 5),
  ('bakery',       'المخابز والأفران',   'store',        'bakery', 6),
  ('produce',      'الخضار والفواكه',    'store',        'produce', 7),
  ('taxi',         'التكسي',            'ride',         'taxi', 8),
  ('tuktuk',       'التكتك',            'ride',         'tuktuk', 9),
  ('courier',      'الدلفري والمندوب',   'courier',      'courier', 10),
  ('parcel',       'توصيل الأغراض',      'parcel',       'parcel', 11)
on conflict (id) do nothing;

insert into home_services (name, icon, sort) values
  ('سباكة', 'plumbing', 1),
  ('كهرباء', 'electric', 2),
  ('صيانة منزلية', 'handyman', 3),
  ('تنظيف', 'cleaning', 4)
on conflict (name) do nothing;

insert into app_settings (key, value) values
  -- أجور الرحلات: mode = distance (حسب المسافة) أو fixed (ثابتة)
  ('ride_pricing', '{
     "taxi":   {"mode": "distance", "base": 2000, "per_km": 750, "fixed": 5000, "min": 3000},
     "tuktuk": {"mode": "distance", "base": 1000, "per_km": 500, "fixed": 3000, "min": 1500}
   }'),
  -- المندوب وتوصيل الأغراض
  ('errand_pricing', '{"mode": "distance", "base": 2000, "per_km": 500, "fixed": 3000, "min": 2000, "max_km": 30}'),
  -- الحد الأدنى العام للطلب (يُضاف لحد المحل إن كان أكبر)
  ('min_order', '{"amount": 0}'),
  -- السماح بالطلب خارج نطاق توصيل المحل
  ('allow_out_of_area', '{"enabled": false}'),
  -- العمولات: معطلة افتراضياً ولا تُحتسب حالياً
  ('commission', '{"enabled": false, "percent": 0}'),
  -- أوقات تشغيل المنصة (للعرض والتنبيه)
  ('operating_hours', '{"open": "08:00", "close": "02:00"}'),
  ('support', '{"phone": ""}')
on conflict (key) do nothing;
