# -*- coding: utf-8 -*-
"""批量：AI 武器原图 → 真透明 PNG + 缩放到占格尺寸 + 拼图检视（技能 Step 3/4）。
目标尺寸 = 占格 × INV_SLOT(10px)：pistol 2x2=20x20 / smg 3x2=30x20 / mp_133 4x1=40x10。"""
import os
from PIL import Image, ImageDraw, ImageFilter

THRESH_L = 244
FEATHER = 0.8
RAW = "assets/sprites/raw"
OUT = "assets/sprites"

WEAPONS = [
    ("pistol", "16_bit_pixel_art_inventory_ite_2026-10-08T00-49-12.png", (20, 20)),
    ("smg",    "16_bit_pixel_art_inventory_ite_2026-10-08T00-50-51.png", (30, 20)),
    ("mp_133", "16_bit_pixel_art_inventory_ite_2026-10-08T00-51-07.png", (40, 10)),
]

def matte(src):
    im = Image.open(src).convert("RGB")
    L = im.convert("L")
    alpha = L.point(lambda v: 0 if v >= THRESH_L else 255).filter(ImageFilter.GaussianBlur(FEATHER))
    out = im.convert("RGBA"); out.putalpha(alpha)
    bbox = out.getbbox()
    return out.crop(bbox) if bbox else out

report = []
for wid, raw, (tw, th) in WEAPONS:
    im = matte(os.path.join(RAW, raw))
    # 等比缩放到占格区域内接
    r = min(tw / im.width, th / im.height)
    sw, sh = max(1, round(im.width * r)), max(1, round(im.height * r))
    small = im.resize((sw, sh), Image.NEAREST)
    # 放进占格画布（居中，透明底）
    canvas = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
    canvas.alpha_composite(small, ((tw - sw) // 2, (th - sh) // 2))
    dst = os.path.join(OUT, "ui_icon_wep_%s.png" % wid)
    canvas.save(dst)
    a = canvas.getchannel("A"); px = list(a.getdata())
    trans = sum(1 for v in px if v == 0) / max(1, len(px))
    report.append((wid, im.size, (sw, sh), canvas.size, trans))
    print("OK %s | 抠图后=%s 内接=%s 画布=%s 透明=%.1f%%" % (wid, im.size, (sw, sh), canvas.size, trans*100))

# 拼图（棋盘底，放大 6x）
zoom = 6; pad = 12
tiles = [Image.open(os.path.join(OUT, "ui_icon_wep_%s.png" % w)).convert("RGBA") for w, *_ in WEAPONS]
W = sum(t.width for t in tiles) * zoom + pad * (len(tiles) + 1)
H = max(t.height for t in tiles) * zoom + pad * 2
sheet = Image.new("RGBA", (W, H), (60, 60, 66, 255))
d = ImageDraw.Draw(sheet)
for y in range(H):
    for x in range(W):
        if ((x // 10) + (y // 10)) % 2 == 0:
            sheet.putpixel((x, y), (90, 90, 96, 255))
x = pad
for t in tiles:
    big = t.resize((t.width * zoom, t.height * zoom), Image.NEAREST)
    sheet.alpha_composite(big, (x, (H - big.height) // 2))
    x += big.width + pad
sheet.convert("RGB").save(os.path.join(OUT, "_contact_weapons.png"))
print("拼图 -> production/previews/_contact_weapons.png")
