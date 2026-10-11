# -*- coding: utf-8 -*-
"""玩家实机观感预览：武器图在暗色地板上的可辨性（技能 Step 7）。
⚠ 重点检查 MP5（黑枪身）在接近黑的 FLOOR_COLOR 上是否糊掉。"""
from PIL import Image
FLOOR = (28, 28, 36, 255)    # Main.FLOOR_COLOR
WALL  = (77, 71, 66, 255)    # Main.WALL_COLOR
ANG = [0, 90, 180, 270]
WEPS = ["pistol", "smg", "mp_133"]
CELL = 56; PAD = 6
W = CELL * len(ANG) + PAD * (len(ANG) + 1)
H = CELL * len(WEPS) + PAD * (len(WEPS) + 1)
canvas = Image.new("RGBA", (W, H), WALL)
for i, wid in enumerate(WEPS):
    for j, a in enumerate(ANG):
        tile = Image.new("RGBA", (CELL, CELL), FLOOR)
        ic = Image.open("assets/sprites/ui_icon_wep_%s.png" % wid).convert("RGBA")
        ic = ic.rotate(-a, expand=True, resample=Image.NEAREST)   # 顺时针
        tile.alpha_composite(ic, ((CELL - ic.width)//2, (CELL - ic.height)//2))
        canvas.alpha_composite(tile, (PAD + j*(CELL+PAD), PAD + i*(CELL+PAD)))
zoom = 3
canvas.resize((W*zoom, H*zoom), Image.NEAREST).convert("RGB").save("production/previews/_weapon_on_floor.png")
print("OK -> production/previews/_weapon_on_floor.png | 行=pistol/smg/mp_133, 列=朝向 0/90/180/270")
