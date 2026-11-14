#!/usr/bin/env python3
"""رسومات أقسام تطبيق واصل (أصلية، Vector).
أسلوب موحّد: أشكال مسطحة مدوّرة بلا حدود، 3 درجات لكل جسم (أساس/ظل/لمعة)، ظل أرضي واحد، ألوان هوية الزبون.
الناتج: brand/illustrations/*.svg — ويتحوّل PNG بـ render_illustrations.js
"""
import pathlib

OUT = pathlib.Path(__file__).resolve().parent

INK = "#24160E"
YELLOW = "#FFC53D"
YELLOW_SH = "#EFA300"
YELLOW_HI = "#FFE08A"
INDIGO = "#13808A"  # فيروزي (تباين مع البرتقالي)
INDIGO_SH = "#0B6670"
INDIGO_HI = "#5DB8BF"
CORAL = "#E8432E"
CORAL_SH = "#C3311E"
MINT = "#1F9A73"
MINT_SH = "#167A5A"
CREAM = "#FFF4E6"
KRAFT = "#F3BF7A"
KRAFT_SH = "#DE9F55"
SKY = "#FFE6D6"
ORANGE = "#B23C0B"
ORANGE_HI = "#D9601F"
WHITE = "#FFFFFF"


def svg(body, w=600, h=460):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{body}</svg>\n'


def shadow(cx=300, cy=410, rx=210, ry=20):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{INK}" opacity=".10"/>'


def wheel(cx, cy, r=46):
    return (f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{INK}"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r*0.46:.1f}" fill="#D9D7EA"/>'
            f'<circle cx="{cx}" cy="{cy}" r="{r*0.17:.1f}" fill="{INK}"/>'
            f'<path d="M{cx-r*0.62:.1f} {cy-r*0.45:.1f} A{r*0.78:.1f} {r*0.78:.1f} 0 0 1 {cx+r*0.1:.1f} {cy-r*0.78:.1f}" fill="none" stroke="#3A3858" stroke-width="5" stroke-linecap="round"/>')


def speed_lines(x, y, color=INDIGO, n=3, gap=26, lens=(60, 40, 50)):
    s = ""
    for i in range(n):
        L = lens[i % len(lens)]
        s += f'<rect x="{x}" y="{y + i * gap}" width="{L}" height="10" rx="5" fill="{color}" opacity="{0.9 - i * 0.25:.2f}"/>'
    return s


# ---------------------------------------------------------------- التكسي
def taxi():
    b = shadow(300, 404, 236, 20)
    # خطوط الحركة خلف السيارة (السيارة تتجه يسار = اتجاه القراءة العربية)
    b += speed_lines(520, 200, INDIGO, 3, 30, (58, 38, 48))
    # الهيكل السفلي
    b += f'<path d="M64 262 C64 232 86 214 118 210 L476 206 C512 204 536 226 538 262 L540 312 C540 334 524 350 500 350 L104 350 C80 350 64 334 64 312 Z" fill="{YELLOW}"/>'
    b += f'<path d="M64 300 L540 300 L540 312 C540 334 524 350 500 350 L104 350 C80 350 64 334 64 312 Z" fill="{YELLOW_SH}"/>'
    # الكابينة
    b += f'<path d="M150 214 C168 150 196 122 246 120 L384 120 C428 120 452 150 470 214 Z" fill="{YELLOW}"/>'
    b += f'<path d="M150 214 C168 150 196 122 246 120 L262 120 C222 128 204 160 192 214 Z" fill="{YELLOW_HI}" opacity=".7"/>'
    # الشبابيك
    b += f'<path d="M188 206 C200 162 218 142 252 142 L298 142 L298 206 Z" fill="{INDIGO}"/>'
    b += f'<path d="M314 142 L378 142 C410 142 428 162 440 206 L314 206 Z" fill="{INDIGO}"/>'
    b += f'<path d="M216 200 L262 148 L280 148 L234 200 Z" fill="{WHITE}" opacity=".28"/>'
    b += f'<path d="M346 200 L392 148 L404 148 L358 200 Z" fill="{WHITE}" opacity=".22"/>'
    # لافتة السقف (مربعات بلا نص)
    b += f'<rect x="250" y="84" width="104" height="38" rx="12" fill="{INK}"/>'
    for i in range(4):
        x = 262 + i * 21
        b += f'<rect x="{x}" y="{94 if i % 2 == 0 else 104}" width="14" height="10" rx="2.5" fill="{YELLOW}"/>'
    # شريط المربعات
    for i in range(18):
        x = 92 + i * 24
        b += f'<rect x="{x}" y="{240 if i % 2 == 0 else 252}" width="12" height="12" rx="2" fill="{INK}" opacity=".9"/>'
    # خط الباب والمقابض
    b += f'<path d="M306 214 L306 296" stroke="{YELLOW_SH}" stroke-width="5" stroke-linecap="round"/>'
    b += f'<rect x="262" y="272" width="30" height="9" rx="4.5" fill="{YELLOW_SH}"/><rect x="322" y="272" width="30" height="9" rx="4.5" fill="{YELLOW_SH}"/>'
    # الضوء الأمامي (يسار) والخلفي
    b += f'<ellipse cx="82" cy="262" rx="20" ry="17" fill="{CREAM}"/><ellipse cx="78" cy="258" rx="7" ry="6" fill="{WHITE}"/>'
    b += f'<path d="M40 248 L58 256 M36 268 L56 268 M40 288 L58 280" stroke="{YELLOW}" stroke-width="7" stroke-linecap="round" opacity=".8"/>'
    b += f'<rect x="522" y="246" width="18" height="30" rx="8" fill="{CORAL}"/>'
    # الصدّامات
    b += f'<rect x="54" y="316" width="80" height="22" rx="11" fill="{INK}"/><rect x="474" y="316" width="76" height="22" rx="11" fill="{INK}"/>'
    # أقواس العجلات + العجلات
    b += f'<path d="M110 350 A58 58 0 0 1 226 350 Z" fill="{YELLOW_SH}"/><path d="M376 350 A58 58 0 0 1 492 350 Z" fill="{YELLOW_SH}"/>'
    b += wheel(168, 352, 46) + wheel(434, 352, 46)
    return svg(b)


# ---------------------------------------------------------------- الطعام
def food():
    b = shadow(300, 410, 200, 20)
    # كوب جانبي
    b += f'<path d="M402 236 L476 236 L466 392 C465 402 457 408 448 408 L430 408 C421 408 413 402 412 392 Z" fill="{INDIGO}"/>'
    b += f'<path d="M448 236 L476 236 L466 392 C465 402 457 408 448 408 Z" fill="{INDIGO_SH}"/>'
    b += f'<rect x="394" y="218" width="90" height="24" rx="10" fill="{INDIGO_HI}"/>'
    b += f'<path d="M444 220 L466 150 L486 150" fill="none" stroke="{CORAL}" stroke-width="11" stroke-linecap="round" stroke-linejoin="round"/>'
    b += f'<rect x="414" y="290" width="50" height="40" rx="10" fill="{WHITE}" opacity=".22"/>'
    # الكيس
    b += f'<path d="M150 196 L386 196 L398 384 C399 398 389 408 375 408 L161 408 C147 408 137 398 138 384 Z" fill="{CORAL}"/>'
    b += f'<path d="M330 196 L386 196 L398 384 C399 398 389 408 375 408 L344 408 Z" fill="{CORAL_SH}"/>'
    # حافة الكيس المتعرجة
    pts = "150,196 " + " ".join(f"{150 + i * 16},{196 if i % 2 == 0 else 210}" for i in range(16)) + " 390,196"
    b += f'<polyline points="{pts}" fill="none" stroke="{CREAM}" stroke-width="8" stroke-linejoin="round" stroke-linecap="round"/>'
    # البرگر يطلع من الكيس
    b += f'<path d="M176 196 C176 130 222 104 268 104 C314 104 360 130 360 196 Z" fill="{YELLOW}"/>'
    b += f'<path d="M300 106 C338 114 360 144 360 196 L326 196 C326 150 316 122 300 106 Z" fill="{YELLOW_SH}"/>'
    for (x, y) in [(220, 138), (250, 124), (284, 128), (238, 158), (306, 150), (270, 156)]:
        b += f'<ellipse cx="{x}" cy="{y}" rx="7" ry="4.5" fill="{CREAM}" transform="rotate(-20 {x} {y})"/>'
    # خس وجبن تحت الخبزة
    b += f'<path d="M166 196 C178 182 190 206 204 192 C218 178 230 206 244 192 C258 178 270 206 284 192 C298 178 310 206 324 192 C338 178 350 206 366 194 L366 210 L166 210 Z" fill="{MINT}"/>'
    # الوجه (شخصية الكيس)
    b += f'<ellipse cx="226" cy="290" rx="13" ry="16" fill="{INK}"/><ellipse cx="300" cy="290" rx="13" ry="16" fill="{INK}"/>'
    b += f'<circle cx="230" cy="284" r="5" fill="{WHITE}"/><circle cx="304" cy="284" r="5" fill="{WHITE}"/>'
    b += f'<path d="M236 326 C252 346 276 346 292 326" fill="none" stroke="{INK}" stroke-width="9" stroke-linecap="round"/>'
    b += f'<ellipse cx="200" cy="322" rx="15" ry="9" fill="{CREAM}" opacity=".45"/><ellipse cx="326" cy="322" rx="15" ry="9" fill="{CREAM}" opacity=".45"/>'
    # بخار
    for x in (226, 268, 310):
        b += f'<path d="M{x} 86 C{x - 12} 70 {x + 12} 58 {x} 40" fill="none" stroke="{INDIGO}" stroke-width="8" stroke-linecap="round" opacity=".55"/>'
    return svg(b)


# ---------------------------------------------------------------- ودي أغراضك بأمان
def parcel():
    b = shadow(300, 410, 220, 20)
    # عربة نقل صغيرة
    b += f'<rect x="96" y="356" width="370" height="22" rx="11" fill="{ORANGE}"/>'
    b += f'<path d="M96 368 L74 236" stroke="{ORANGE}" stroke-width="16" stroke-linecap="round"/>'
    b += f'<rect x="58" y="218" width="44" height="22" rx="11" fill="{ORANGE_HI}"/>'
    b += wheel(150, 386, 26) + wheel(416, 386, 26)
    # الصندوق
    b += f'<path d="M130 176 L430 176 L430 338 C430 348 422 356 412 356 L148 356 C138 356 130 348 130 338 Z" fill="{KRAFT}"/>'
    b += f'<path d="M352 176 L430 176 L430 338 C430 348 422 356 412 356 L352 356 Z" fill="{KRAFT_SH}"/>'
    b += f'<path d="M118 150 L442 150 C448 150 452 154 452 160 L452 176 L108 176 L108 160 C108 154 112 150 118 150 Z" fill="{KRAFT_SH}"/>'
    # شريط اللاصق
    b += f'<rect x="254" y="150" width="52" height="206" fill="{ORANGE}" opacity=".92"/>'
    b += f'<rect x="254" y="150" width="14" height="206" fill="{WHITE}" opacity=".18"/>'
    # الوجه
    b += f'<ellipse cx="190" cy="262" rx="11" ry="14" fill="{INK}"/><ellipse cx="226" cy="262" rx="11" ry="14" fill="{INK}"/>'
    b += f'<circle cx="193" cy="257" r="4" fill="{WHITE}"/><circle cx="229" cy="257" r="4" fill="{WHITE}"/>'
    b += f'<path d="M194 292 C202 304 216 304 224 292" fill="none" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
    # درع الأمان (علامة صح)
    b += f'<path d="M376 196 L452 222 L452 280 C452 326 420 352 376 368 C332 352 300 326 300 280 L300 222 Z" fill="{MINT}"/>'
    b += f'<path d="M376 196 L452 222 L452 280 C452 326 420 352 376 368 Z" fill="{MINT_SH}"/>'
    b += f'<path d="M338 280 L366 308 L418 252" fill="none" stroke="{WHITE}" stroke-width="16" stroke-linecap="round" stroke-linejoin="round"/>'
    return svg(b)


# ---------------------------------------------------------------- المحلات
def shops():
    b = shadow(300, 410, 220, 20)
    # واجهة محل خلفية
    b += f'<rect x="96" y="120" width="300" height="270" rx="20" fill="{SKY}"/>'
    b += f'<rect x="126" y="232" width="110" height="158" rx="14" fill="{INDIGO_HI}" opacity=".55"/>'
    b += f'<rect x="262" y="232" width="104" height="92" rx="14" fill="{WHITE}"/>'
    b += f'<rect x="276" y="246" width="34" height="64" rx="8" fill="{SKY}"/><rect x="318" y="270" width="34" height="40" rx="8" fill="{SKY}"/>'
    # المظلة المخططة
    for i in range(6):
        x = 86 + i * 54
        b += f'<path d="M{x} 150 L{x + 54} 150 L{x + 54} 186 C{x + 54} 202 {x + 40} 212 {x + 27} 212 C{x + 14} 212 {x} 202 {x} 186 Z" fill="{YELLOW if i % 2 == 0 else WHITE}"/>'
    b += f'<rect x="80" y="118" width="336" height="40" rx="14" fill="{ORANGE}"/>'
    # الكيس الكبير (أمام يمين)
    b += f'<path d="M318 236 C318 196 340 176 368 176 C396 176 418 196 418 236" fill="none" stroke="{INK}" stroke-width="11" stroke-linecap="round"/>'
    b += f'<path d="M290 230 L446 230 L462 392 C463 402 456 410 446 410 L290 410 C280 410 273 402 274 392 Z" fill="{MINT}"/>'
    b += f'<path d="M404 230 L446 230 L462 392 C463 402 456 410 446 410 L414 410 Z" fill="{MINT_SH}"/>'
    b += f'<circle cx="340" cy="300" r="22" fill="{WHITE}" opacity=".9"/><path d="M330 300 L338 308 L352 292" fill="none" stroke="{MINT}" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>'
    # الكيس الصغير (أمام يسار)
    b += f'<path d="M168 290 C168 262 184 248 204 248 C224 248 240 262 240 290" fill="none" stroke="{INK}" stroke-width="10" stroke-linecap="round"/>'
    b += f'<path d="M146 286 L262 286 L274 394 C275 403 268 410 259 410 L149 410 C140 410 133 403 134 394 Z" fill="{CORAL}"/>'
    b += f'<path d="M232 286 L262 286 L274 394 C275 403 268 410 259 410 L240 410 Z" fill="{CORAL_SH}"/>'
    b += f'<rect x="166" y="320" width="60" height="12" rx="6" fill="{CREAM}" opacity=".8"/><rect x="166" y="342" width="40" height="12" rx="6" fill="{CREAM}" opacity=".6"/>'
    # بريق
    for (x, y, r) in [(470, 150, 10), (500, 190, 6), (66, 230, 7)]:
        b += f'<path d="M{x} {y - r * 2} L{x + r * 0.5} {y - r * 0.5} L{x + r * 2} {y} L{x + r * 0.5} {y + r * 0.5} L{x} {y + r * 2} L{x - r * 0.5} {y + r * 0.5} L{x - r * 2} {y} L{x - r * 0.5} {y - r * 0.5} Z" fill="{YELLOW}"/>'
    return svg(b)


if __name__ == "__main__":
    for name, fn in [("taxi", taxi), ("food", food), ("parcel", parcel), ("shops", shops)]:
        (OUT / f"{name}.svg").write_text(fn(), encoding="utf-8")
        print("wrote", name)
