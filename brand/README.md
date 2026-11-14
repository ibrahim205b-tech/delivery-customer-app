# هوية واصل | WASEL (الإصدار 7)

## الشعار
كلمة **«واصل»** بخط عريض مائل قليلاً، يمينها **شيفرون برتقالي «>»** بأطراف مقطوعة، وتحتها **WASEL** بحروف متباعدة.
الألوان: كحلي `#003060` · برتقالي `#FD5A17` · أبيض.

| العنصر | الملفات (SVG في `svg/` و PNG في `png/`) |
|---|---|
| العلامة وحدها (الشيفرون) | `mark-orange` · `mark-navy` · `mark-white` |
| الكلمة + الشيفرون | `logo-ar-ink` (على فاتح) · `logo-ar-white` (على داكن) · `logo-ar-on-navy` · `logo-ar-on-orange` |
| الشعار الكامل مع WASEL | `logo-full-ink` · `logo-full-white` · `logo-full-on-navy` · `splash-lockup` |
| أيقونات التطبيقات | `icon-{customer,merchant,admin}-{full,foreground,background}` |

| التطبيق | الأيقونة |
|---|---|
| واصل (الزبون) | كحلي + «واصل» أبيض + شيفرون برتقالي |
| واصل شريك (التاجر/السائق) | Lime + شيفرون Ink |
| إدارة واصل | Blue + شيفرون أبيض |

الخطوط بمجلد `brand/fonts` (SIL OFL): Alexandria ExtraBold للعربي، Montserrat ExtraBold Italic للإنگليزي.

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
python3 brand/tools/build_brand.py
NODE_PATH=$(npm root -g) node brand/tools/render_png.js   # يحتاج playwright
```
النصوص بالشعار محوّلة لمسارات، فالملفات ما تحتاج الخط عند الاستخدام.

## هوية تطبيق الزبون (الإصدار 7)
تطبيق الزبون له لوحة ألوان خاصة (`WPalette.customer`)، وتطبيقا التاجر/السائق والإدارة يبقون على الألوان الأصلية (`WPalette.classic`).

| الدور | اللون | الاستخدام |
|---|---|---|
| كحلي واصل | `#003060` | الواجهة العلوية، الشريط المختار، الروابط، أيقونة التطبيق |
| برتقالي واصل | `#FD5A17` | الفعل الرئيسي (الأزرار)، بطاقة التكسي، الشارات — نصه كحلي داكن |
| كحلي شبه أسود | `#0B1B33` | النص الأساسي |
| أبيض مزرق | `#F5F7FB` | الخلفية |

### رسومات الأقسام
`brand/illustrations/*.svg` — رسومات أصلية (تكسي، طعام، ودّي أغراضك، المحلات) بأسلوب موحّد: أشكال مسطحة مدوّرة بلا حدود، 3 درجات لكل جسم، ظل أرضي واحد، بلا نصوص داخل الرسم.
إعادة التوليد:
```
python3 brand/illustrations/build_illustrations.py
NODE_PATH=$(npm root -g) node brand/illustrations/render_illustrations.js   # → apps/customer/assets/illustrations (1x/2x/3x)
```
