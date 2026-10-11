# assets/sfx/SOURCES.md · 真实音效来源登记表（R-133 守护）

> 本文件是**未来**真实录音的**唯一**受控登记位。
> 当前音效库（Sfx.gd · 12 个 id）**100% 程序合成**——零外部素材，零版权风险。
> 若某天某个 id 走"实录音"路线（用户原话"如果很难生成就从网上找对应武器的真实声音（注意版权）"），
> **必须**在本文件登记才能进项目；否则 `--verify-sfx` ②-h 会判 FAIL。

---

## §1 当前状态（2026-10-08 · R-133）

| id            | 当前来源                | 状态        |
| ------------- | ----------------------- | ----------- |
| pistol_fire   | 程序合成（`_synth_pistol`） | 保留       |
| smg_fire      | 程序合成（`_synth_smg`）    | 保留       |
| shotgun_fire  | 程序合成（`_synth_shotgun`） | 保留       |
| hit_flesh     | 程序合成（`_synth_hit_flesh`） | 保留    |
| hit_wall      | 程序合成（`_synth_hit_wall`）  | 保留    |
| enemy_die_zombie | 程序合成              | 保留       |
| enemy_die_merc   | 程序合成              | 保留       |
| player_hurt   | 程序合成（`_synth_player_hurt`） | 保留 |
| pickup        | 程序合成               | 保留       |
| crate_open    | 程序合成               | 保留       |
| **step**      | **程序合成（R-133 重写为运动鞋）** | **已重生** |
| ui_confirm    | 程序合成               | 保留       |

**决策依据（R-133）**：

- **脚步（step）**：原 R-114 配方（460Hz 低通软 thud + 96→62Hz sub）听起来像地毯，玩家心理预期"运动鞋踩硬地"。重写为三层叠加（1800~3500Hz slap + 350~900Hz flex + 130→75Hz thump）。详见 `Sfx.gd::_synth_step` 的注释。
- **三把武器（pistol / smg / shotgun）**：**保留**程序合成。理由是这三把枪都是"瞬态冲击 + 体 + 亚低音"的标准合成路径（任何枪械音效教科书都是这三层），程序合成已经能听出"枪"。**没有"很难生成"的成分**——只有"还不够真实"。若要让"还不够真实"的差距落地，最经济的是继续调参（envelope / 滤波 / 层次），而不是砸版权进项目。

---

## §2 真要引入实录音时**必须**满足的三条

⚠⚠⚠ **任何**真实录音进入项目前，**全部三条都要满足**。一条不满足 → `--verify-sfx` ②-h FAIL。

### ① 许可证必须是**这五种之一**

| 许可证                              | 是否接受 | 备注 |
| ----------------------------------- | -------- | ---- |
| **CC0（Public Domain）**            | ✅ 必须   | 唯一全无条件接受的；freesound.org 上标 CC0 的素材 |
| **CC-BY**                           | ✅ 接受   | **必须**在 §3 写明 attribution 行（作者 + URL） |
| **CC-BY-SA**                        | ✅ 接受   | 同 CC-BY + 必须同许可证再分发（影响**整个项目**） |
| **MIT / BSD / Apache-2.0（源码许可）** | ❌ 不接受 | 这些是**源码**许可证，跟音频素材无关 |
| **GPL / LGPL（任何）**              | ❌ 不接受 | 污染项目；本项目是闭源游戏 |
| **未明确 / "免费但禁止商用"**       | ❌ 不接受 | 模糊地带 = 不进项目 |

### ② source URL 必须在 §3 表格里

任何新增的实录音条目**必须**填齐四列：`id` · `filename` · `source_url` · `license`。
任一空缺 → `--verify-sfx` ②-h 判 FAIL。

### ③ 文件本身必须在 `assets/sfx/` 下能找到

`assets/sfx/<filename>.wav` 必须存在（`OS.file_exists` 检查）；缺文件 → ②-h FAIL。

---

## §3 真实录音登记表（R-133 启动时为空）

<!--
  下面是唯一允许登记真实录音的表格。
  每条新增条目**必须**填齐四列；删条目时**必须**保留旧条目 + 写删除日期（备查）。
-->

| id | filename | source_url | license | sha256 | added_at |
| -- | -------- | ---------- | ------- | ------ | -------- |
| （空） | | | | | |

> 📌 **目前没有任何条目** —— 因为目前没有任何真实录音进项目。
> 第一次进真实录音时，请按下面格式加一行：
>
> ```
> | pistol_fire | pistol_real_001.wav | https://freesound.org/people/xxx/sounds/yyy/ | CC0 | <sha256> | 2026-10-XX |
> ```

---

## §4 推荐 source（按 R-133 评估排序）

1. **freesound.org** — 主流开源音效库，按 license 过滤可一键筛 CC0 / CC-BY；下载时**务必**勾"我已阅读并同意该 license"。新用户先做邮箱验证。
2. **Pixabay Audio**（pixabay.com/audio）—— 全部 royalty-free，可商用，无需 attribution。但仍**保留登记**（license 写 "Pixabay Content License"）以便审计。
3. **ZapSplat** —— CC-BY 为主（**必须 attribution**），量大；新手注意看清楚 license。
4. **BBC Sound Effects**（bbcsfx.acropolis.org.uk）—— 部分 CC-BY-NC（**非商用 → 本项目拒收**），仅标了 RemArc Licence 的才商用可用。
5. ❌ **YouTube 视频里扒的音轨**——几乎都是侵权的；不进项目。
6. ❌ **商业音效库（Splice / Soundsnap 等）**——单条 $1~$5 起步；除非走商业采购流程，否则不进项目。

---

## §5 故障排查

- `--verify-sfx` 报 `FAIL: ②-h assets/sfx/SOURCES.md 缺失` → 检查 §3 表格的列头是否**逐字**为 `id | filename | source_url | license | sha256 | added_at`（列名改一个字符都会红）。
- `--verify-sfx` 报 `FAIL: ②-h SOURCES.md 行 N 列 M 空` → 表格里那一行的那一列没填齐四列。
- `--verify-sfx` 报 `FAIL: ②-h 真实录音文件缺失` → 检查 `assets/sfx/<filename>.wav` 是否存在（大小写敏感）。

---

> **维护原则**：本文件**只增不删**。删除旧条目 = 假装那段录音从没进来过 = 审计断裂。
> 若某条录音后来发现 license 有问题 → 在该行后加 `⚠ INVALIDATED 2026-XX-XX · 原因`，但**不删原行**。
