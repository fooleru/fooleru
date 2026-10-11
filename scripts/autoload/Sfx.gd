# Sfx · **全代码合成**音效库（R-114 + R-133 脚步重生）
#
# === R-133 重生结论 ===
#   用户原话：「重新生成音效，风格要求更贴近现实，玩家脚步声改成旅游鞋或者运动鞋的声音。
#             武器音效如果很难生成就从网上找对应武器的真实声音（注意版权）。」
#   本批决定：
#     · **脚步**：从原 R-114 的"460Hz 低通软 thud + 96→62Hz sub"（听起来像地毯）重写为
#       三层叠加的「运动鞋踩硬地面」—— 1800~3500Hz 宽带 slap + 350~900Hz 中频 flex +
#       130→75Hz 短亚低音 thump。峰值 0.55、时长 0.120s。
#     · **武器（pistol/smg/shotgun）**：**保留 R-114 配方不动**。理由：
#       三把枪都是「瞬态冲击 + 体 + 亚低音」的标准合成路径（任何枪械音效教科书
#       都是这三层），程序合成已经能听出"枪"。**没有"很难生成"的成分**。
#       若未来出现更复杂的武器（霰弹枪膛内回响、特定枪械机匣咔哒声、火焰尾音等）
#       → 走 _wav_file(id) 加载真实 WAV 的扩展点（详见下方"R-133 扩展点"）。
#     · **网络实录音源**：见 `assets/sfx/SOURCES.md`（已留位）—— 真要引入实录音时
#       必须在该文件登记 source + license，否则**项目拒收**（--verify-sfx ②-h 守护）。
#
# === R-133 扩展点（未来加真实 WAV 的接入路径）===
#   现在的 12 个 id **全部走 `_synth_*()` 程序合成**。若某天需要把某个 id 替换成
#   真实录音，按以下三步走（已留位置、未启用）：
#     ① 把 WAV 放到 `assets/sfx/<id>.wav`（22050Hz / mono / 16-bit，与本库规格一致）；
#     ② 在 `assets/sfx/SOURCES.md` 登记 source URL + license + 哈希；
#     ③ 在 `_build()` 里把 `_lib[id] = _wav(_synth_xxx())` 改成
#        `_lib[id] = _wav_from_file(id)`（后者待实现，签名见下）。
#   ⚠ `_wav_from_file()` 本批**故意未实现**：用户原话是"如果很难生成**就**从网上找"，
#     是兜底而非首选；现在不需要 = 现在不写（避免留一截死代码）。
#
# === 这个 autoload 解决什么 ===
# 《百层逃生 / SKY DESCENT》CP1 原型此前**零音频**：没有任何 .ogg/.wav/.mp3，
#   也没有自定义总线。开火 / 命中 / 死亡 / 拾取全是"哑"的 —— 手感验证（G1-G5）
#   缺了听觉反馈这一半，而听觉反馈恰恰是"打击感"最大的单一来源。
#
# === 用户两轮拍板（本文件的全部设计前提）===
#   ① **音效来源 = 代码合成**（R-114 主基调）：零外部素材、零版权风险、
#      零导入管线依赖，改一个数字就能重渲，**立刻能用**。
#      R-133 把这个基调**收紧到"音效库本体"**，把"实录音"放到了
#      `assets/sfx/SOURCES.md` 这个**受控、可审计**的扩展点。
#   ② **首批范围 = 核心战斗 + 交互**：开火 / 命中 / 敌人死亡 / 拾取开箱 / 脚步 / UI 确认。
#
# === ⚠⚠ 核心技术决策：预渲染为 AudioStreamWAV，**不用** AudioStreamGenerator ===
#   备选 A（被否）：AudioStreamGenerator + 每帧 `push_buffer`。
#     · 否决理由 1：它必须挂 `_process` 逐帧喂数据，而本工程 Player / Zombie 的
#       逻辑**全在 `_physics_process`** —— 两套时基打架，且移动端后台/暂停语义要额外处理。
#     · 否决理由 2（决定性）：headless 验证时音频回调可能不跑 → **无法验证**。
#       本工程的立身之本就是"每个系统都要有一个能断言的 headless 入口"，
#       一个测不了的功能等于没有功能。
#   备选 B（采纳）：启动时用公式算出 PCM 采样 → 封进 `AudioStreamWAV`
#     （FORMAT_16_BITS / mix_rate=22050 / stereo=false）→ 播放时**零 CPU 开销**。
#     · 附带好处：整个音效库是**纯数据**，可以在 headless 里逐条断言
#       「采样数 / 峰值 / RMS / 过零率 / 起始瞬态」—— 符合本工程既有的可验证纪律。
#
# === 混音规格（为什么是这组数）===
#   · mix_rate 22050：内部分辨率只有 320×180、玩法是俯视角 2D，
#     最高频内容（脚步/开火瞬态）远在 11kHz 以下。22050 让同样时长的波形
#     内存只有 44.1kHz 的**一半**，12 个音效预渲染总耗时实测 < 10ms。
#   · FORMAT_16_BITS / stereo=false：单声道足够（全部音效都是单点事件，
#     声像定位未来要留给真正的音频中间件），16bit 是"峰值不会被量化噪底吃掉"的底线。
#   · ⚠ **绝不改 Master 音量**：本文件只**新增**一条 SFX 总线并把播放器挂上去，
#     Master 一律保持 0dB（用户要能随时听到声音、也要能自己调）。
#
# === 三条降噪护栏（叠加场景下的"音效墙"是本文件最大的设计风险）===
#   ① **播放池轮转**（POOL_SIZE 个 AudioStreamPlayer）：并发上限硬封顶，
#      不会出现"每个音效一个播放器"的节点爆炸。
#   ② **同类切断**：同一 id 上一次用的那个播放器**直接 stop 掉再复用**。
#      → 60 只僵尸同时嘶吼也只会**一声**（而不是 60 声叠成噪音墙）。
#      副作用是好的：SMG 13.3rps 连射会得到"哒哒哒"的紧实颗粒，而不是糊成一片。
#   ③ **同帧 / 最短间隔限流**（MIN_REPLAY_MS = 45ms）：
#      · 同帧重复直接吞掉 —— 霰弹枪**一发 6 弹丸**在同一帧打中 6 个目标时，
#        `take_damage` 会被调 6 次；没有这道闸就是 6 声"啪"叠在一起。
#      · 45ms 的依据：全工程**最快的合法重复间隔**是 SMG 的
#        `SMG_FIRE_COOLDOWN = 0.075s = 75ms`（手枪 180ms / MP133 470ms）。
#        45 < 75 → **永远不会误伤正常连射**（留 30ms 余量给 pitch 抖动与调度抖动），
#        同时把"同一瞬间的多次结算"压成 1 声。
#      ⚠ 若将来加入比 SMG 更快的武器（<45ms），必须同步下调本值。
#
# === 失败姿态 ===
#   `play()` 对**不存在的 id 静默失败**（返回 false，不 push_error）。
#   理由：Sfx 会被 5 个 gameplay 文件在热路径上调用，若用 id 拼错了就刷错误日志，
#   等于用开发期噪音换一个"其实没问题"的问题。测试用返回值判断，不靠日志。
#
# === 只读观测接口（供 --verify-sfx 断言用；**不改任何游戏逻辑**）===
#   count_of() / total_plays() / peak_of() / rms_of() / energy_of() /
#   zero_crossings_of() / argmax_of() / sample_count() / stream_of()
#   ⚠ 全部只读已建好的 `AudioStreamWAV.data`（**从真正的 PCM 字节反解**，
#     不是读缓存的浮点数组）→ 这样断言校验的是"真正送进声卡的那串字节"。
extends Node

# === 混音规格常量 ===
const MIX_RATE: int = 22050          # ⚠ 逐字；改这里要同步改 --verify-sfx 的期望值
const CHANNELS: int = 1              # mono
const POOL_SIZE: int = 12            # 播放池大小（并发上限）
const BUS_SFX: String = "SFX"        # 新增总线名；Master 保持 0dB 不动
const PITCH_JITTER: float = 0.06     # ±6% 音高抖动（让重复音效不机械）
const MIN_REPLAY_MS: int = 45        # 同类最短重放间隔；依据见文件头护栏 ③

# 音效 id 全集（**唯一权威清单**；--verify-sfx 逐条硬断言这张表）
const IDS: Array = [
	"pistol_fire", "smg_fire", "shotgun_fire",
	"hit_flesh", "hit_wall",
	"enemy_die_zombie", "enemy_die_merc",
	"player_hurt", "pickup", "crate_open",
	"step", "ui_confirm",
]

# === 运行时状态 ===
var _lib: Dictionary = {}            # id -> AudioStreamWAV
var _pool: Array = []                # Array[AudioStreamPlayer]
var _pool_i: int = 0
var _owner: Dictionary = {}          # id -> 上一次用的播放器（同类切断）
var _owner_of: Dictionary = {}       # 播放器 -> id（防两个 id 抢同一个播放器）
var _last_ms: Dictionary = {}        # id -> 上次播放的 Time.get_ticks_msec()
var _last_frame: Dictionary = {}     # id -> 上次播放的 Engine.get_process_frames()
var _count: Dictionary = {}          # id -> 实际播放次数（只读观测）
var _total: int = 0
var _built: bool = false
var _bus_ok: bool = false
var _jr: RandomNumberGenerator = null   # 抖动专用 RNG（**不碰全局 randf** → 可复现）

# ⚠ 抖动必须用**自己的** RNG：`randf()` 会被玩法侧的 `_seed` 推进，
#   那样同一个音效在不同时刻抖动不同 → 验证不可复现。
func _ensure_jr() -> RandomNumberGenerator:
	if _jr == null:
		_jr = RandomNumberGenerator.new()
		_jr.seed = 0x5EED
	return _jr

func _ready() -> void:
	_jr = _ensure_jr()
	_build()

# ----------------------------------------------------------------------
# 对外 API
# ----------------------------------------------------------------------

## 播放一个音效。id 不存在时**静默失败**（返回 false，不报错不刷屏）。
## jitter=false 可关闭音高抖动 —— 测试必须用它才能得到可复现的断言。
func play(id: String, volume_db: float = 0.0, pitch: float = 1.0, jitter: bool = true) -> bool:
	_ensure_built()
	if not _lib.has(id):
		return false
	if _throttled(id):
		return false
	var st: AudioStreamWAV = _lib[id]
	var pl: AudioStreamPlayer = _claim_player(id)
	pl.stream = st
	pl.volume_db = volume_db
	pl.pitch_scale = maxf(0.01, pitch * _jitter_factor(jitter))
	pl.play()
	_last_ms[id] = Time.get_ticks_msec()
	_last_frame[id] = Engine.get_process_frames()
	_count[id] = int(_count.get(id, 0)) + 1
	_total += 1
	return true

## 把某个音效池里正在响的播放器全部停掉（切场景 / 玩家死亡时用）。
func stop_all() -> void:
	for pl in _pool:
		if is_instance_valid(pl):
			pl.stop()

## 清空播放计数与限流状态（**仅供 --verify-sfx 逐段隔离断言**）。
func reset_counters() -> void:
	_count.clear()
	_total = 0
	_last_ms.clear()
	_last_frame.clear()

# ---- 只读观测接口（测试用；不参与任何玩法判定）----
func has_id(id: String) -> bool:
	return _lib.has(id)

func stream_of(id: String) -> AudioStreamWAV:
	return _lib.get(id, null)

func count_of(id: String) -> int:
	return int(_count.get(id, 0))

func total_plays() -> int:
	return _total

func bus_ready() -> bool:
	return _bus_ok

func pool_size() -> int:
	return _pool.size()

## 采样数（从 AudioStreamWAV 的真实字节数反推：data.size() / 2）。
func sample_count(id: String) -> int:
	var st: AudioStreamWAV = _lib.get(id, null)
	if st == null:
		return 0
	return st.data.size() / (2 * CHANNELS)

func peak_of(id: String) -> float:
	var b: PackedFloat32Array = _decode(id)
	var pk: float = 0.0
	for v in b:
		pk = maxf(pk, absf(v))
	return pk

func rms_of(id: String) -> float:
	var b: PackedFloat32Array = _decode(id)
	if b.is_empty():
		return 0.0
	var acc: float = 0.0
	for v in b:
		acc += v * v
	return sqrt(acc / float(b.size()))

## 总能量 = Σx²（不除以采样数）。用于"重武器总能量必须更大"这类断言。
func energy_of(id: String) -> float:
	var b: PackedFloat32Array = _decode(id)
	var acc: float = 0.0
	for v in b:
		acc += v * v
	return acc

## 过零次数：波形"亮度"的廉价代理（噪声/高频成分越多 → 越高）。
func zero_crossings_of(id: String) -> int:
	var b: PackedFloat32Array = _decode(id)
	var z: int = 0
	for i in range(1, b.size()):
		if (b[i - 1] < 0.0) != (b[i] < 0.0):
			z += 1
	return z

## 绝对值最大样本的下标 —— "起始瞬态"断言就看它落在波形前面还是后面。
func argmax_of(id: String) -> int:
	var b: PackedFloat32Array = _decode(id)
	var best_i: int = -1
	var best_v: float = -1.0
	for i in b.size():
		var a: float = absf(b[i])
		if a > best_v:
			best_v = a
			best_i = i
	return best_i

## 起始瞬态之后的位置 → 见 `argmax_of()`。
## 宽频含量：|x[i] - x[i-1]| > 0.02×peak 的样本占比。
## ⚠ 这是"**不是纯正弦**"的判据：22050Hz 下200Hz 纯正弦的相邻差上限只有
##   peak×2π·200/22050 ≈ peak×0.057，而宽带噪声的相邻差可以顶到 2×peak。
##   纯正弦 → 该值≈0；噪声/多层叠加 → 显著 >0。
func hf_ratio_of(id: String) -> float:
	var b: PackedFloat32Array = _decode(id)
	var n: int = b.size()
	if n < 2:
		return 0.0
	var pk: float = 0.0
	for v in b:
		pk = maxf(pk, absf(v))
	if pk <= 0.0001:
		return 0.0
	var thr: float = 0.02 * pk
	var hit: int = 0
	for i in range(1, n):
		if absf(b[i] - b[i - 1]) > thr:
			hit += 1
	return float(hit) / float(n - 1)

## 从 AudioStreamWAV 的 PCM 字节反解出归一化波形（-1..1）。
## ⚠ 刻意**不**读预渲染时的浮点数组：这里读到的是"真正送进声卡的那串字节"，
##   量化截断也会一并暴露出来。
func _decode(id: String) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var st: AudioStreamWAV = _lib.get(id, null)
	if st == null:
		return out
	var n: int = st.data.size() / 2
	out.resize(n)
	for i in n:
		out[i] = float(st.data.decode_s16(i * 2)) / 32768.0
	return out

# ----------------------------------------------------------------------
# 限流 / 播放池
# ----------------------------------------------------------------------

## 同帧重复 or 距上次不足 MIN_REPLAY_MS → 吞掉。
func _throttled(id: String) -> bool:
	var f: int = Engine.get_process_frames()
	if int(_last_frame.get(id, -1)) == f:
		return true
	var ms: int = Time.get_ticks_msec()
	if ms - int(_last_ms.get(id, -100000)) < MIN_REPLAY_MS:
		return true
	return false

## 取一个播放器：同一 id 优先复用"上一次那个"（顺带 stop = 同类切断）。
func _claim_player(id: String) -> AudioStreamPlayer:
	var prev: AudioStreamPlayer = _owner.get(id, null)
	if prev != null and is_instance_valid(prev) and String(_owner_of.get(prev, "")) == id:
		if prev.playing:
			prev.stop()
		return prev
	var pl: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	_owner[id] = pl
	_owner_of[pl] = id
	return pl

func _jitter_factor(on: bool) -> float:
	if not on:
		return 1.0
	return _ensure_jr().randf_range(1.0 - PITCH_JITTER, 1.0 + PITCH_JITTER)

# ----------------------------------------------------------------------
# 构建：总线 + 播放池 + 预渲染
# ----------------------------------------------------------------------

func _ensure_built() -> void:
	if not _built:
		_jr = _ensure_jr()
		_build()

func _build() -> void:
	_ensure_bus()
	_build_pool()
	_lib.clear()
	_lib["pistol_fire"] = _wav(_synth_pistol())
	_lib["smg_fire"] = _wav(_synth_smg())
	_lib["shotgun_fire"] = _wav(_synth_shotgun())
	_lib["hit_flesh"] = _wav(_synth_hit_flesh())
	_lib["hit_wall"] = _wav(_synth_hit_wall())
	_lib["enemy_die_zombie"] = _wav(_synth_die_zombie())
	_lib["enemy_die_merc"] = _wav(_synth_die_merc())
	_lib["player_hurt"] = _wav(_synth_player_hurt())
	_lib["pickup"] = _wav(_synth_pickup())
	_lib["crate_open"] = _wav(_synth_crate_open())
	_lib["step"] = _wav(_synth_step())
	_lib["ui_confirm"] = _wav(_synth_ui_confirm())
	_built = true

## 新增一条 SFX 总线，SFX -> Master。⚠ **Master 音量一个字都不动**（保持 0dB）。
func _ensure_bus() -> void:
	_bus_ok = false
	if AudioServer.get_bus_index(BUS_SFX) >= 0:
		_bus_ok = true
		return
	var before: int = AudioServer.bus_count
	AudioServer.add_bus()
	var idx: int = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, BUS_SFX)
	AudioServer.set_bus_send(idx, "Master")
	_bus_ok = (AudioServer.bus_count == before + 1) and (AudioServer.get_bus_index(BUS_SFX) == idx)

func _build_pool() -> void:
	if not _pool.is_empty():
		return
	for i in POOL_SIZE:
		var pl := AudioStreamPlayer.new()
		# headless 下音频后端是 Dummy，`get_bus_index` 仍可用；
		# 万一总线没建成（极端环境）就退回 Master —— **绝不因此崩掉**。
		pl.bus = BUS_SFX if AudioServer.get_bus_index(BUS_SFX) >= 0 else "Master"
		add_child(pl)
		_pool.append(pl)

## 浮点波形 -> AudioStreamWAV（16bit / 22050Hz / mono）。
func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var n: int = buf.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(round(clampf(buf[i], -1.0, 1.0) * 32767.0)))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = MIX_RATE
	s.stereo = CHANNELS == 2
	s.data = bytes
	return s

# ----------------------------------------------------------------------
# DSP 小工具（全部确定性：自带固定种子 RNG，不依赖全局 randf）
# ----------------------------------------------------------------------

func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r

## 指数衰减包络。atk = 起音样本数（>0 即为"软起音"，用来做无瞬态的音色）。
func _exp_env(n: int, atk: int, tau: float) -> PackedFloat32Array:
	var e: PackedFloat32Array = PackedFloat32Array()
	e.resize(n)
	var a: int = maxi(1, atk)
	var t: float = maxf(0.0001, tau)
	for i in n:
		if i < a:
			e[i] = float(i) / float(a)
		else:
			e[i] = exp(-(float(i - a) / float(MIX_RATE)) / t)
	return e

## 白噪声（-1..1）。
func _noise(n: int, r: RandomNumberGenerator) -> PackedFloat32Array:
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = r.randf_range(-1.0, 1.0)
	return b

## 正弦，频率从 f0 线性扫到 f1（相位累加，不用 sin(t*f) 以免频率跳变）。
func _sine_sweep(n: int, f0: float, f1: float) -> PackedFloat32Array:
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var ph: float = 0.0
	var dph: float = TAU / float(MIX_RATE)
	var prev_f: float = f0
	for i in n:
		var tt: float = float(i) / float(maxi(1, n - 1))
		var f: float = lerpf(f0, f1, tt)
		ph += dph * (prev_f + f) * 0.5
		prev_f = f
		b[i] = sin(ph)
	return b

## 锯齿（基频带颤音 + 整体下滑）—— 僵尸低吼的振源。
func _vib_saw(n: int, f0: float, f1: float, vib_hz: float, vib_depth: float) -> PackedFloat32Array:
	var b: PackedFloat32Array = PackedFloat32Array()
	b.resize(n)
	var ph: float = 0.0
	var dph: float = TAU / float(MIX_RATE)
	var prev_f: float = f0
	for i in n:
		var tt: float = float(i) / float(maxi(1, n - 1))
		var f: float = lerpf(f0, f1, tt) * (1.0 + vib_depth * sin(TAU * vib_hz * float(i) / float(MIX_RATE)))
		ph += dph * (prev_f + f) * 0.5
		prev_f = f
		b[i] = 2.0 * (ph / TAU - floorf(ph / TAU + 0.5))
	return b

## 单极低通（原地）。
func _lowpass(buf: PackedFloat32Array, cutoff: float) -> void:
	var n: int = buf.size()
	if n == 0:
		return
	var a: float = 1.0 - exp(-TAU * cutoff / float(MIX_RATE))
	var y: float = 0.0
	for i in n:
		y += a * (buf[i] - y)
		buf[i] = y

## 单极高通（原地）= 原信号 - 低通。
func _highpass(buf: PackedFloat32Array, cutoff: float) -> void:
	var n: int = buf.size()
	if n == 0:
		return
	var orig: PackedFloat32Array = buf.duplicate()
	_lowpass(buf, cutoff)
	for i in n:
		buf[i] = orig[i] - buf[i]

## Chamberlin 状态变量带通（中心频率随时间上滑）—— 木质吱呀的振源。
## ⚠ 稳定前提 fc < MIX_RATE/4 ≈ 5512Hz；本文件所有取值都远低于它。
func _svf_band(buf: PackedFloat32Array, f0: float, f1: float, q: float) -> void:
	var n: int = buf.size()
	if n <= 1:
		return
	var low: float = 0.0
	var band: float = 0.0
	var damp: float = minf(2.0 * (1.0 - pow(q, 0.25)), 1.4)
	for i in n:
		var tt: float = float(i) / float(n - 1)
		var f: float = 2.0 * sin(PI * lerpf(f0, f1, tt) / float(MIX_RATE))
		var high: float = buf[i] - q * low - damp * band
		band += f * high
		low += f * band
		buf[i] = band

## 按设计峰值缩放（**不自动归一化**）—— 相对响度是**设计出来的**，不是算法副产品。
## ⚠ 全零输入（反向验证用）时原样返回，不做除零。
func _scale_peak(buf: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var pk: float = 0.0
	for v in buf:
		pk = maxf(pk, absf(v))
	if pk <= 0.0001:
		return buf
	var k: float = target / pk
	for i in buf.size():
		buf[i] = buf[i] * k
	return buf

# ----------------------------------------------------------------------
# 12 个音效的合成配方
# 【通用手法】噪声爆（激励）→ 滤波（音色）→ 包络（时值）→ 分层叠加（体量）
# 【刻意区分】每个音效在「时长 / 峰值 / 亮度（过零率） / 起音形态」四个维度上
#   至少有一个维度与其他音效显著不同 —— 否则玩家会听成"同一个音"。
#   `--verify-sfx` ② 就是逐条钉死这四个维度。
# ----------------------------------------------------------------------

## 手枪：短促干脆。
## 配方 = 极短高频瞬态(click) + 中频噪声体(爆) + 190→95Hz 下滑低频(手上的重量)。
## 起音 atk=0 → argmax 落在最前面 → 模拟"冲击"。
func _synth_pistol() -> PackedFloat32Array:
	var n: int = 3528                     # 0.160s
	var r: RandomNumberGenerator = _rng(1001)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var click: PackedFloat32Array = _noise(n, r)
	_highpass(click, 2600.0)
	var e_click: PackedFloat32Array = _exp_env(n, 0, 0.004)
	var body: PackedFloat32Array = _noise(n, r)
	_lowpass(body, 1800.0)
	var e_body: PackedFloat32Array = _exp_env(n, 0, 0.030)
	var thump: PackedFloat32Array = _sine_sweep(n, 190.0, 95.0)
	var e_thump: PackedFloat32Array = _exp_env(n, 0, 0.055)
	for i in n:
		out[i] = click[i] * e_click[i] * 0.85 \
			+ body[i] * e_body[i] * 0.55 \
			+ thump[i] * e_thump[i] * 0.40
	return _scale_peak(out, 0.85)

## 冲锋枪：更快更轻。
## 配方同手枪但整体上移：瞬态更短(0.005 vs 0.004 的高频更多)、低频体抬到 300→210Hz、
## 时长砍到 0.090s、峰值 0.62 → 听起来"更快更轻"而不是"同一把枪"。
func _synth_smg() -> PackedFloat32Array:
	var n: int = 1984                     # 0.090s
	var r: RandomNumberGenerator = _rng(1002)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var crack: PackedFloat32Array = _noise(n, r)
	_highpass(crack, 1500.0)
	var e_crack: PackedFloat32Array = _exp_env(n, 0, 0.005)
	var body: PackedFloat32Array = _noise(n, r)
	_lowpass(body, 2400.0)
	var e_body: PackedFloat32Array = _exp_env(n, 0, 0.016)
	var thump: PackedFloat32Array = _sine_sweep(n, 300.0, 210.0)
	var e_thump: PackedFloat32Array = _exp_env(n, 0, 0.026)
	for i in n:
		out[i] = crack[i] * e_crack[i] * 0.72 \
			+ body[i] * e_body[i] * 0.50 \
			+ thump[i] * e_thump[i] * 0.26
	return _scale_peak(out, 0.62)

## 霰弹枪：最重、低频冲击最强。
## 配方 = 128→52Hz 主Boom + 66→41Hz 超低频 sub(最长 tau=0.170s) + 宽频爆炸噪声 + 尖锐瞬态。
## 时长 0.320s（全库最长）、峰值 1.0（最响）、低频能量占比最高 → "重武器更响更沉"。
func _synth_shotgun() -> PackedFloat32Array:
	var n: int = 7056                     # 0.320s
	var r: RandomNumberGenerator = _rng(1003)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var boom: PackedFloat32Array = _sine_sweep(n, 128.0, 52.0)
	var e_boom: PackedFloat32Array = _exp_env(n, 0, 0.115)
	var sub: PackedFloat32Array = _sine_sweep(n, 66.0, 41.0)
	var e_sub: PackedFloat32Array = _exp_env(n, 0, 0.170)
	var blast: PackedFloat32Array = _noise(n, r)
	_lowpass(blast, 2600.0)
	var e_blast: PackedFloat32Array = _exp_env(n, 0, 0.055)
	var crack: PackedFloat32Array = _noise(n, r)
	_highpass(crack, 2800.0)
	var e_crack: PackedFloat32Array = _exp_env(n, 0, 0.006)
	for i in n:
		out[i] = boom[i] * e_boom[i] * 0.62 \
			+ sub[i] * e_sub[i] * 0.55 \
			+ blast[i] * e_blast[i] * 0.50 \
			+ crack[i] * e_crack[i] * 0.40
	return _scale_peak(out, 1.0)

## 命中血肉：湿润打击感。
## 配方 = 两级低通(620Hz ×2)的噪声(极闷、无高频"脆"感) + 165→88Hz 下滑低频。
## ⚠ **软起音 atk=90**（≈4ms）→ 首样本不是峰值 → 与三把枪的瞬态形成对比，
##   玩家能听出"打中了"而不是"又开了一枪"。
func _synth_hit_flesh() -> PackedFloat32Array:
	var n: int = 2866                     # 0.130s
	var r: RandomNumberGenerator = _rng(2002)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var wet: PackedFloat32Array = _noise(n, r)
	_lowpass(wet, 620.0)
	_lowpass(wet, 620.0)
	var e_wet: PackedFloat32Array = _exp_env(n, 90, 0.032)
	var thud: PackedFloat32Array = _sine_sweep(n, 165.0, 88.0)
	var e_thud: PackedFloat32Array = _exp_env(n, 40, 0.050)
	for i in n:
		out[i] = wet[i] * e_wet[i] * 0.75 + thud[i] * e_thud[i] * 0.45
	return _scale_peak(out, 0.55)

## 命中硬物（墙）：硬质撞击。
## 配方 = 2200Hz 高通噪声爆(tau=0.009，极短"咔") + 两个衰减正弦泛音(2450/3680Hz)。
## 与 hit_flesh 的对比在**过零率**上最明显：这里高频泛音 → 亮度远高于血肉那一声。
func _synth_hit_wall() -> PackedFloat32Array:
	var n: int = 2205                     # 0.100s
	var r: RandomNumberGenerator = _rng(2003)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var crack: PackedFloat32Array = _noise(n, r)
	_highpass(crack, 2200.0)
	var e_crack: PackedFloat32Array = _exp_env(n, 0, 0.009)
	var t1: PackedFloat32Array = _sine_sweep(n, 2450.0, 1980.0)
	var e1: PackedFloat32Array = _exp_env(n, 0, 0.030)
	var t2: PackedFloat32Array = _sine_sweep(n, 3680.0, 3120.0)
	var e2: PackedFloat32Array = _exp_env(n, 0, 0.018)
	for i in n:
		out[i] = crack[i] * e_crack[i] * 0.70 \
			+ t1[i] * e1[i] * 0.42 \
			+ t2[i] * e2[i] * 0.26
	return _scale_peak(out, 0.70)

## 僵尸死亡：低吼。
## 配方 = 带颤音的锯齿 118→74Hz（三次谐波天然产生"粗粝低吼"）→ 1100Hz 低通
##   + 620→380Hz 带通"喉咙噪声"。
## ⚠ **慢起音 atk=900（≈41ms）** —— 全库最慢的起音，模拟"倒下时才发出声"。
func _synth_die_zombie() -> PackedFloat32Array:
	var n: int = 12127                    # 0.550s
	var r: RandomNumberGenerator = _rng(3006)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var growl: PackedFloat32Array = _vib_saw(n, 118.0, 74.0, 5.5, 0.35)
	_lowpass(growl, 1100.0)
	var e_growl: PackedFloat32Array = _exp_env(n, 900, 0.200)
	var throat: PackedFloat32Array = _noise(n, r)
	_svf_band(throat, 620.0, 380.0, 0.5)
	var e_throat: PackedFloat32Array = _exp_env(n, 1200, 0.130)
	for i in n:
		out[i] = growl[i] * e_growl[i] * 0.60 + throat[i] * e_throat[i] * 0.30
	return _scale_peak(out, 0.75)

## 佣兵死亡：短促。
## 配方 = 320→150Hz 快速下滑锯齿(带 7Hz 颤音 = 呛气) + 1200Hz 高通噪声爆。
## 与僵尸对比：**时长 0.200s vs 0.550s、起音 atk=60 vs 900、频带高一个八度**。
func _synth_die_merc() -> PackedFloat32Array:
	var n: int = 4410                     # 0.200s
	var r: RandomNumberGenerator = _rng(3007)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var gasp: PackedFloat32Array = _vib_saw(n, 320.0, 150.0, 7.0, 0.22)
	_lowpass(gasp, 1700.0)
	var e_gasp: PackedFloat32Array = _exp_env(n, 60, 0.065)
	var hit: PackedFloat32Array = _noise(n, r)
	_highpass(hit, 1200.0)
	var e_hit: PackedFloat32Array = _exp_env(n, 0, 0.012)
	for i in n:
		out[i] = gasp[i] * e_gasp[i] * 0.62 + hit[i] * e_hit[i] * 0.34
	return _scale_peak(out, 0.65)

## 玩家受伤：闷哼。
## 配方 = 205→158Hz 基频下滑 + 2/3 次谐波(700/1150Hz 附近的"声道"感)
##   + 900Hz 带通(把整体闷住) + 极少量气声噪声；**软起音 atk=420**。
## ⚠ 与 pistol_fire 的波形差异靠三重保证钉死（防"复制粘贴忘改参数"）：
##   ① 时长 0.300s ≠ 0.160s ② 软起音（argmax 靠后）③ 带通后过零率大幅降低。
func _synth_player_hurt() -> PackedFloat32Array:
	var n: int = 6615                     # 0.300s
	var r: RandomNumberGenerator = _rng(2004)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var f1: PackedFloat32Array = _sine_sweep(n, 205.0, 158.0)
	var f2: PackedFloat32Array = _sine_sweep(n, 410.0, 316.0)
	var f3: PackedFloat32Array = _sine_sweep(n, 615.0, 474.0)
	var breath: PackedFloat32Array = _noise(n, r)
	_lowpass(breath, 1400.0)
	var e_breath: PackedFloat32Array = _exp_env(n, 700, 0.090)
	var g: PackedFloat32Array = PackedFloat32Array()
	g.resize(n)
	for i in n:
		g[i] = f1[i] * 0.60 + f2[i] * 0.26 + f3[i] * 0.14 + breath[i] * e_breath[i] * 0.16
	_svf_band(g, 900.0, 640.0, 0.55)
	var e_g: PackedFloat32Array = _exp_env(n, 420, 0.100)
	for i in n:
		out[i] = g[i] * e_g[i]
	return _scale_peak(out, 0.70)

## 拾取：轻脆。
## 配方 = 880Hz + 1318Hz(纯律五度)两声正弦铃音 + 3000Hz 高通微瞬态。
## 纯正弦 + 高音区 → 玩家听成"清脆的 UI 反馈"而不是"又一声枪响"。
func _synth_pickup() -> PackedFloat32Array:
	var n: int = 3087                     # 0.140s
	var r: RandomNumberGenerator = _rng(4001)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var b1: PackedFloat32Array = _sine_sweep(n, 880.0, 884.0)
	var e1: PackedFloat32Array = _exp_env(n, 40, 0.055)
	var b2: PackedFloat32Array = _sine_sweep(n, 1318.0, 1324.0)
	var e2: PackedFloat32Array = _exp_env(n, 40, 0.075)
	var click: PackedFloat32Array = _noise(n, r)
	_highpass(click, 3000.0)
	var e_click: PackedFloat32Array = _exp_env(n, 0, 0.004)
	for i in n:
		out[i] = b1[i] * e1[i] * 0.55 \
			+ b2[i] * e2[i] * 0.38 \
			+ click[i] * e_click[i] * 0.18
	return _scale_peak(out, 0.45)

## 开箱：木质吱呀。
## 配方 = ① 150→92Hz 下滑正弦"闷响"(箱盖被掀起) + ② 带通噪声 420→1150Hz 上滑
##   + ③ 尾部 2000Hz 高通"木纤维"碎响(2.4k 样本之后才进来 = 吱呀拖尾)。
## 吱呀的"嘎吱"感来自**带通中心频率随时间上滑**（模拟木头受力形变）。
func _synth_crate_open() -> PackedFloat32Array:
	var n: int = 9922                     # 0.450s
	var r: RandomNumberGenerator = _rng(4002)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var knock: PackedFloat32Array = _sine_sweep(n, 150.0, 92.0)
	var e_knock: PackedFloat32Array = _exp_env(n, 0, 0.045)
	var creak: PackedFloat32Array = _noise(n, r)
	_svf_band(creak, 420.0, 1150.0, 0.38)
	var e_creak: PackedFloat32Array = _exp_env(n, 60, 0.160)
	var fiber: PackedFloat32Array = _noise(n, r)
	_highpass(fiber, 2000.0)
	var e_fiber: PackedFloat32Array = _exp_env(n, 2400, 0.090)
	for i in n:
		out[i] = knock[i] * e_knock[i] * 0.55 \
			+ creak[i] * e_creak[i] * 0.62 \
			+ fiber[i] * e_fiber[i] * 0.22
	return _scale_peak(out, 0.60)

## 脚步（R-133）：运动鞋踩硬地面。
## 配方（三层叠加）=
##   ① 1800~3500Hz 带通噪声"啪"（橡胶鞋底撞地，**宽带锐瞬态**），
##   ② 350~900Hz 带通噪声"折"（EVA 鞋底受压形变，**中频体**），
##   ③ 130→75Hz 极短正弦下滑"咚"（脚跟着地的**亚低音冲击**，仅前 50ms 显著）。
## 三层全用 _rng(4003)（与 R-114 同种子）→ 回归仍可逐位复现。
## ⚠ **峰值 0.55（高于 R-114 的 0.28）**：原版太"垫底"、与"运动鞋"心理声学不一致，
##   新版把宽带 slap 抬上来 → hf_ratio 必 > 0.10（--verify-sfx ②-f 钉死）。
## ⚠ **时长 0.120s（高于 R-114 的 0.075s）**：原版被玩家反馈"像走在地毯上"，
##   新版延长的部分是"啪"后的极低电平残响，argmax 仍 < 5%（②-g 钉死锐瞬态）。
func _synth_step() -> PackedFloat32Array:
	var n: int = 2646                     # 0.120s
	var r: RandomNumberGenerator = _rng(4003)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	# ① slap：宽带高频"橡胶拍地"
	var slap: PackedFloat32Array = _noise(n, r)
	_svf_band(slap, 1800.0, 3500.0, 0.50)
	var e_slap: PackedFloat32Array = _exp_env(n, 0, 0.008)
	# ② flex：中频"鞋底形变"
	var flex: PackedFloat32Array = _noise(n, r)
	_svf_band(flex, 350.0, 900.0, 0.55)
	var e_flex: PackedFloat32Array = _exp_env(n, 30, 0.024)
	# ③ thump：极短亚低音"脚跟冲击"
	var thump: PackedFloat32Array = _sine_sweep(n, 130.0, 75.0)
	var e_thump: PackedFloat32Array = _exp_env(n, 0, 0.040)
	for i in n:
		out[i] = slap[i] * e_slap[i] * 0.58 \
			+ flex[i] * e_flex[i] * 0.42 \
			+ thump[i] * e_thump[i] * 0.32
	return _scale_peak(out, 0.55)

## UI 确认：中性短音。
## 配方 = 659Hz(E5) 与 988Hz(B5) 两声纯正弦，软起音 atk=70，第二声延后 260 样本进入。
## ⚠ 刻意选**纯正弦、无噪声**：UI 音应该是"干净的中性反馈"，
##   一旦掺噪声就会被误认成世界里的枪声/打击声。
func _synth_ui_confirm() -> PackedFloat32Array:
	var n: int = 2425                     # 0.110s
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(n)
	var a: PackedFloat32Array = _sine_sweep(n, 659.0, 661.0)
	var e_a: PackedFloat32Array = _exp_env(n, 70, 0.050)
	var b: PackedFloat32Array = _sine_sweep(n, 988.0, 992.0)
	var e_b: PackedFloat32Array = _exp_env(n, 260, 0.055)
	for i in n:
		out[i] = a[i] * e_a[i] * 0.60 + b[i] * e_b[i] * 0.45
	return _scale_peak(out, 0.40)
