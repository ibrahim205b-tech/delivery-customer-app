-- =====================================================================
-- WASEL | عروض حقيقية على المنتجات (0018)
-- compare_at_price: السعر قبل الخصم (اختياري). المنتج يُعتبر "عرضاً" فقط إذا
-- كان هذا السعر أكبر من السعر الحالي. صاحب المطعم يحدده من شاشة المنتج.
-- التأثير: عمود إضافي فقط، لا يغيّر أي بيانات موجودة.
-- =====================================================================
alter table products add column if not exists compare_at_price int;
alter table products drop constraint if exists products_compare_at_price_check;
alter table products add constraint products_compare_at_price_check
  check (compare_at_price is null or compare_at_price > 0);
create index if not exists products_offers_idx on products (merchant_id) where compare_at_price is not null;
notify pgrst, 'reload schema';
