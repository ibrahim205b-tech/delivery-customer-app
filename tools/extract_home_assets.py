"""يستخرج صور الصفحة الرئيسية لتطبيق الزبون من الصورة المرجعية design/home_reference.png.

كل صورة تُقص من المرجع نفسه (لا صور مولّدة ولا روابط خارجية):
- الشعار: قص + تلوين الدبوس فقط إلى البرتقالي #FF8C00 + خلفية شفافة.
- المطعم والتاكسي: قص + إزالة لون خلفية البطاقة (شفافية).
- البانر وصور العروض: قص + ملء أماكن النصوص/الزر/المؤشرات/شارات الخصم المطبوعة من المحيط،
  لأن التطبيق يرسمها نصوصاً حقيقية فوق الصورة.
- صور الأقسام: قص مباشر.
الاستخدام: python3 tools/extract_home_assets.py
"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'design', 'home_reference.png')
OUT = os.path.join(ROOT, 'apps', 'customer', 'assets', 'home')
os.makedirs(OUT, exist_ok=True)
im = Image.open(SRC).convert('RGB')
A = np.asarray(im).astype(np.float64)


def crop(x0, y0, x1, y1):
    return A[y0:y1 + 1, x0:x1 + 1].copy()


def save_rgb(a, name, q=95):
    img = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8), 'RGB')
    p = os.path.join(OUT, name)
    img.save(p, quality=q) if name.endswith('.jpg') else img.save(p, optimize=True)
    print(name, img.size)


def save_rgba(rgb, alpha, name):
    out = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    Image.fromarray(out, 'RGBA').save(os.path.join(OUT, name), optimize=True)
    print(name, out.shape[1], 'x', out.shape[0])


def unblend(a, bg, floor=0.12):
    """أقل شفافية تكفي لتفسير البكسل كلون فوق خلفية ثابتة (مناسب للرسوم على خلفية فاتحة)."""
    bg = np.array(bg, dtype=np.float64)
    lo = np.where(a < bg, (bg - a) / np.maximum(bg, 1), 0)
    hi = np.where(a > bg, (a - bg) / np.maximum(255 - bg, 1), 0)
    alpha = np.clip(np.max(np.maximum(lo, hi), axis=2), 0, 1)
    # تنعيم: الفروق الضئيلة (تدرج البطاقة وضغط الصورة) تصير شفافة بالكامل
    alpha = np.clip((alpha - floor) / (1 - floor), 0, 1)
    safe = np.maximum(alpha, 1e-3)[..., None]
    color = (a - (1 - alpha[..., None]) * bg) / safe
    return np.clip(color, 0, 255), alpha


def gblur(a, sigma):
    """تمويه غاوسي عبر FFT لكل قناة (بدون مكتبات إضافية)."""
    h, w = a.shape[:2]
    ky = np.fft.fftfreq(h)[:, None]
    kx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (np.pi ** 2) * (sigma ** 2) * (kx ** 2 + ky ** 2))
    if a.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(a) * g))
    return np.dstack([np.real(np.fft.ifft2(np.fft.fft2(a[..., c]) * g)) for c in range(a.shape[2])])


def inpaint(a, mask):
    """يملأ المنطقة المحددة من محيطها (التفاف مُطبّع على عدة مقاييس) ويضيف حبيبات خفيفة."""
    out = a.copy()
    known = (~mask).astype(np.float64)
    fill = np.zeros_like(a)
    done = np.zeros(mask.shape, bool)
    for s in (6, 14, 30, 60):
        num = gblur(a * known[..., None], s)
        den = gblur(known, s)[..., None]
        est = num / np.maximum(den, 1e-6)
        ok = (den[..., 0] > 0.05) & mask & ~done
        fill[ok] = est[ok]
        done |= ok
    rest = mask & ~done
    fill[rest] = a[~mask].mean(axis=0)
    rng = np.random.default_rng(3)
    fill += rng.normal(0, 2.2, fill.shape)
    # حافة ناعمة بين الأصل والملء
    soft = np.clip(gblur(mask.astype(np.float64), 2.0), 0, 1)[..., None]
    soft = np.where(mask[..., None], 1.0, soft)
    out = a * (1 - soft) + fill * soft
    return out


def rect_mask(shape, rects, ox=0, oy=0):
    m = np.zeros(shape[:2], bool)
    for x0, y0, x1, y1 in rects:
        m[y0 - oy:y1 - oy + 1, x0 - ox:x1 - ox + 1] = True
    return m


def circle_mask(shape, cx, cy, r, ox=0, oy=0):
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    return (xx + ox - cx) ** 2 + (yy + oy - cy) ** 2 <= r * r


# ---------- الشعار ----------
x0, y0, x1, y1 = 286, 46, 592, 156
logo = crop(x0, y0, x1, y1)
red = (logo[..., 0] > 110) & (logo[..., 0] - logo[..., 1] > 40) & (logo[..., 0] - logo[..., 2] > 40)
# الدبوس هو الجزء الأحمر الكبير المتصل (يسار الخطوط السريعة): x من 466 إلى 540 بالإحداثيات الأصلية
pin_zone = np.zeros(red.shape, bool)
pin_zone[:, 466 - x0:541 - x0] = True
# يشمل الحواف المنعّمة القريبة من الدبوس
pin_soft = pin_zone & ((logo[..., 0] - np.maximum(logo[..., 1], logo[..., 2])) > 12)
bgc = np.array([247, 246, 253], float)
redc = np.array([227, 6, 19], float)
orange = np.array([255, 140, 0], float)
# نسبة اللون الأحمر في كل بكسل (من القناة الخضراء) ثم إعادة الخلط بالبرتقالي
t = np.clip((bgc[1] - logo[..., 1]) / (bgc[1] - redc[1]), 0, 1)[..., None]
recol = t * orange + (1 - t) * bgc
logo = np.where(pin_soft[..., None], recol, logo)
c, al = unblend(logo, (247, 246, 253), 0.16)
save_rgba(c, al, 'logo.png')

# ---------- المطعم والتاكسي ----------
c, al = unblend(crop(612, 696, 795, 873), (251, 232, 208))
save_rgba(c, al, 'restaurant.png')
c, al = unblend(crop(42, 726, 266, 869), (252, 227, 200))
save_rgba(c, al, 'taxi.png')

# ---------- البانر ----------
# صورة الطعام فقط (قبل بداية النص عند x=478)، وحافتها اليمنى تتلاشى بشفافية.
# الخلفية الداكنة والنص والزر والمؤشرات يرسمها التطبيق.
bx0, by0, bx1, by1 = 0, 213, 478, 545
food = crop(bx0, by0, bx1, by1)
# مؤشرات السلايدر المطبوعة أسفل البانر (يرسمها التطبيق بدلها)
zone = rect_mask(food.shape, [(366, 503, 478, 528)], bx0, by0)
lum = food.mean(axis=2)
dots = zone & ((lum > 185) | ((food[..., 0] > 150) & (food[..., 0] - food[..., 1] > 80)))
# توسيع القناع حتى تختفي الحواف المنعّمة
grow = gblur(dots.astype(np.float64), 1.8) > 0.03
food = inpaint(food, grow & zone)
w = food.shape[1]
fade = np.clip((w - 1 - np.arange(w)) / 120.0, 0, 1) ** 1.4
alpha = np.tile(fade, (food.shape[0], 1))
save_rgba(food, alpha, 'banner_food.png')

# ---------- العروض ----------
# الصورة الأصلية كما هي. شارة الخصم يرسمها التطبيق في نفس المكان وبحجم أكبر قليلاً فتغطي المطبوعة.
for name, (px0, px1) in (('offer_pizza.jpg', (28, 412)), ('offer_chicken.jpg', (440, 824))):
    save_rgb(crop(px0, 1124, px1, 1322), name)

# ---------- أقسام المطاعم ----------
for name, (cx0, cx1) in (('cat_shawarma.jpg', (675, 823)), ('cat_grills.jpg', (510, 658)), ('cat_burger.jpg', (346, 493)), ('cat_pizza.jpg', (181, 328))):
    save_rgb(crop(cx0, 1532, cx1, 1632), name)
