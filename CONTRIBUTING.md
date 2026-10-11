# CONTRIBUTING · 协作铁律（破一条就白跑）

本文件是 **《百层逃生 / SKY DESCENT》cp1 原型**的协作护栏。每一条都来自真实事故（R-82~R-152），
不是风格建议。新增代码 / 跑回归 / 提 PR 前逐条对着检查。

---

## 0. 提交前

- **代码改动先过本地回归再提**（对得齐 `r152` 67/67 四项闭合）。
- 提交 git **等用户(项目 owner)审批**，不要自行 push main。
- 推送 GitHub 用 **personal access token**（HTTPS）或 SSH；GitHub 自 2021 起已不支持账号密码做 git 操作。

---

## 1. 跑回归的铁律（R-126 事故换来的）

1. **绝不要 `rm -rf qa_scratch/<批号>` 来"跑一轮干净的"。**
   锁在 `qa_scratch/.regression.lock`（与批号解耦）；删批号目录=删在跑实例的锁→两轮并行→summary 混写。
   **批号目录只增不删。**
2. **「用户取消对话框」不会杀掉后台 bash**——上一轮脚本可能还活着。开新一轮前先确认：
   `ls -d qa_scratch/.regression.lock`（有锁=有在跑）+ `tasklist | grep Godot`（Windows）。
3. 脚本拿到锁后会**自动 taskkill 孤儿 Godot**；孤儿不清会让后续入口 `rc=1` 且日志无收尾行。
4. **判定可采信必须四项闭合全过**：入口数==预期(67)、无重复入口、无 `????`/NOLOG、`FROZEN-OK`。
   只看 `P=/F=` 一行不够。
5. **回归在跑时不要编辑任何源文件**（含 `run_all_verify.sh` 本身）——bash 按字节偏移增量读脚本，
   中途改动会"读飞"并漏分类；md5 冻结也会因此报 NOT-OK。

**命令**：`bash qa_scratch/run_all_verify.sh <批号> 67`（从工程根运行）。

---

## 2. 缩进按文件（勿破）

- `scenes/enemies/Zombie.gd` = **4 空格**。
- `Main.gd` / `GameConstants.gd` / `Player.gd` / `Bullet.gd` / `Mercenary.gd` 等 = **Tab**。
- 以文件**实际字节**为准，不要全局替换缩进。混用会让 Godot 解析失败或 diff 噪声巨大。

---

## 3. 新增资源 / 节点

- 新增 PNG **必须先** `godot --headless --path . --import`，否则 `preload` 报 `has no resource loaders`。
- 中文 UI 字体走 `GameConstants.ui_font()`（SystemFont + 微软雅黑），**不要** `ThemeDB.fallback_font`。
- 尽量「代码 `new` 节点，不动 `Main.tscn`」以减少回归面。
- GDScript **`var` 是块级作用域**：在函数内不同 `if` 分支声明同名 `var` 会越界报错；
  需要跨分支用时在函数层统一声明，并加 null 保护。

---

## 4. 世界空间禁止文字（R-128 用户铁律，勿破）

- 用户逐字：「游戏场景内不能出现提示性文字，**游戏场景的文字只能出现在美术素材中**。」
- **分界线是「空间」**：
  - ❌ 禁止：`scenes/world/` `scenes/player/` `scenes/enemies/` `scenes/furniture/` `scenes/weapons/`
    （跟摄像机走、会缩放、被迷雾压暗→文字不可控地糊/错位，且语义锁死在代码里）。
  - ✅ 允许：`scenes/ui/*` 与 HUD（屏幕空间 UI，本就该有字）。
- 语义只能靠**美术素材 + 形状/颜色/动效**表达。**禁止**用 `draw_string` 补救。
- **机器守护**：`godot --headless --path . --verify-loc` 按**目录** grep 上述五个目录，
  出现 `draw_string(` / `draw_multiline_string(` / `draw_char(` / `Label.new()` 即 FAIL（跳过 `#` 注释行）。
  新增世界空间文件自动纳入，无需改清单。**改完必须做突变测试证明它会红。**
- 屏幕空间文案统一走 `Loc.t("<key>")`（`scripts/autoload/Loc.gd`），不在别处写字面量。
- 第 100 层出发点 = **12×12 实心黄方块 + 站上提亮，零文字**；「按 F 进入下一层」走底部 hint 通道(`Hint.gd`)。

---

## 5. 美术生产线（独立机器 `D:\work\ComfyUI`）

- **AI 出的 tileset sheet 不能当可平铺瓦片**（亮框/降采样噪点/白底漏底）。
  → AI 只定风格/概念图/角色道具+抠图；**环境瓦片必须像素级程序化**（`outputs/r126_tiles/make_tiles16.py`）。
- 像素化必须用 **`vsLinx_ImageToPixelArt`**（真调色板 + 抖动）。单纯 `ImageScale(nearest-exact)`
  降采样只得到 1381 色噪点；接 Pico-8(16) 色板后仅 13 色 = 真像素素材。
- 网络镜像（本机）：GitHub Release 直连 56KB/s 不可用 → `https://gh-proxy.com/` 前缀 + 4 路 Range 并行；
  HuggingFace 直连不通 → `https://hf-mirror.com`；PyPI → `-i https://pypi.tuna.tsinghua.edu.cn/simple`。
  无 aria2c/wget，只有 curl。内嵌 python 是 Windows 二进制 → 传路径用 `D:/...` 不用 `/d/...`。
- 仓库真名注意：`kijai/ComfyUI-segment-anything-2`（非 `ComfyUI-SAM2`）；`Azornes/comfyui-pixel-art` 不存在。

---

## 6. Godot 调用

- **Godot 调用不带 `--` 分隔符**：写成 `-- --verify-x` 会让 Godot 收不到 flag，表现为"日志连头都没有"，
  极易被误判成测试超时。
- 非 headless 会真开窗；同一工程**同时只能跑一个 Godot 实例**（`cp1_dod_log.txt` 会被覆盖）。

---

## 7. 验证纪律

- **突变测试必须亲自跑**，不能采信队友文字汇报（实测过"声称已改、实际没改"）。
  改一行守护逻辑后，先故意改坏被守护代码确认它红，再还原确认绿。
- 断言不得依赖真实物理移动/感知时滞；摆坐标后先断言前提成立，再断言结论。
- 凡关键交付，自己开文件 / 跑产物验证，不靠声明。
