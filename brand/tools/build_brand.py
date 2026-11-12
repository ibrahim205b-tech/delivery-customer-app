#!/usr/bin/env python3
"""
مولّد الهوية البصرية لواصل | WASEL — الإصدار الثاني (Bold Contemporary)
--------------------------------------------------------------------------
العلامة: مسار متصل على شكل موجة (W) يبدأ من نقطة وينتهي بحلقة وصول.
الفكرة: الحركة + المسار + لحظة الوصول. بدون دبوس خرائط وبدون أسهم.

الخط: Alexandria (SIL OFL) للعربي والإنگليزي، محوّل لمسارات SVG عبر HarfBuzz.

الاستخدام:
  pip install uharfbuzz fonttools
  python3 brand/tools/build_brand.py --font Alexandria_700Bold.ttf
  node brand/tools/render_png.js
"""
import argparse
import pathlib
import shutil

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

INK = "#111923"
LIME = "#D8F36A"
PAPER = "#F4F2EC"
BLUE = "#4058E8"
WHITE = "#FFFFFF"
GRAPHITE = "#303943"

OUT = pathlib.Path(__file__).resolve().parent.parent / "svg"

# مسار العلامة داخل مربع 100×100 (نفسه مستخدم بالكود: WaselMark في wasel_core)
# الإصدار 3: نفس الـW كمسار، والطرف الأخير يلف على نفسه ويصير هو حلقة الوصول (خط واحد متصل، لون واحد).
# القوس: مركز (75.5, 34.5) نصف قطر 13، من 30° يلف عكس عقارب الساعة 240° — يترك فتحة حتى ما يلمس الخط الصاعد.
ROUTE = ("M11.5 38.5 C17.5 60.5 21.5 78.5 29.5 78.5 C37.5 78.5 40.5 55.5 47.5 55.5 "
         "C54.5 55.5 57.5 78.5 65.5 78.5 C73.5 78.5 80.76 51.39 86.76 41 A13 13 0 1 0 64.24 41")


def text_path(font_path, text, size, rtl, tracking=0.0):
    blob = hb.Blob.from_file_path(font_path)
    font = hb.Font(hb.Face(blob))
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    if rtl:
        buf.direction = "rtl"
    hb.shape(font, buf, {"kern": True, "liga": True})
    tt = TTFont(font_path)
    upem = tt["head"].unitsPerEm
    scale = size / upem
    gs = tt.getGlyphSet()
    order = tt.getGlyphOrder()
    pen = SVGPathPen(gs)
    x = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        t = (scale, 0, 0, -scale, (x + pos.x_offset) * scale, -pos.y_offset * scale)
        gs[order[info.codepoint]].draw(TransformPen(pen, t))
        x += pos.x_advance + tracking * upem
    x -= tracking * upem
    # حدود فعلية للحروف (أدق من ascent/descent للتوسيط)
    from fontTools.pens.boundsPen import BoundsPen
    bp = BoundsPen(gs)
    x2 = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        t = (scale, 0, 0, -scale, (x2 + pos.x_offset) * scale, -pos.y_offset * scale)
        gs[order[info.codepoint]].draw(TransformPen(bp, t))
        x2 += pos.x_advance + tracking * upem
    xmin, ymin, xmax, ymax = bp.bounds
    return pen.getCommands(), (xmin, ymin, xmax, ymax)


def mark(route, ring=None, sw=12.5):
    # ring محفوظ للتوافق؛ العلامة الآن خط واحد بلون واحد
    return f'<path d="{ROUTE}" fill="none" stroke="{route}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round"/>'



def svg(w, h, body, bg=None, rx=0):
    rect = f'<rect width="{w:g}" height="{h:g}" rx="{rx:g}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:g} {h:g}" width="{w:g}" height="{h:g}">{rect}{body}</svg>\n'


def write(name, content):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(content, encoding="utf-8")
    print("wrote", name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--font", required=True, help="Alexandria Bold TTF")
    a = ap.parse_args()

    if OUT.exists():
        shutil.rmtree(OUT)

    ar_d, (axmin, aymin, axmax, aymax) = text_path(a.font, "واصل", 120, rtl=True)
    en_d, (exmin, eymin, exmax, eymax) = text_path(a.font, "WASEL", 44, rtl=False, tracking=0.08)
    ar_w, ar_h = axmax - axmin, aymax - aymin
    en_w, en_h = exmax - exmin, eymax - eymin

    # ---- العلامة ----
    write("mark-ink.svg", svg(100, 100, mark(INK, BLUE)))
    write("mark-lime.svg", svg(100, 100, mark(LIME, WHITE)))
    write("mark-white.svg", svg(100, 100, mark(WHITE, LIME)))

    def place_text(d, xmin, ymin, x, y):
        # يضع النص بحيث تبدأ حدوده الفعلية عند (x, y)
        return f'<path transform="translate({x - xmin:.2f},{y - ymin:.2f})" d="{d}"'

    # ---- الشعار العربي الأفقي: [واصل][العلامة] ----
    def lockup_ar(text_c, route_c, ring_c, bg=None):
        pad, ms, gap = 28, 128, 26
        h = max(ar_h, ms) + pad * 2
        w = pad + ar_w + gap + ms + pad
        body = (
            f'<g transform="translate({pad + ar_w + gap},{(h - ms) / 2}) scale({ms / 100})">{mark(route_c, ring_c)}</g>'
            + place_text(ar_d, axmin, aymin, pad, (h - ar_h) / 2) + f' fill="{text_c}"/>'
        )
        return svg(round(w), round(h), body, bg, rx=32 if bg else 0)

    write("logo-ar-ink.svg", lockup_ar(INK, INK, BLUE))
    write("logo-ar-white.svg", lockup_ar(WHITE, LIME, WHITE))
    write("logo-ar-on-ink.svg", lockup_ar(WHITE, LIME, WHITE, bg=INK))
    write("logo-ar-on-lime.svg", lockup_ar(INK, INK, BLUE, bg=LIME))

    # ---- الشعار الإنگليزي: [العلامة][WASEL] ----
    def lockup_en(text_c, route_c, ring_c, bg=None):
        pad, ms, gap = 20, 64, 16
        h = ms + pad * 2
        w = pad + ms + gap + en_w + pad
        body = (
            f'<g transform="translate({pad},{pad}) scale({ms / 100})">{mark(route_c, ring_c)}</g>'
            + place_text(en_d, exmin, eymin, pad + ms + gap, (h - en_h) / 2) + f' fill="{text_c}"/>'
        )
        return svg(round(w), round(h), body, bg, rx=24 if bg else 0)

    write("logo-en-ink.svg", lockup_en(INK, INK, BLUE))
    write("logo-en-white.svg", lockup_en(WHITE, LIME, WHITE))

    # ---- شاشة البداية: علامة كبيرة + واصل + WASEL ----
    pad, ms = 40, 150
    w = max(ar_w, en_w, ms) + pad * 2
    y_ar = pad + ms + 30
    y_en = y_ar + ar_h + 22
    h = y_en + en_h + pad
    body = (
        f'<g transform="translate({(w - ms) / 2},{pad}) scale({ms / 100})">{mark(LIME, WHITE)}</g>'
        + place_text(ar_d, axmin, aymin, (w - ar_w) / 2, y_ar) + f' fill="{WHITE}"/>'
        + place_text(en_d, exmin, eymin, (w - en_w) / 2, y_en) + f' fill="{LIME}" fill-opacity="0.8"/>'
    )
    write("splash-lockup.svg", svg(round(w), round(h), body))

    # ---- أيقونات التطبيقات (1024): كاملة + طبقة أمامية للأيقونة المتكيّفة ----
    apps = {
        "customer": (INK, LIME, WHITE),   # الأساسي: حبر + ليموني
        "merchant": (LIME, INK, BLUE),    # التاجر: ليموني + حبر
        "admin": (BLUE, WHITE, LIME),     # الإدارة: أزرق + أبيض
    }
    for app, (bg, route_c, ring_c) in apps.items():
        def body(pct):
            s = 1024 * pct / 100
            off = (1024 - s) / 2
            return f'<g transform="translate({off},{off}) scale({s / 100})">{mark(route_c, ring_c)}</g>'
        write(f"icon-{app}-full.svg", svg(1024, 1024, body(64), bg))
        write(f"icon-{app}-foreground.svg", svg(1024, 1024, body(48)))
        write(f"icon-{app}-background.svg", svg(1024, 1024, "", bg))


if __name__ == "__main__":
    main()
