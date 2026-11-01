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
| `tests/` | Python 测试 + 探针在模拟会话里的测试（假 `chef` + 假引擎） |

MDL3 版和原版的补丁文件（含 BF5 音频）**没有**放进本仓库。

## 开发

```bash
tests/run_all.sh                        # 全部测试（需要 python3 和 Lua 5.1）
python3 -I tools/pack.py probe/mod.json dist
```

要在测试里同时验证"能逐字节重建真实 mod 的补丁"，把补丁文件路径给 `HD2_FIXTURE_PATCHES`（用冒号分隔）。
用 Chef 自带的模拟器跑探针（我没能运行它，见下）：在 Chef 仓库里 `python3 tools/modsim/modsim.py <本仓库>/probe/mod.json`。

## 验证状态

已验证：

- 补丁写入器：5 个资源哈希向量吻合（含 Chef 公布的 `boot`、`core_1` 和两个真实 mod 的资源 ID）；
  能把用户上传的两个真实 Lua 补丁**逐字节重建**。打好的 zip 是确定性的。
- 探针：Lua 5.1 语法通过；在自写的模拟环境里 8 组场景、85 项检查全过（正常任务、引擎拒绝一切、旧版加载器、垃圾数据、日志洪水、
  阶段反复报错、房主有几百个对象、尸体排在前面）。模拟环境把探针关在 Chef 文档规定的受限全局环境里，误用 `print`/`require`/`debug` 会直接失败。
  还做过变异测试：故意把关键逻辑改坏（尸体判定、移动判定、字符串脱敏、跨世界保留、阶段暂停），检查都能抓到。

**没有**验证：

- 没有在真实游戏里、也没有在真实的 Chef Shared Loader 里运行过。
- Chef 自带的模拟器没跑：这个环境拒绝运行外部仓库里的代码。
- 这个 zip 能不能被你的 Arsenal / HD2 Mod Manager 正常导入、Chef 能不能识别，需要你装一次才知道。
