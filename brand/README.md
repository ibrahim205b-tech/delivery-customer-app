# هوية واصل | WASEL (الإصدار 6)

## الفكرة
العلامة **شيفرون «<»** بخط سميك مدوّر الأطراف، بلون **برتقالي غامق جداً** `#B23C0B`: سهم الوصول نحو الزبون. الشعار المكتوب **«<واصل»**: الشيفرون يسبق الكلمة بارتفاع الحروف.

| العنصر | الملفات (SVG في `svg/` و PNG في `png/`) |
|---|---|
| العلامة وحدها | `mark-orange` · `mark-ink` · `mark-white` |
| الشعار العربي «<واصل» | `logo-ar-ink` · `logo-ar-white` · `logo-ar-on-ink` · `logo-ar-on-orange` · `logo-ar-on-cream` |
| الشعار الإنگليزي | `logo-en-ink` · `logo-en-white` |
| شاشة البداية | `splash-lockup` |
| أيقونات التطبيقات | `icon-{customer,merchant,admin}-{full,foreground,background}` |

| التطبيق | الخلفية | العلامة |
|---|---|---|
| واصل (الزبون) | كريمي `#FFF8F2` | برتقالي غامق `#B23C0B` |
| واصل شريك (التاجر/السائق) | Lime | Ink |
| إدارة واصل | Blue | White |

## الألوان
| الاسم | القيمة | الاستخدام |
|---|---|---|
| Primary Ink | `#111923` | النص الأساسي، الأسطح الداكنة، أزرار ثانوية |
| Electric Lime | `#D8F36A` | الإجراء الرئيسي، التمييز، الحالة الحالية |
| Warm Paper | `#F4F2EC` | خلفية التطبيقات |
| Electric Blue | `#4058E8` | الروابط، الأسعار، المسارات على الخريطة، معلومات |
| White | `#FFFFFF` | البطاقات |
| Graphite | `#303943` | أسطح داكنة ثانوية |

**قاعدة التباين:** الليموني ما يُستعمل كنص على خلفية فاتحة أبداً (تباينه ضعيف). على الفاتح: نص Ink أو Blue. الليموني يكون تعبئة (زر/شارة) ونصه Ink، أو نصاً على خلفية Ink.

## الخط
**Alexandria** (رخصة SIL OFL 1.1 — مسموح تجارياً) بالأوزان 400/500/600/700، مضمّن محلياً بالتطبيق (`packages/wasel_core/fonts`)، وخط احتياطي **Noto Sans Arabic** للأحرف النادرة.
اختير بعد مقارنة فعلية مع IBM Plex Sans Arabic و Readex Pro و Noto: هندسي ومعاصر، أرقامه واضحة، ويحافظ على وضوحه بالأحجام الصغيرة.

سلّم الطباعة (`WText` في `tokens.dart`): Display · H1 · H2 · H3 · Body · BodyStrong · Small · Caption · Label · Button · Price (أرقام بعرض ثابت) · Number · Overline.

## إعادة التوليد
```
pip install uharfbuzz fonttools
python3 brand/tools/build_brand.py --font Alexandria_700Bold.ttf
NODE_PATH=$(npm root -g) node brand/tools/render_png.js   # يحتاج playwright
```
النصوص بالشعار محوّلة لمسارات، فالملفات ما تحتاج الخط عند الاستخدام.

## هوية تطبيق الزبون (الإصدار 6)
تطبيق الزبون له لوحة ألوان خاصة (`WPalette.customer`)، وتطبيقا التاجر/السائق والإدارة يبقون على الألوان الأصلية (`WPalette.classic`).

| الدور | اللون | الاستخدام |
|---|---|---|
| برتقالي واصل الغامق | `#B23C0B` | الواجهة العلوية، الشريط المختار، الروابط، أيقونة التطبيق |
| أصفر التكسي | `#FFC53D` | الفعل الرئيسي، بطاقة التكسي، الشارات — نصه دائماً بني داكن |
| بني شبه أسود | `#24160E` | النص الأساسي |
| كريمي | `#FFF8F2` | الخلفية |
| مرجاني / نعناعي / فيروزي | `#E8432E` / `#1F9A73` / `#13808A` | ألوان الأقسام والرسومات |

### رسومات الأقسام
`brand/illustrations/*.svg` — رسومات أصلية (تكسي، طعام، ودّي أغراضك، المحلات) بأسلوب موحّد: أشكال مسطحة مدوّرة بلا حدود، 3 درجات لكل جسم، ظل أرضي واحد، بلا نصوص داخل الرسم.
إعادة التوليد:
```
python3 brand/illustrations/build_illustrations.py
NODE_PATH=$(npm root -g) node brand/illustrations/render_illustrations.js   # → apps/customer/assets/illustrations (1x/2x/3x)
```
