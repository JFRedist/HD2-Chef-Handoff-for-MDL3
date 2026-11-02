# HD2-BF5-Kill-Feedback：Chef 与 MDL3 的工作笔记和工具

这个仓库开始是为 [Battlefield 5 Hit and Kill Feedback](https://www.nexusmods.com/helldivers2/mods/16927)（Helldivers 2 的 BF5 风格命中/击杀反馈）做 **Chef Shared Loader** 版。
调研的结果是：Chef 下做不了（见下），BF5 反馈留在它的 MDL3 版上。现在仓库里有两样东西：

1. **[`handoff/`](handoff/README.md)：让 Chef 和 HUDdle 在 MDL3 旁边运行的小 mod（当前的目标）。**
2. [`probe/`](probe/README.md)：做 Chef 版 BF5 反馈时用的只读探针，结果和数据都在 `docs/`，留作记录。

## 当前：Chef Hand-off for MDL3

HUDdle（Nexus 18108）是 Chef 的 addon，没有 MDL3 版；BF5 反馈要 MDL3。游戏只运行一个 `boot`，Chef 和 MDL3 抢它，所以默认只能有一个工作。
Chef 的文档给其它加载器留了交接的办法，[`handoff/chef_handoff.lua`](handoff/chef_handoff.lua) 在 MDL3 这一边做它：进游戏 6 秒后把游戏交给 Chef。
MDL3 照常运行它的 mod，Chef 运行 HUDdle 和别的 Chef mod。原理、验证和风险见 [`docs/chef-under-mdl3.md`](docs/chef-under-mdl3.md)。

**要做的事：**

1. 按 [`handoff/README.md`](handoff/README.md) 安装 [`dist/Chef-Hand-off-for-MDL3-0.1.0.zip`](dist/Chef-Hand-off-for-MDL3-0.1.0.zip)，**MDL3 的优先级要比 Chef 高**（Arsenal 里怎么摆看它的 First / Last mod highest priority 设置，说明里有），Purge 再 Deploy。
2. 启动游戏，在标题画面停 10 秒，进一局任务看 HUDdle。
3. 不管成不成，把 `%APPDATA%\Arrowhead\Helldivers2\` 里的 `chef_handoff.log` 和 `chef_loader.log` 发回来。

**真机结果（MDL3 3.0.0-dev.29）**：交接成功，HUDdle 在任务里出现。还没解决的：任务中按 ESC 回飞船会闪退（原因待隔离，见 `docs/chef-under-mdl3.md`）；Treasure Radar 这类没有 `HD2-Requires` 头的 Chef mod 被 Chef 跳过（已知，修法还没做）；MDL3 的 mod（BF5）还没和它一起试过。

## 为什么 BF5 反馈没有 Chef 版

MDL3 版（v2.0.1）的三样核心数据，在 Chef 下**没有来源**：

| MDL3 版从哪里拿 | Chef（纯 Lua 5.1，没有 ffi，读不了内存）下 |
|---|---|
| 击杀归属、命中/伤害事件：MDL3 原生的 HD2 Data Hub | 没有 |
| 自定义音效：MDL3.audio（原生 XAudio2） | 没有音频接口 |
| 敌人分级表（light/medium/heavy/flying） | **有**，同一套单位资源 ID，可直接复用 |

探针在真实游戏里跑过一轮（0.1.0），结果见 [`docs/probe-run-1.md`](docs/probe-run-1.md)：敌人死亡的时刻能精确得到（进入死亡动画状态，比状态机消失早 5 秒）；
声音没找到路径；击杀凭证和命中信号没有回答到。探针 0.2.0 针对这些改过，在模拟器里验证过，没有再在真实游戏里跑，因为这条路已经放弃。依据见 [`docs/chef-feasibility.md`](docs/chef-feasibility.md)。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `handoff/` | Chef 交接 addon：`chef_handoff.lua`、`mod.json`、使用说明 |
| `probe/` | Chef 探针 mod：`bfv_chef_probe.lua`、`mod.json`、使用说明 |
| `dist/` | 打好的 mod 管理器 zip（与源码逐字节对应，构建是确定性的） |
| `docs/chef-under-mdl3.md` | 在 MDL3 下运行 HUDdle：问题、交接办法、验证、风险 |
| `docs/chef-feasibility.md` | 为什么 BF5 反馈没有 Chef 版：依据，探针要回答的问题和第一轮的答案 |
| `docs/probe-run-1.md` | 探针 0.1.0 第一次真机运行的数据和结论 |
| `tools/hd2patch.py` | 资源哈希（MurmurHash64A）和 Lua 补丁文件的读写 |
| `tools/pack.py` | 把 `mod.json` + Lua 打成 Arsenal / HD2 Mod Manager 的 zip |
| `tools/inspect_patch.py` | 只读地查看/解出任何补丁文件（比如 MDL3 包里的 Lua） |
| `tools/extract_tiers.py` | 从 MDL3 版的 Lua 里提取敌人分级表 |
| `tools/modsim_extend.py` | 给 **Chef 模拟器的复制品** 加上按第一轮日志重建的战场（探针的测试用） |
| `tests/` | `run_all.sh`：Python 测试 + 探针和交接 addon 在自写假环境里的测试（快速检查）；`handoff_sim.sh`、`chef_sim.sh`：在**真实的 Chef 加载器**（它自带的模拟器）上分别跑交接 addon 和探针（主要检查） |

MDL3 版和原版的补丁文件（含 BF5 音频）、HUDdle 的代码**没有**放进本仓库。

## 开发

```bash
tests/handoff_sim.sh <Chef-Shared-Loader 仓库路径>   # 主要检查：交接 addon 在真实的 Chef 上，假 MDL3 启动器下（需要 python3、Pillow、lua5.1）
tests/chef_sim.sh <Chef-Shared-Loader 仓库路径>      # 主要检查：探针在真实的 Chef 上
tests/run_all.sh                                     # 快速检查：Python 测试 + Lua 语法 + 两个 mod 在自写假环境里的测试
python3 -I tools/pack.py handoff/mod.json dist       # 打包（probe/mod.json 同理）
HUDDLE_LUA=<HUDdle 的 Lua 文件> tests/handoff_sim.sh <Chef 仓库路径>   # 可选：用你自己那份 HUDdle 再跑一遍
```

两个 `*_sim.sh` 都会先把 Chef 仓库**复制**到临时目录再运行 Chef 自带的模拟器（`tools/modsim/modsim.py`）。它们运行的是 Chef 仓库里的代码（模拟器、构建脚本、加载器本体），运行前请先读一遍。
要在测试里同时验证"能逐字节重建真实 mod 的补丁"，把补丁文件路径给 `HD2_FIXTURE_PATCHES`（用冒号分隔）。

## 验证状态

**交接 addon（0.1.0）**
- `tests/test_handoff.lua` 40 项全过（6 秒前不交接、之后一次、便条内容、状态文件、日志、`update` 链保持；Chef 没装 / 已在运行 / 上次崩溃 / 核心报错 / 各种奇怪的游戏）。
- `tests/handoff_sim.sh` 在真实的 Chef 1.4.1 上全过：三种假 MDL3 启动器（init 里启动 / boot 里启动并先普通 `require` / 自己已交接），Chef 报告被谁交接、自己的 boot stub 没运行、Chef 的 mod 启动并绘制、
  假 MDL3 的回调每帧照常运行、游戏的 `init` 恰好一次；用真实的 HUDdle 0.6.11 也能启动。
- 变异检查：故意改坏 9 处，自写测试全部抓到；模拟器测试抓到影响真实 Chef 行为的三处。
- 真机（MDL3 3.0.0-dev.29）：交接成功，HUDdle 运行正常；ESC 回飞船闪退未解决；**没有验证**：和 MDL3 的 mod 一起运行。

**探针（0.1.0 和 0.2.0）**
- 0.1.0 在真实游戏里跑过一局：0 错误，没有拦截，开销平均 0.04～0.22 毫秒/帧。
- 0.2.0 在真实的 Chef 1.4.1 上用按日志重建的战场跑通，`tests/chef_sim.sh` 67 项检查全过，自写模拟环境 12 组场景、132 项检查全过，变异检查通过。
  战场里游戏对象字段的含义和 `unit_to_game_object_id` 的参数形式是猜的，0.2.0 没有在真实游戏里跑过。

**工具**
- 补丁写入器：5 个资源哈希向量吻合（含 Chef 公布的 `boot`、`core_1` 和两个真实 mod 的资源 ID）；能把用户上传的两个真实 Lua 补丁**逐字节重建**。打好的 zip 是确定性的。
