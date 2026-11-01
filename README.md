# HD2-BF5-Kill-Feedback：Chef Shared Loader 版

[Battlefield 5 Hit and Kill Feedback](https://www.nexusmods.com/helldivers2/mods/16927)（Helldivers 2 的 BF5 风格命中/击杀反馈）的 **Chef Shared Loader** 版。

## 现状：探针阶段，还不是完整 mod

MDL3 版（v2.0.1）的三样核心数据，在 Chef 下**没有来源**：

| MDL3 版从哪里拿 | Chef（纯 Lua 5.1，没有 ffi，读不了内存）下 |
|---|---|
| 击杀归属、命中/伤害事件：MDL3 原生的 HD2 Data Hub | 没有 |
| 自定义音效：MDL3.audio（原生 XAudio2） | 没有音频接口 |
| 敌人分级表（light/medium/heavy/flying） | **有**，同一套单位资源 ID，可直接复用 |

所以不能直接移植。第一步是弄清游戏自己的 Lua 层能看到什么：[`probe/`](probe/README.md) 是一个只读的 Chef 探针，
装上打一局，把日志文件发回，再决定 Chef 版能做到什么程度。详细依据见 [`docs/chef-feasibility.md`](docs/chef-feasibility.md)。

**第一轮（探针 0.1.0）已经在真实游戏里跑过**，结果见 [`docs/probe-run-1.md`](docs/probe-run-1.md)：
敌人死亡的时刻能精确得到（进入死亡动画状态，比状态机消失早 5 秒）；声音没找到路径；击杀凭证和命中信号这一轮没回答到（探针只看了 347 个游戏对象里的 40 个）。
探针 0.2.0 针对这些做了修改。

## 现在要做的事

1. 按 [`probe/README.md`](probe/README.md) 安装 [`dist/BFV-Chef-Probe-0.2.0.zip`](dist/BFV-Chef-Probe-0.2.0.zip)（先卸掉 0.1.0），做房主打一局，对大只敌人持续点射并按 F7/F6 标记。
2. 把 `bfv_probe.log`、`bfv_probe_api.txt`、`bfv_probe_summary.txt`（和 `chef_loader.log`）发回。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `probe/` | 探针 mod：`bfv_chef_probe.lua`、`mod.json`、使用说明 |
| `dist/` | 打好的 mod 管理器 zip（与源码逐字节对应，构建是确定性的） |
| `docs/chef-feasibility.md` | 为什么现在不能直接移植、依据、探针要回答的问题（和第一轮的答案） |
| `docs/probe-run-1.md` | 探针 0.1.0 第一次真机运行的数据和结论，0.2.0 为什么这样改 |
| `tools/hd2patch.py` | 资源哈希（MurmurHash64A）和 Lua 补丁文件的读写 |
| `tools/pack.py` | 把 `mod.json` + Lua 打成 Arsenal / HD2 Mod Manager 的 zip |
| `tools/inspect_patch.py` | 只读地查看/解出任何补丁文件（比如 MDL3 包里的 Lua） |
| `tools/extract_tiers.py` | 从 MDL3 版的 Lua 里提取敌人分级表 |
| `tools/modsim_extend.py` | 给 **Chef 模拟器的复制品** 加上按第一轮日志重建的战场：走动的敌人、5 秒的死亡状态、附件、短命单位、房主的几百个游戏对象（`tests/chef_sim.sh` 用） |
| `tests/` | `chef_sim.sh`：在**真实的 Chef 加载器**（它自带的模拟器）上跑探针，是主要检查；`run_all.sh`：Python 测试 + 探针在自写模拟环境里的场景（假 `chef` + 假引擎），是快速检查 |

MDL3 版和原版的补丁文件（含 BF5 音频）**没有**放进本仓库。

## 开发

```bash
tests/chef_sim.sh <Chef-Shared-Loader 仓库路径>   # 主要检查：在真实的 Chef 加载器上跑探针（需要 python3、Pillow、lua5.1）
tests/run_all.sh                        # 快速检查：Python 测试 + Lua 语法 + 探针在自写模拟环境里的 12 组场景（需要 python3 和 Lua 5.1）
python3 -I tools/pack.py probe/mod.json dist
```

`tests/chef_sim.sh` 会先把 Chef 仓库**复制**到临时目录，用 `tools/modsim_extend.py` 给复制品里的模拟器加上会走动的敌人、动画状态机和游戏对象，
再用 Chef 自带的 `tools/modsim/modsim.py` 跑三种场景（普通任务、第二个玩家加入且打开"读别人的对象"、任务中途换新世界）。它运行的是 Chef 仓库里的代码（模拟器、构建脚本、加载器本体），运行前请先读一遍。
要在测试里同时验证"能逐字节重建真实 mod 的补丁"，把补丁文件路径给 `HD2_FIXTURE_PATCHES`（用冒号分隔）。

## 验证状态

已验证：

- **0.1.0 在真实游戏里跑过**（你那一局）：加载器启动它，0 错误，没有拦截，开销平均 0.04～0.22 毫秒/帧；
  收集到的数据见 `docs/probe-run-1.md`。
- **0.2.0 在真实的 Chef Shared Loader 1.4.1 上跑通**（Chef 自带的模拟器 + 按第一轮日志重建的战场），`tests/chef_sim.sh` 的 67 项检查全过：
  加载器识别并启动探针，健康表 `running`、0 错误，没有调用被拒绝或拦截；进入死亡状态的 `DEATH`（含准星证据和游戏对象）、
  5 秒后的 `UNIT … dying=5.0`、`DEATH cancel`、`DEATH learned`、忽略表和自动忽略、`SIGKIND`、`AIMOBJ` 里一只 600 血的敌人四发子弹的 600→440→280→120→-40、
  玩家对象计数器、噪声字段的静音、`NEW`/`GONE`、第二个玩家加入时的"读别人的对象"、任务中途换世界（访问旧世界的单位在模拟器里算崩溃）都有对应检查。
  真实加载器此前还抓出过一个我自己的测试环境没覆盖到的缺陷（`chef.capabilities` 是只读代理），已修。
- 变异测试：故意把关键逻辑改坏（死亡种子、忽略表、unit↔对象查询、全对象扫描、噪声静音、世界切换时的重置、撤销、学习、布局↔种类记录），
  `tests/chef_sim.sh` 的检查都能抓到（一个等价变异除外：`link_unit` 里对单位存活的二次检查，调用前还有一次）。
- 自写的模拟环境里 12 组场景、132 项检查全过（含全部对象扫描的每帧读数上限、他人对象默认不读、死亡状态种子/撤销/学习、配额、噪声静音、文字替身、日志预算优先级）。
- 补丁写入器：5 个资源哈希向量吻合（含 Chef 公布的 `boot`、`core_1` 和两个真实 mod 的资源 ID）；
  能把用户上传的两个真实 Lua 补丁**逐字节重建**。打好的 zip 是确定性的。

**没有**验证：

- 模拟器里的战场是我按日志重建的，**游戏对象字段的含义是我猜的**（敌人血量在字段 22、玩家击杀计数在某个字段），
  `UnitSynchronizer.unit_to_game_object_id` 的参数形式也是猜的。真实游戏的这些接口给出什么，正是第二轮要回答的问题。
- 0.2.0 在真实游戏里还没有跑过：全部对象扫描的开销（0.1.0 每 0.2 秒最多读 8 个对象，0.2.0 每帧最多读 14 个，另有最多 16 个独立对象每 0.2 秒读一次）、
  unit synchronizer 查询会不会让游戏出事。
- 这个 zip 能不能被你的 Arsenal / HD2 Mod Manager 正常导入：0.1.0 的 zip 你已经导入过，打包方式相同，但 0.2.0 的这个文件没人试过。
