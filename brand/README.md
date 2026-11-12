# هوية واصل | WASEL (الإصدار 2)

## الفكرة
العلامة **خط مسار واحد متصل** يتموّج بين نقطتين وينتهي **بحلقة وصول**:
حركة → طريق → وصول. الخط بشكله يقرأ كحرف «w» (WASEL) وكموجة طريق بالمدينة، بلا دبوس خريطة وبلا أسهم.

| العنصر | الملفات (SVG في `svg/` و PNG في `png/`) |
|---|---|
| العلامة وحدها | `mark-ink` · `mark-lime` · `mark-white` |
| الشعار العربي | `logo-ar-ink` (فاتح) · `logo-ar-white` · `logo-ar-on-ink` (داكن) · `logo-ar-on-lime` |
| الشعار الإنگليزي | `logo-en-ink` · `logo-en-white` |
| شاشة البداية | `splash-lockup` |
| أيقونات التطبيقات (1024، أندرويد adaptive) | `icon-{customer,merchant,admin}-{full,foreground,background}` |

كل تطبيق له أيقونة بنفس العلامة وتوزيع ألوان مختلف حتى تتميّز على شاشة الهاتف:

| التطبيق | الخلفية | المسار | الحلقة |
|---|---|---|---|
| واصل (المستهلك) | Ink | Lime | White |
| واصل شريك (التاجر/السائق) | Lime | Ink | Blue |
| إدارة واصل | Blue | White | Lime |

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
