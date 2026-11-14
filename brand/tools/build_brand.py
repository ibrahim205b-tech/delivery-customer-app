#!/usr/bin/env python3
"""
مولّد الهوية البصرية لواصل | WASEL — الإصدار 7
------------------------------------------------
الشعار: كلمة «واصل» بخط عريض مائل قليلاً + شيفرون برتقالي «>» يمين الكلمة، وتحتها WASEL بحروف متباعدة.
الألوان: كحلي #003060 · برتقالي #FD5A17 · أبيض.

الخطوط (SIL OFL، بمجلد brand/fonts): Alexandria ExtraBold للعربي، Montserrat ExtraBold Italic للإنگليزي.
تتحوّل لمسارات SVG عبر HarfBuzz، فالملفات الناتجة ما تحتاج الخط.

الاستخدام:
  pip install uharfbuzz fonttools
  python3 brand/tools/build_brand.py
  NODE_PATH=$(npm root -g) node brand/tools/render_png.js
"""
import math
import pathlib
import shutil

import uharfbuzz as hb
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "svg"
AR_FONT = ROOT / "fonts" / "Alexandria-ExtraBold.ttf"
EN_FONT = ROOT / "fonts" / "Montserrat-ExtraBoldItalic.ttf"

NAVY = "#003060"
ORANGE = "#FD5A17"
WHITE = "#FFFFFF"
INK = "#17191B"
LIME = "#C7F464"
BLUE = "#3979E8"

# العلامة: شيفرون ">" عريض، أطرافه مقطوعة ورأسه مدوّر قليلاً — داخل مربع 100×100
# (نفس الهندسة بالكود: _MarkPainter في wasel_core)
CHEVRON = "M30 14 L70 50 L30 86"
CHEVRON_SW = 24
SLANT = math.tan(math.radians(7))  # ميلان الكلمة العربية


def text_path(font_path, text, size, rtl, tracking=0.0, slant=0.0):
    blob = hb.Blob.from_file_path(str(font_path))
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
        t = (scale, 0, slant * scale, -scale, (x + pos.x_offset) * scale, -pos.y_offset * scale)
        gs[order[info.codepoint]].draw(TransformPen(pen, t))
        x += pos.x_advance + tracking * upem
    x -= tracking * upem
    # حدود فعلية للحروف (أدق من ascent/descent للتوسيط)
    from fontTools.pens.boundsPen import BoundsPen
    bp = BoundsPen(gs)
    x2 = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        t = (scale, 0, slant * scale, -scale, (x2 + pos.x_offset) * scale, -pos.y_offset * scale)
        gs[order[info.codepoint]].draw(TransformPen(bp, t))
        x2 += pos.x_advance + tracking * upem
    xmin, ymin, xmax, ymax = bp.bounds
    return pen.getCommands(), (xmin, ymin, xmax, ymax)


def mark(color, ring=None, sw=CHEVRON_SW):
    # ring محفوظ للتوافق مع الاستدعاءات القديمة
    return f'<path d="{CHEVRON}" fill="none" stroke="{color}" stroke-width="{sw}" stroke-linecap="butt" stroke-linejoin="round"/>'


def svg(w, h, body, bg=None, rx=0):
    rect = f'<rect width="{w:g}" height="{h:g}" rx="{rx:g}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:g} {h:g}" width="{w:g}" height="{h:g}">{rect}{body}</svg>\n'


def write(name, content):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(content, encoding="utf-8")
    print("wrote", name)


def main():
    if OUT.exists():
        shutil.rmtree(OUT)

    ar_d, (axmin, aymin, axmax, aymax) = text_path(AR_FONT, "واصل", 120, rtl=True, slant=SLANT)
    en_d, (exmin, eymin, exmax, eymax) = text_path(EN_FONT, "WASEL", 38, rtl=False, tracking=0.42)
    ar_w, ar_h = axmax - axmin, aymax - aymin
    en_w, en_h = exmax - exmin, eymax - eymin

    def place(d, xmin, ymin, x, y, fill, extra=""):
        return f'<path transform="translate({x - xmin:.2f},{y - ymin:.2f})" d="{d}" fill="{fill}"{extra}/>'

    # الشيفرون بالشعار: ارتفاعه المرئي ≈ 80% من ارتفاع الكلمة، يبدأ فوق رأس الألف بقليل
    ms = ar_h * 0.80 / 0.86          # 86% من مربع العلامة مرئي
    ch_x0, ch_x1 = 0.20 * ms, 0.80 * ms  # الحدود الأفقية المرئية تقريباً
    gap = ar_h * 0.07

    def word_group(x, y, text_c, chev_c):
        """الكلمة + الشيفرون، تبدأ حدودهم من (x, y). يرجع (svg, w, h)."""
        cy = y - ar_h * 0.06 - 0.07 * ms
        cx = x + ar_w + gap - ch_x0
        body = place(ar_d, axmin, aymin, x, y, text_c)
        body += f'<g transform="translate({cx:.2f},{cy:.2f}) scale({ms / 100:.4f})">{mark(chev_c)}</g>'
        return body, ar_w + gap + (ch_x1 - ch_x0), ar_h

    def lockup(text_c, chev_c, en_c=None, bg=None, pad=30):
        wg_w = ar_w + gap + (ch_x1 - ch_x0)
        top = pad + ar_h * 0.06
        h = top + ar_h + pad
        if en_c:
            en_gap = ar_h * 0.10
            h += en_gap + en_h
        w = wg_w + pad * 2
        body, _, _ = word_group(pad, top, text_c, chev_c)
        if en_c:
            # WASEL في منتصف الكلمة العربية
            body += place(en_d, exmin, eymin, pad + (ar_w - en_w) / 2, top + ar_h + en_gap, en_c)
        return svg(round(w), round(h), body, bg, rx=32 if bg else 0)

    # ---- العلامة وحدها ----
    write("mark-orange.svg", svg(100, 100, mark(ORANGE)))
    write("mark-navy.svg", svg(100, 100, mark(NAVY)))
    write("mark-white.svg", svg(100, 100, mark(WHITE)))

    # ---- الشعار: الكلمة + الشيفرون ----
    write("logo-ar-ink.svg", lockup(NAVY, ORANGE))          # على خلفية فاتحة
    write("logo-ar-white.svg", lockup(WHITE, ORANGE))       # على خلفية داكنة
    write("logo-ar-on-navy.svg", lockup(WHITE, ORANGE, bg=NAVY))
    write("logo-ar-on-orange.svg", lockup(WHITE, WHITE, bg=ORANGE))

    # ---- الشعار الكامل مع WASEL ----
    write("logo-full-ink.svg", lockup(NAVY, ORANGE, en_c=NAVY))
    write("logo-full-white.svg", lockup(WHITE, ORANGE, en_c=WHITE))
    write("logo-full-on-navy.svg", lockup(WHITE, ORANGE, en_c=WHITE, bg=NAVY))
    write("splash-lockup.svg", lockup(WHITE, ORANGE, en_c=WHITE, pad=20))

    # ---- أيقونات التطبيقات (1024) ----
    def icon_word(width_pct):
        wg_w = ar_w + gap + (ch_x1 - ch_x0)
        k = 1024 * width_pct / 100 / wg_w
        body, _, _ = word_group(0, 0, WHITE, ORANGE)
        tx = (1024 - wg_w * k) / 2
        ty = (1024 - ar_h * k) / 2
        return f'<g transform="translate({tx:.2f},{ty:.2f}) scale({k:.4f})">{body}</g>'

    def icon_mark(color, pct):
        s = 1024 * pct / 100
        off = (1024 - s) / 2
        return f'<g transform="translate({off + s * 0.02:.2f},{off}) scale({s / 100})">{mark(color)}</g>'

    # الزبون: كحلي + «واصل» أبيض + شيفرون برتقالي (نفس الشعار)
    write("icon-customer-full.svg", svg(1024, 1024, icon_word(74), NAVY))
    write("icon-customer-foreground.svg", svg(1024, 1024, icon_word(54)))
    write("icon-customer-background.svg", svg(1024, 1024, "", NAVY))
    # التاجر والإدارة: نفس الشيفرون بألوانهم
    for app, (bg, c) in {"merchant": (LIME, INK), "admin": (BLUE, WHITE)}.items():
        write(f"icon-{app}-full.svg", svg(1024, 1024, icon_mark(c, 60), bg))
        write(f"icon-{app}-foreground.svg", svg(1024, 1024, icon_mark(c, 44)))
        write(f"icon-{app}-background.svg", svg(1024, 1024, "", bg))


if __name__ == "__main__":
    main()
