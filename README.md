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
你装上打一局，把三个日志文件发回，再决定 Chef 版能做到什么程度。详细依据见 [`docs/chef-feasibility.md`](docs/chef-feasibility.md)。

## 现在要做的事

1. 按 [`probe/README.md`](probe/README.md) 安装 [`dist/BFV-Chef-Probe-0.1.0.zip`](dist/BFV-Chef-Probe-0.1.0.zip)，打一局并按 F6/F7 标记。
2. 把 `bfv_probe.log`、`bfv_probe_api.txt`、`bfv_probe_summary.txt`（和 `chef_loader.log`）发回。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `probe/` | 探针 mod：`bfv_chef_probe.lua`、`mod.json`、使用说明 |
| `dist/` | 打好的 mod 管理器 zip（与源码逐字节对应，构建是确定性的） |
| `docs/chef-feasibility.md` | 为什么现在不能直接移植、依据、探针要回答的问题 |
| `tools/hd2patch.py` | 资源哈希（MurmurHash64A）和 Lua 补丁文件的读写 |
| `tools/pack.py` | 把 `mod.json` + Lua 打成 Arsenal / HD2 Mod Manager 的 zip |
| `tools/inspect_patch.py` | 只读地查看/解出任何补丁文件（比如 MDL3 包里的 Lua） |
| `tools/extract_tiers.py` | 从 MDL3 版的 Lua 里提取敌人分级表 |
| `tools/modsim_extend.py` | 给 **Chef 模拟器的复制品** 加上会走动的敌人、动画状态机和游戏对象（`tests/chef_sim.sh` 用） |
| `tests/` | `run_all.sh`：Python 测试 + 探针在自写模拟环境里的测试（假 `chef` + 假引擎）；`chef_sim.sh`：在真实 Chef 加载器上跑探针 |

MDL3 版和原版的补丁文件（含 BF5 音频）**没有**放进本仓库。

## 开发

```bash
tests/run_all.sh                        # Python 测试 + Lua 语法 + 探针在自写模拟环境里的 8 组场景（需要 python3 和 Lua 5.1）
python3 -I tools/pack.py probe/mod.json dist
tests/chef_sim.sh <Chef-Shared-Loader 仓库路径>   # 在真实的 Chef 加载器上跑探针（需要 python3、Pillow、lua5.1）
```

`tests/chef_sim.sh` 会先把 Chef 仓库**复制**到临时目录，用 `tools/modsim_extend.py` 给复制品里的模拟器加上会走动的敌人、动画状态机和游戏对象，
再用 Chef 自带的 `tools/modsim/modsim.py` 跑三种场景。它运行的是 Chef 仓库里的代码（模拟器、构建脚本、加载器本体），运行前请先读一遍。
要在测试里同时验证"能逐字节重建真实 mod 的补丁"，把补丁文件路径给 `HD2_FIXTURE_PATCHES`（用冒号分隔）。

## 验证状态

已验证：

- **在真实的 Chef Shared Loader 1.4.1 上跑通**（Chef 自带的模拟器 + 我加的假战场）：加载器识别并启动探针，健康表 `running`、0 错误，
  没有任何调用被拒绝或拦截；三个输出文件都写出来了；F9 菜单、F6 标记、开火记录、准星射线、敌人对象阶段都正常；
  任务中途换世界（访问旧世界的单位在模拟器里算游戏崩溃）没有触发崩溃。
  真实加载器还抓出了一个我自己的测试环境没覆盖到的缺陷（`chef.capabilities` 是只读代理，遍历不出内容），已修，`tests/chef_sim.sh` 里有对应检查。
- 真实加载器读了**本仓库打包器**产出的补丁（与 zip 里字节一致）并启动了探针。
- 补丁写入器：5 个资源哈希向量吻合（含 Chef 公布的 `boot`、`core_1` 和两个真实 mod 的资源 ID）；
  能把用户上传的两个真实 Lua 补丁**逐字节重建**。打好的 zip 是确定性的。
- 探针逻辑：Lua 5.1 语法通过；自写的模拟环境里 8 组场景、87 项检查全过（正常任务、引擎拒绝一切、旧版加载器、垃圾数据、日志洪水、
  阶段反复报错、房主有几百个对象、尸体排在前面），环境把探针关在 Chef 文档规定的受限全局环境里。
  还做过变异测试：故意把关键逻辑改坏（尸体判定、移动判定、字符串脱敏、跨世界保留、阶段暂停），检查都能抓到。

**没有**验证：

- **没有在真实游戏里运行过。** 模拟器里的战场是假的：单位、动画状态机、玩家对象的字段都是我加的（`tools/modsim_extend.py`），
  `UnitSynchronizer.unit_to_game_object_id` 的参数形式是猜的。真实游戏的这些接口给出什么，正是探针要回答的问题。
- 游戏本身会不会接受我打出来的补丁文件头，要装进真实游戏才知道（格式已和两个真实 mod 的补丁逐字节对过）。
- 这个 zip 能不能被你的 Arsenal / HD2 Mod Manager 正常导入，需要你装一次才知道。
