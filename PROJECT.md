# 百层逃生 / SKY DESCENT — cp1 手感原型

> **协作入口文档。** 新接手的人按这个顺序读：① 本文件 → ② `CONTRIBUTING.md`（铁律，破一条就白跑）→ ③ `TASKS.md`（认领你要做的卡）。

---

## 这是什么

- 仙侠主题 **2D 弹幕 roguelite**，引擎 **Godot 4.7.2**（GDScript）。
- 内部分辨率 **320×180**，瓦片 **16×16**，世界 128×86 格。
- 资源架构遵循设计文档 §6.5 的 **4 层模型**：L0 背景 / L1 角色 / L2 弹幕 / L3 HUD。
- 美术圣经已定视角：**正俯（轴对齐网格，非 iso）+ ZERO Sievert 式 3/4 可读画法**。
  （外部参照 ZS = Zero Sievert，不是 Project Zomboid。）

## 当前状态

- 阶段：**cp1 手感原型**——只验证核心手感，不是完整游戏。
- **回归基线 = `r152`，67/67 PASS，四项闭合**（判定口径见下「回归可采信条件」）。
  所有新提交的代码都必须对得上这条基线，不允许「只看 P=/F= 一行」就当过。
- 最近落地：分裂怪 Boss 仅视觉生成闸门（R-150）；全量回归 r152 已 67/67 闭环。

## 目录地图

| 路径 | 内容 | 入库？ |
|------|------|--------|
| `assets/` | sprites / tiles / sfx（游戏资源） | ✅ |
| `data/` | `floor100.txt` 等关卡数据 | ✅ |
| `design/` | 美术圣经、GDD、UX、概念、外部参照（本仓库已收敛） | ✅ |
| `production/` | 美术产出脚本(`scripts/`)、瓦片、预览 | ✅（previews 大图按需） |
| `scenes/` | `world/ player/ enemies/ furniture/ weapons/ ui/`（**按空间分层**） | ✅ |
| `scripts/` | `autoload/ main/ ...`（GDScript） | ✅ |
| `project.godot` | Godot 工程文件 | ✅ |
| `qa_scratch/` | 回归批次与脚本、日志 | ❌（`.gitignore`） |
| `outputs/` | 生成物（地图 PNG、瓦片） | ❌（`.gitignore`） |
| `*.txt`（根） | `dod_*.txt` / `*_log.txt` 等过程日志 | ❌（`.gitignore`） |

## 如何运行

- 打开工程：用 Godot 4.7.2 打开 `project.godot`（`godot --path .`）。
- **全量 headless 回归**（从工程根运行）：
  ```bash
  bash qa_scratch/run_all_verify.sh <批号> 67
  ```
  预期入口数 **67**。跑前会自动查锁、清孤儿 Godot、冻结源文件 md5。
- 单入口冒烟：`godot --headless --path . --verify-<name>`（如 `--verify-splitter`、`--verify-loc`）。
- 世界空间禁文字守护：`godot --headless --path . --verify-loc` 必须 `rc=0`。

## 如何参与协作（积分分担模型）

目标：**多人各自认领 `TASKS.md` 一张卡，在「自己机器 / 自己 WorkBuddy 账号」上开发并跑回归**，
积分各算各的，不挤在同一个会话里串行烧。

三种分摊机制（按推荐度）：

1. **GitHub Actions 跑回归（推荐，几乎不耗本地积分）**——把 headless 回归挂 CI，
   push 后由 GitHub 免费额度跑出 67/67 报告。见 `TASKS.md` T10。
2. **每人本地认领卡**——clone 后在自己账号上改 + 跑对应 `--verify-*`，只对得齐 r152 基线再提 PR。
3. **重活(生图)外移**——AI 美术放独立机器 `d:\work\ComfyUI`，不占游戏机回归时间（见下「美术线」）。

> ⚠ 同一台机器**同时只能跑一个 Godot 实例**（会互踩 `cp1_dod_log.txt`）。本地多人并行请用不同机器或错峰。

## 回归可采信条件（四项必须同时成立）

1. 实际入口数 == 预期（67）；
2. 无重复入口；
3. 无 `????` / NOLOG（即每个入口都跑出了结论）；
4. `FROZEN-OK`（跑前跑后源文件 md5 一致，证明回归期间没人改源文件）。

只看 `P=/F=` 一行**不够**。

## 护栏速查（破一条就白跑，详见 `CONTRIBUTING.md`）

- 跑回归前先 `ls -d qa_scratch/.regression.lock` 确认无在跑实例；**绝不要 `rm -rf qa_scratch/<批号>`**。
- 回归期间**不编辑任何源文件**（含 `run_all_verify.sh` 本身）。
- 缩进按文件：`Zombie.gd`=4 空格；`Main/GameConstants/Player/Bullet/Mercenary`=Tab。
- 世界空间(`scenes/world|player|enemies|furniture|weapons/`)**禁止任何文字**，只走 `scenes/ui` + `Hint.gd` 底部通道。
- 新增 PNG **必须先** `godot --headless --path . --import`。
- Godot 调用**不带 `--` 分隔符**（会吞掉 flag，表现为"日志连头都没有"）。
- AI 只定风格；**瓦片必须程序化**（无缝前提只能由生成方保证）。
- 突变测试**必须亲自跑**，不信队友文字汇报。

## 美术线（独立机器）

- 位置 `D:\work\ComfyUI\`，文档 `D:\work\ComfyUI\README_游戏美术工作流.md`。
- 像素化必须用 `vsLinx_ImageToPixelArt`（真调色板+抖动）；单纯降采样只得到噪点。
- 瓦片程序化：`outputs/r126_tiles/make_tiles16.py`（哈希可复现 + 16px 周期砖缝）。
- 网络镜像：GitHub 走 `gh-proxy.com` 前缀；HuggingFace 走 `hf-mirror.com`；PyPI 走 tuna。

## 外部参照

- ZS 数值真值：`D:\games\Zero.Sievert\ZS_vanilla\gamedata\*.json`。
- 设计文档（本仓库 `design/`）：`art/art-bible.md` §9 禁忌 46（世界空间禁文字）、`gdd/` 各系统、`ux/ux-spec.md`。
