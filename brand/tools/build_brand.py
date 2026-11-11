#!/usr/bin/env python3
"""
مولّد الهوية البصرية لواصل | WASEL
-----------------------------------
- يحوّل كلمة "واصل" و "WASEL" إلى مسارات SVG حقيقية (outlines) من خطوط مرخّصة OFL
  (Reem Kufi للشعار العربي، Readex Pro للإنگليزي) مع تشكيل عربي صحيح عبر HarfBuzz.
- يرسم العلامة: حرف "و" على شكل مسار توصيل يبدأ بحلقة وينتهي بنقطة وصول.
- يكتب ملفات SVG في brand/svg/ ، ثم يحوّلها PNG عبر Chromium (render_png.js).

الاستخدام:
  python3 brand/tools/build_brand.py --reem <ReemKufi_700Bold.ttf> --readex <ReadexPro_600SemiBold.ttf>
"""
import argparse
import pathlib

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

NAVY = "#172E3B"
CORAL = "#F0785B"
IVORY = "#F5F1E8"
MINT = "#A9C8B9"
WHITE = "#FFFFFF"

OUT = pathlib.Path(__file__).resolve().parent.parent / "svg"


def text_path(font_path: str, text: str, size: float, rtl: bool, tracking: float = 0.0):
    """يرجّع (d, width, ascent, descent) لنص مشكّل كمسار SVG بإحداثيات y للأسفل."""
    blob = hb.Blob.from_file_path(font_path)
    face = hb.Face(blob)
    font = hb.Font(face)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    if rtl:
        buf.direction = "rtl"
    hb.shape(font, buf, {"kern": True, "liga": True})

    tt = TTFont(font_path)
    upem = tt["head"].unitsPerEm
    scale = size / upem
    glyph_set = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    pen = SVGPathPen(glyph_set)

    x = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        name = order[info.codepoint]
        # y يتقلب لأن SVG محوره للأسفل
        t = (scale, 0, 0, -scale, (x + pos.x_offset) * scale, -pos.y_offset * scale)
        glyph_set[name].draw(TransformPen(pen, t))
        x += pos.x_advance + tracking * upem
    x -= tracking * upem
    hhea = tt["hhea"]
    return pen.getCommands(), x * scale, hhea.ascent * scale, -hhea.descent * scale


def mark_paths(stroke: str, dot: str, ring_fill: str | None = None, sw: float = 11.0) -> str:
    """
    العلامة داخل مربع 100×100: حلقة (نقطة الانطلاق) + ذيل الواو كمسار + نقطة الوصول.
    """
    fill_ring = f'<circle cx="60" cy="34" r="9" fill="{ring_fill}"/>' if ring_fill else ""
    return (
        f'<circle cx="60" cy="34" r="15" fill="none" stroke="{stroke}" stroke-width="{sw}"/>'
        f"{fill_ring}"
        f'<path d="M75 34 C75 58 62 78 32 81" fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round"/>'
        f'<circle cx="21" cy="81.5" r="6.5" fill="{dot}"/>'
    )


def svg(w: float, h: float, body: str, bg: str | None = None, rx: float = 0) -> str:
    rect = f'<rect width="{w:g}" height="{h:g}" rx="{rx:g}" fill="{bg}"/>' if bg else ""
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:g} {h:g}" width="{w:g}" height="{h:g}">'
        f"{rect}{body}</svg>\n"
    )


def write(name: str, content: str):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(content, encoding="utf-8")
    print("wrote", OUT / name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--reem", required=True)
    ap.add_argument("--readex", required=True)
    a = ap.parse_args()

    ar_d, ar_w, ar_asc, ar_desc = text_path(a.reem, "واصل", 120, rtl=True)
    en_d, en_w, en_asc, en_desc = text_path(a.readex, "WASEL", 40, rtl=False, tracking=0.18)

    # ---- العلامة وحدها ----
    write("mark-coral.svg", svg(100, 100, mark_paths(CORAL, MINT)))
    write("mark-navy.svg", svg(100, 100, mark_paths(NAVY, CORAL)))
    write("mark-ivory.svg", svg(100, 100, mark_paths(IVORY, CORAL)))

    # ---- الشعار العربي: العلامة + واصل ----
    def lockup_ar(text_color, mark_stroke, mark_dot, bg=None):
        pad = 24
        mark_size = 120
        gap = 22
        h = max(ar_asc + ar_desc, mark_size) + pad * 2
        w = pad + ar_w + gap + mark_size + pad
        base = pad + ar_asc + (h - pad * 2 - (ar_asc + ar_desc)) / 2
        body = (
            # RTL: العلامة يمين، الكلمة يسارها
            f'<g transform="translate({pad + ar_w + gap},{(h - mark_size) / 2}) scale({mark_size / 100})">'
            f"{mark_paths(mark_stroke, mark_dot)}</g>"
            f'<path transform="translate({pad},{base})" d="{ar_d}" fill="{text_color}"/>'
        )
        return svg(round(w), round(h), body, bg, rx=28 if bg else 0)

    write("logo-ar-navy.svg", lockup_ar(NAVY, CORAL, NAVY))
    write("logo-ar-ivory.svg", lockup_ar(IVORY, CORAL, MINT))
    write("logo-ar-on-navy.svg", lockup_ar(IVORY, CORAL, MINT, bg=NAVY))

    # ---- الشعار الإنگليزي ----
    def lockup_en(text_color, mark_stroke, mark_dot):
        pad = 16
        mark_size = 56
        gap = 14
        h = mark_size + pad * 2
        w = pad + mark_size + gap + en_w + pad
        base = h / 2 + (en_asc - en_desc) / 2 - 4
        body = (
            f'<g transform="translate({pad},{pad}) scale({mark_size / 100})">{mark_paths(mark_stroke, mark_dot)}</g>'
            f'<path transform="translate({pad + mark_size + gap},{base})" d="{en_d}" fill="{text_color}"/>'
        )
        return svg(round(w), round(h), body)

    write("logo-en-navy.svg", lockup_en(NAVY, CORAL, NAVY))
    write("logo-en-ivory.svg", lockup_en(IVORY, CORAL, MINT))

    # ---- الشعار المزدوج (عربي فوق إنگليزي) للـ Splash ----
    pad = 40
    mark_size = 150
    w = max(ar_w, en_w, mark_size) + pad * 2
    y_mark = pad
    y_ar = y_mark + mark_size + 26 + ar_asc
    y_en = y_ar + ar_desc + 8 + en_asc
    h = y_en + en_desc + pad
    body = (
        f'<g transform="translate({(w - mark_size) / 2},{y_mark}) scale({mark_size / 100})">{mark_paths(CORAL, MINT)}</g>'
        f'<path transform="translate({(w - ar_w) / 2},{y_ar})" d="{ar_d}" fill="{IVORY}"/>'
        f'<path transform="translate({(w - en_w) / 2},{y_en})" d="{en_d}" fill="{MINT}"/>'
    )
    write("splash-lockup.svg", svg(round(w), round(h), body))

    # ---- أيقونات التطبيقات (1024) ----
    # كامل (للأجهزة القديمة) + طبقة أمامية للأيقونة المتكيّفة (المنطقة الآمنة 66%)
    apps = {
        # التطبيق: (الخلفية، لون العلامة، لون النقطة، شارة)
        "customer": (NAVY, CORAL, MINT, None),
        "merchant": (CORAL, NAVY, IVORY, None),
        "admin": (MINT, NAVY, CORAL, None),
    }
    for app, (bg, stroke, dot, badge) in apps.items():
        def icon_body(scale_pct):
            s = 1024 * scale_pct / 100
            off = (1024 - s) / 2
            b = f'<g transform="translate({off},{off}) scale({s / 100})">{mark_paths(stroke, dot)}</g>'
            if badge:
                # شارة صغيرة تميّز تطبيق الإدارة
                b += f'<rect x="{off + s * 0.62}" y="{off + s * 0.70}" width="{s * 0.30}" height="{s * 0.13}" rx="{s * 0.065}" fill="{badge}"/>'
            return b

        write(f"icon-{app}-full.svg", svg(1024, 1024, icon_body(62), bg))
        write(f"icon-{app}-foreground.svg", svg(1024, 1024, icon_body(46)))
        write(f"icon-{app}-background.svg", svg(1024, 1024, "", bg))


if __name__ == "__main__":
    main()
