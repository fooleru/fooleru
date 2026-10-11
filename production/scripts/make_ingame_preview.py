# -*- coding: utf-8 -*-
"""实机观感预览（技能 Step 7）：把武器图标按占格放进模拟箱子面板（真实配色 + 真实尺寸）。"""
from PIL import Image, ImageDraw
SLOT = 10; COLS, ROWS = 12, 10
BG   = (41, 43, 56, 255)    # Backpack.SLOT_BG
LINE = (77, 82, 102, 255)   # Backpack.SLOT_LINE
PANEL =(23, 26, 36, 255)    # Backpack.BG

pad = 4
W = COLS*SLOT + pad*2; H = ROWS*SLOT + pad*2
canvas = Image.new("RGBA", (W, H), PANEL)
d = ImageDraw.Draw(canvas)
d.rectangle([pad, pad, pad+COLS*SLOT-1, pad+ROWS*SLOT-1], fill=BG)
for c in range(COLS+1):
    d.line([(pad+c*SLOT, pad), (pad+c*SLOT, pad+ROWS*SLOT)], fill=LINE)
for r in range(ROWS+1):
    d.line([(pad, pad+r*SLOT), (pad+COLS*SLOT, pad+r*SLOT)], fill=LINE)

def put(wid, tx, ty):
    ic = Image.open("assets/sprites/ui_icon_wep_%s.png" % wid).convert("RGBA")
    canvas.alpha_composite(ic, (pad+tx*SLOT, pad+ty*SLOT))

put("pistol", 0, 0)      # 2x2
put("smg",    3, 0)      # 3x2
put("mp_133", 0, 3)      # 4x1

zoom = 4
canvas.resize((W*zoom, H*zoom), Image.NEAREST).convert("RGB").save("production/previews/_ingame_preview.png")
print("OK -> production/previews/_ingame_preview.png (箱子面板 %dx%d 格，放大 %dx)" % (COLS, ROWS, zoom))
