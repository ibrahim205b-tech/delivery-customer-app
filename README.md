<div dir="rtl">

# واصل | WASEL

**كل احتياجاتك أقرب.** منصة عراقية للخدمات المحلية والتوصيل: ثلاثة تطبيقات Android متصلة بقاعدة بيانات مركزية واحدة.

| التطبيق | الحزمة | لمن |
|---|---|---|
| `wasel-customer.apk` | `iq.wasel.customer` | المستهلك: محلات، سلة، تتبع لحظي، تكسي/تكتك، مندوب، توصيل أغراض، خدمات منزلية |
| `wasel-merchant.apk` | `iq.wasel.merchant` | التجار ومقدّمو الخدمات، **وواجهة منفصلة** للسائقين والمندوبين |
| `wasel-admin.apk` | `iq.wasel.admin` | الإدارة المركزية |

آخر الملفات الجاهزة: تبويب **Releases** بالمستودع.

---

## البنية

```
supabase/
  migrations/      ← قاعدة البيانات: الجداول، الدوال، الحماية (RLS)، التخزين، البيانات الأساسية
  tests/           ← 60 فحص لدورة العمل والصلاحيات على PostgreSQL محلي
  local/           ← تشغيل Supabase كامل محلياً للاختبار (Auth + REST + Realtime + Storage)
packages/wasel_core/  ← مكتبة مشتركة: نظام التصميم، النماذج، خدمات Supabase، الخرائط
apps/customer | merchant | admin  ← التطبيقات الثلاثة (Flutter)
brand/             ← الشعار والأيقونات (SVG + PNG) وأدوات توليدها
.github/workflows/build.yml  ← يبني الـ APKs ويختبر وينشرها
```

**التقنيات:** Flutter 3.50 · Supabase (PostgreSQL + Auth + Realtime + Storage) · OpenStreetMap عبر flutter_map.

**مبدأ الحماية:** كل العمليات الحساسة (إنشاء الطلب، الأسعار، الأجرة، تغيير الحالات، قبول المهام) تتم بدوال على الخادم. التطبيق ما يگدر يغيّر سعر أو حالة مباشرة. **Row Level Security** مفعّلة على كل جدول: كل مستخدم يشوف بياناته فقط، والتاجر يشوف محله، والسائق يشوف مهام نوع مركبته ومهامه فقط، والإدارة تشوف كلشي.

---

## التشغيل خطوة بخطوة

### 1) إنشاء مشروع Supabase (مجاني)
1. سجّل في [supabase.com](https://supabase.com) ← **New project**.
2. المنطقة المقترحة: **Frankfurt (eu-central-1)** (الأقرب للعراق).
3. احفظ كلمة مرور قاعدة البيانات بمكان آمن.

### 2) إعداد تسجيل الدخول
**Authentication ← Sign In / Providers ← Email:**
- خليه **مفعّل**.
- **أطفِ "Confirm email"** (التطبيقات تستخدم رقم الهاتف + كلمة مرور، وداخلياً يتحول الرقم لبريد ثابت ما تنرسل له رسائل).

### 3) إنشاء قاعدة البيانات
**SQL Editor** ← شغّل الملفات بالترتيب، كل ملف مرة وحدة:
```
supabase/migrations/0001_schema.sql
supabase/migrations/0002_functions.sql
supabase/migrations/0003_security.sql
supabase/migrations/0004_storage.sql
supabase/migrations/0005_seed.sql
supabase/migrations/0006_admin_reports.sql
```
> إذا شغّلت `setup_all.sql` قبل التحديث البصري، شغّل الآن **فقط** `0006_admin_reports.sql` (تقارير لوحة الإدارة).
أو بالـ CLI: `supabase link --project-ref <ref>` ثم `supabase db push`.

تأكد من **Database ← Publications ← supabase_realtime** إنه يحتوي: `orders, delivery_tasks, rides, service_bookings, notifications, merchants, products` (الملف 0003 يضيفهم).

### 4) ربط التطبيقات بالخادم (GitHub Secrets)
من Supabase: **Project Settings ← API Keys** انسخ:
- **Project URL** (بالشكل `https://<project-id>.supabase.co`)
- **Publishable key** (يبدأ بـ `sb_publishable_`)

بالمستودع: **Settings ← Secrets and variables ← Actions ← New repository secret**:

| الاسم | القيمة |
|---|---|
| `SUPABASE_URL` | Project URL |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable key (`sb_publishable_...`) |
| `WASEL_KEYSTORE_BASE64` *(اختياري، مستحسن)* | مفتاح التوقيع بصيغة base64 |
| `WASEL_KEYSTORE_PASSWORD` *(اختياري)* | كلمة مرور المفتاح |

المفتاح العام آمن داخل التطبيق (الحماية الفعلية بـ RLS)، لكنه ما ينحفظ بالكود. مفتاح anon القديم يشتغل أيضاً كـ `SUPABASE_ANON_KEY` لكن Supabase راح يوقفه بداية 2027. **لا تضع أبداً المفتاح السري (`sb_secret_` / `service_role`) بأي تطبيق أو Secret للبناء.**

**مفتاح التوقيع** (حتى تنثبّت التحديثات فوق النسخة القديمة بدون حذف):
```bash
keytool -genkey -v -keystore wasel.jks -alias wasel -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 wasel.jks   # الناتج ← WASEL_KEYSTORE_BASE64
```
احتفظ بـ `wasel.jks` بمكان آمن: إذا ضاع ما تگدر تحدّث التطبيقات المثبتة.

### 5) بناء الـ APKs
**Actions ← Build Wasel APKs ← Run workflow** (أو أي دفع للفرع `main`).
بعد النجاح تظهر الملفات الثلاثة في **Releases** (`build-<رقم>`).

> بدون `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` التطبيق يفتح على شاشة "التطبيق غير مربوط بالخادم".

### 6) التثبيت
حمّل الـ APK على الموبايل ← افتحه ← اسمح بـ "التثبيت من مصادر غير معروفة".

---

## أول تشغيل: المدير، أول محل، أول سائق

### المدير الأول
1. سجّل حساب برقمك من تطبيق **واصل** (المستهلك) أو **واصل للأعمال**.
2. بـ **SQL Editor**:
```sql
insert into user_roles (user_id, role)
select id, 'admin' from users where phone = '07XXXXXXXXX';
```
3. افتح **إدارة واصل** وسجّل دخول بنفس الرقم. المدراء اللاحقون تمنحهم من التطبيق (المزيد ← المستخدمون).

### أول منطقة ومحل
1. **إدارة واصل ← المزيد ← المناطق ← +**: الاسم، المدينة، مركز المنطقة على الخريطة، نصف القطر.
2. صاحب المحل يسجّل برقمه بتطبيق **واصل للأعمال** (يشوف "حسابك بانتظار الربط").
3. **المحلات ← إضافة محل**: الاسم، التصنيف، المنطقة، الموقع على الخريطة، أجرة التوصيل، أقل طلب، نطاق التوصيل ← **إضافة المحل**.
4. بنفس الشاشة: **حساب التاجر** ← اكتب رقمه ← **ربط**. ارفع الشعار والغلاف.
5. التاجر يضيف منتجاته (الاسم، السعر، صورة من الكاميرا).
6. الإدارة تغيّر الحالة إلى **معتمد** ← يظهر المحل للزبائن فوراً.

مقدّم خدمة منزلية: نفس الخطوات مع التصنيف **الأعمال المنزلية** واختيار الخدمات اللي يقدّمها.

### أول سائق / مندوب
1. السائق يسجّل برقمه بتطبيق **واصل للأعمال**.
2. **إدارة واصل ← السائقون ← إضافة سائق**: رقمه، النوع (مندوب / تكسي / تكتك)، المركبة واللوحة.
3. السائق يفتح التطبيق ← يشغّل **متاح** ← تظهر له المهام المناسبة لنوع مركبته.

### حسابات الاختبار
ما اكو كلمات مرور منشورة بالمستودع. للتجربة سوّي 4 حسابات بأرقام مختلفة (مستهلك، تاجر، سائق، مدير) واتبع الخطوات أعلاه.

---

## دورة الطلب

```
المستهلك يرسل ← placed (تم إرسال الطلب)
المحل يقبل   ← accepted          (أو يرفض مع سبب ← cancelled)
المحل يجهّز  ← preparing
المحل يجهز   ← ready             ← تنشأ مهمة توصيل للمندوبين المتاحين
المندوب يقبل ← (يظهر اسمه وموقعه للزبون لحظياً)
المندوب      ← picked_up ← on_the_way ← delivered
```
الزبون يلغي فقط قبل موافقة المحل. الإدارة تلغي أي طلب عالق. كل تغيير ينحفظ بسجل `order_status_history` ويولّد إشعار.

---

## الاختبارات

| الاختبار | الأمر | ماذا يغطي |
|---|---|---|
| قاعدة البيانات | `bash supabase/tests/run.sh` | 60 فحص: دورة الطلب، الرحلات، المهام، الخدمات، التخزين، الصلاحيات، تعطيل الحسابات |
| الوحدة | `cd packages/wasel_core && flutter test test/core_test.dart` | الأرقام العراقية، التنسيق، النماذج، أوقات العمل، ترجمة الأخطاء |
| التكامل | انظر أدناه | 9 سيناريوهات بكود التطبيقات نفسه ضد Supabase حقيقي، تشمل التحديث اللحظي |

**اختبار التكامل محلياً** (يحتاج Docker + PostgreSQL 16 + `postgresql-16-wal2json`):
```bash
bash supabase/local/up.sh        # يطبع SUPABASE_URL و المفاتيح
cd packages/wasel_core
WASEL_IT_URL=http://localhost:54321 WASEL_IT_ANON=<anon> WASEL_IT_SERVICE=<service> \
  flutter test test/integration_test.dart
```

---

## حدود النسخة الحالية (MVP)

- **الدفع نقداً فقط.** لا محفظة ولا بطاقات ولا شحن رصيد.
- **العمولات معطّلة** ولا تُحتسب (إعداد محفوظ للمستقبل فقط).
- **الإشعارات داخل التطبيق** (لحظية + صوت) عندما يكون التطبيق مفتوحاً. إشعارات Push والتطبيق مسكّر تحتاج Firebase (المرحلة الجاية).
- **موقع السائق** يتحدّث كل 15 ثانية والتطبيق مفتوح فقط.
- **التسعير** يعتمد مسافة خط مستقيم (Haversine) بالخادم. الخرائط تعرض مسار الطريق الفعلي من خدمة التوجيه، وإذا فشلت يظهر خط منقّط مع كلمة «تقريباً».
- **التحقق من الرقم** بكلمة مرور بدون SMS (حتى نتجنب كلفة مزوّد الرسائل).
- **الخرائط** تستخدم افتراضياً خدمات مجانية عامة: OpenStreetMap (الصور)، Nominatim (البحث عن العناوين)، OSRM (المسارات). هذه الخدمات لها حدود استخدام ومناسبة للتجربة فقط.

### تغيير مزوّد الخرائط (بدون تعديل كود)
عند البناء أضف أي من هذه القيم (`--dart-define` أو GitHub Secrets بنفس الاسم):

| المتغير | الافتراضي | مثال مدفوع |
|---|---|---|
| `MAP_TILE_URL` | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | MapTiler: `https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=KEY` |
| `MAP_TILE_ATTRIBUTION` | `© OpenStreetMap` | `© MapTiler © OpenStreetMap` |
| `GEOCODER_URL` | `https://nominatim.openstreetmap.org` | خادم Nominatim خاص |
| `ROUTER_URL` | `https://router.project-osrm.org` | خادم OSRM خاص |

> لم يُفعَّل أي مزوّد مدفوع. التفعيل يحتاج موافقتك ومفتاح من حسابك.

## التكلفة المتوقعة للتجربة

| الخدمة | المجاني | عند التوسع |
|---|---|---|
| Supabase | باقة Free: قاعدة 500MB، تخزين 1GB، 50 ألف مستخدم نشط شهرياً (المشروع يتوقف بعد أسبوع بدون استخدام) | Pro بحدود 25$ شهرياً |
| GitHub Actions | مجاني للمستودعات العامة، 2000 دقيقة شهرياً للخاصة | — |
| الخرائط | OSM مجاني ضمن الاستخدام المعقول | MapTiler أو مشابه حسب الاستخدام |
| Google Play (إذا تنشر) | — | 25$ مرة وحدة |

---

الخطوط: Alexandria و Noto Sans Arabic برخصة SIL Open Font License (مسموحة تجارياً). تفاصيل الهوية في [`brand/README.md`](brand/README.md).

</div>
