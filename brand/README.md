# هوية واصل | WASEL

| العنصر | الملف |
|---|---|
| العلامة (حرف «و» كمسار توصيل) | `svg/mark-*.svg` |
| الشعار العربي | `svg/logo-ar-navy.svg` · `svg/logo-ar-ivory.svg` · `svg/logo-ar-on-navy.svg` |
| الشعار الإنگليزي | `svg/logo-en-navy.svg` · `svg/logo-en-ivory.svg` |
| شاشة البداية | `svg/splash-lockup.svg` |
| أيقونات التطبيقات (1024) | `png/icon-{customer,merchant,admin}-{full,foreground,background}.png` |

كل ملف SVG له نسخة PNG في `png/`.

## الألوان
| الاسم | القيمة | الاستخدام |
|---|---|---|
| Deep Navy | `#172E3B` | النصوص الرئيسية، الخلفيات الداكنة، تطبيق المستهلك |
| Coral | `#F0785B` | الأزرار الرئيسية، العلامة، تطبيق التاجر |
| Warm Ivory | `#F5F1E8` | خلفية التطبيقات |
| Soft Mint | `#A9C8B9` | العناصر الثانوية، حالات النجاح، تطبيق الإدارة |
| White | `#FFFFFF` | البطاقات |

## الخطوط (رخصة SIL OFL 1.1 — مسموح تجارياً)
- الشعار العربي: **Reem Kufi** Bold، محوّل لمسارات (لا يحتاج الخط عند الاستخدام).
- الواجهات والشعار الإنگليزي: **Readex Pro**.

## إعادة التوليد
```
pip install uharfbuzz fonttools
python3 brand/tools/build_brand.py --reem ReemKufi_700Bold.ttf --readex ReadexPro_600SemiBold.ttf
node brand/tools/render_png.js   # يحتاج playwright
```
