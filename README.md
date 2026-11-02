# Chef Hand-off for MDL3

让 **Chef Shared Loader** 和 **MDL3** 在同一个 Helldivers 2 里一起工作的小 mod：它由 MDL3 启动，进游戏 6 秒后把游戏交给 Chef。
这样，只能在 Chef 下运行的 mod（[HUDdle](https://www.nexusmods.com/helldivers2/mods/18108)、Treasure Radar ……）
和只能在 MDL3 下运行的 mod（比如 [BF5 击杀反馈的 MDL3 版](https://www.nexusmods.com/helldivers2/mods/16927)）可以同时用。

**English.** Helldivers 2 runs only one `boot`, so Chef Shared Loader and MDL3 normally cannot both work, and Chef-only mods (HUDdle, Treasure Radar) have no MDL3 version.
This addon is started by MDL3 and, 6 seconds into the game, hands the game over to the real Chef with the hand-off that Chef's own documentation describes for other loaders.
MDL3 keeps running its mods; Chef runs the Chef mods. No code of Chef, HUDdle or MDL3 is included.
Download `Chef-Hand-off-for-MDL3-0.2.1.zip` from the Releases page (the same file is in [`dist/`](dist/Chef-Hand-off-for-MDL3-0.2.1.zip)), add it to your mod manager, enable it, and give **MDL3 a higher priority than Chef**.
**Chef Shared Loader 1.5.x needs 0.2.1 or later**: 0.2.0 let Chef run MDL3's callbacks under its new hang watchdog, which stops them when one call takes over 3 s.
Tested by the repository owner in the real game (MDL3 3.0.0-dev.29, Chef 1.4.1); 0.2.1 with Chef 1.5.1 is verified in Chef's own simulator, not yet in the game. The documentation is in Chinese; the Lua source is commented in English.

## 真机状态

作者在自己的游戏里测的：MDL3 3.0.0-dev.29，Chef Shared Loader 1.4.1，HUDdle 0.6.11，BF5 击杀反馈 MDL3 版 2.0.1，Treasure Radar 0.7.1n。

| 项目 | 结果 | 依据 |
|---|---|---|
| 交接：Chef 在 MDL3 下被启动 | 成功 | 0.1.0 的日志：`chef_handoff.log` 里 `Chef Shared Loader 1.4.1 started`，`chef_loader.log` 里 `started by MDL3 chef_handoff 0.1.0, which handed off to me` |
| HUDdle 0.6.11 | 任务里正常；一局约 8 分钟没有一条错误，约 0.7 毫秒/帧（它的预算是 1 毫秒） | 0.1.0 的日志 |
| 完成任务、正常结算回飞船 | 正常（0.1.0，一次） | 日志：任务世界 → 加载 → 飞船，退出时 `shutdown (clean)` |
| BF5 击杀反馈（MDL3 版）一起用 | 正常 | 0.2.0：作者的试玩报告，没有传日志。0.1.0 的 `MDL.log` 里它被 MDL3 启用并注册了选项；Chef 没有把它再启动一份 |
| 任务中按 ESC 回飞船 | 0.1.0 下闪退过**一次**，原因没找到，之后没有再出现；0.2.0 下没有闪退 | 0.2.0：作者的试玩报告，没有传日志 |
| Treasure Radar 这类不带 `HD2-Requires` 头的 Chef mod | 0.1.0 被 Chef 跳过（日志里 `already started by another loader (started)`）；0.2.0 起来了 | 0.2.0：作者的试玩报告（游戏里没问题）；`chef_handoff.log` 里 `taken off package.loaded, so that Chef starts them: mods/chef/treasure_radar` |
| 认出做给 Chef 的 addon（读补丁文件） | 在真机上起作用，不是靠内置名单 | 0.2.0 的 `chef_handoff.log`：`patch files read: 91 (4 addons, 2 made for Chef, 0 read errors) in 5 ms`，认出的是 Treasure Radar 和 HUDdle |
| Chef 1.5.0 / 1.5.1 | 0.2.0 和它们不兼容：Chef 把 MDL3 的回调放在它的卡死看门狗下面，一次调用超过 3 秒就判卡死并终止（评论里有人这样报告，作者转述）。**0.2.1 修了，真机还没有确认** | 在 Chef 自带的模拟器里，用真实的 1.5.1：0.2.0 下对方的更新链被 `stopped by the hang watchdog: it ran over 3 s` 终止，0.2.1 下不会；1.4.1 上两版都正常。原因、复现和限制见 [`docs/chef-under-mdl3.md`](docs/chef-under-mdl3.md) |

ESC 那次闪退没有找到原因，0.2.0 也没有做任何针对它的改动，所以只能说"没有再出现"，不能说"修好了"。顺带一个事实：闪退那一次还没有装 BF5 反馈（作者当时说还没试 MDL3 的 mod，Chef 的日志里也没有它），之后的几次都装了（详见 [`docs/chef-under-mdl3.md`](docs/chef-under-mdl3.md)）。

## 它怎么工作

1. 游戏只运行优先级最高的补丁里的 `boot`。MDL3 的优先级高，运行的就是 MDL3 的 boot；Chef 不会运行别的加载器的 boot，所以 Chef 和它的 mod 默认不工作。
2. MDL3 会启动所有带 `HD2-Addon` 头的 Lua，包括这个 mod。
3. 这个 mod 等 6 秒，然后用 Chef 文档里"给其它加载器"写明的办法（设一个便条，再 `require` Chef 的核心）把游戏交给 Chef。之后 MDL3 的 mod 照常运行，Chef 运行它自己的 mod。
4. 0.2.0 多做一步：MDL3 也会"启动"Chef 的 mod（给它们的不是 Chef，多数会报错）。没报错的（Treasure Radar）会被 Chef 当作"已经被别的加载器启动"而跳过。
   所以交接前，这个 mod 读游戏的补丁文件找出做给 Chef 的 addon，把它们从 `package.loaded` 里摘掉，让 Chef 正常启动它们。
   怎么认：带 `-- HD2-Addon:` 头的 Lua 里，再有**行首的 `local chef = ...`**（Chef 把工具表交给 addon 的惯用写法），或者 `-- HD2-Requires: chef-shared-loader` 头行，就是做给 Chef 的。规则的细节和会漏掉什么见 [`docs/chef-under-mdl3.md`](docs/chef-under-mdl3.md)。
5. 0.2.1：Chef 1.5 起，交接来的启动脚本的回调（MDL3 和它的 mod 串起来的 `update`、`render`、`shutdown`）会被 Chef 保管，在它自己的回调之后运行，并且放在它的卡死看门狗下面：一次调用超过 3 秒就判卡死，整条链被终止，MDL3 也就停了。
   所以交接时不把这些回调交给 Chef：Chef 加载期间先从全局里摘下，加载完再放回它自己的回调后面（Chef 的先，MDL3 的链后，游戏照常调用）。Chef 不再拥有、计时或终止它们。

没装 Chef，或者 Chef 已经在运行时，它什么也不做。原理、验证、风险和已知的疑点见 [`docs/chef-under-mdl3.md`](docs/chef-under-mdl3.md)。

## 安装

完整说明在 [`handoff/README.md`](handoff/README.md)。要点：

1. 你已经有 MDL3、Chef Shared Loader（1.2.0 以上；**1.5.x 要用本 mod 的 0.2.1 或更新的版本**）和要用的 mod。
2. 从本仓库的 Releases 页下载 `Chef-Hand-off-for-MDL3-0.2.1.zip`（[`dist/`](dist/Chef-Hand-off-for-MDL3-0.2.1.zip) 里是同一个文件），加进 Arsenal / HD2 Mod Manager 并启用。
3. **MDL3 的优先级要比 Chef 高**（游戏运行的 boot 必须是 MDL3 的）。Arsenal 里：设置是 *First mod highest priority* 就把 MDL3 放在 Chef 上面，是 *Last mod highest priority* 就放在下面。这和 Chef、HUDdle 的说明（要求 Chef 最高）相反。
4. Purge，再 Deploy。启动游戏，在标题画面停 10 秒以上，再进一局任务。

## 出问题时

| 现象 | 多半是 |
|---|---|
| BF5 反馈（MDL3）正常，HUDdle 没有 | 交接没成功：看 `%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log` |
| HUDdle 正常，BF5 反馈（MDL3）没有，也没有 `chef_handoff.log` | Chef 的优先级还是高的（摆反了） |
| 都没有 | 看 `chef_handoff.log` 和 `chef_loader.log` |

反馈问题时请附上 `chef_handoff.log`、`chef_loader.log` 和 `MDL.log`。`MDL.log` 每次启动都会被覆盖，闪退后先把它拷出来再重开游戏。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `handoff/` | **交接 addon**：`chef_handoff.lua`、`mod.json`、使用说明 |
| `dist/` | 打好的 mod 管理器 zip：`Chef-Hand-off-for-MDL3-0.2.1.zip`（与源码逐字节对应，构建是确定性的）。同一个文件在本仓库的 Releases 页 |
| `docs/chef-under-mdl3.md` | 在 MDL3 下运行 Chef 和 HUDdle：问题、交接办法、怎么认出做给 Chef 的 mod、三次真机结果、验证、风险 |
| `docs/nexus-page.md` | Nexus Mods 页面的文字：名称、摘要、BBCode 描述（英文，带简体中文折叠块）、文件说明、更新说明、发布前检查 |
| `promo/` | 宣传材料的源文件：`scenes.html`（宣传视频的动画）、`cover.html`（B 站封面）、`nexus-images.html`（Nexus 页面的 6 张图）、`render.js`（渲染）、`bilibili-post.md`（B 站投稿文案）。视频和图片本身不入库 |
| `docs/chef-feasibility.md`、`docs/probe-run-1.md` | 已放弃的研究：BF5 击杀反馈的 Chef 版（见下） |
| `CHANGELOG.md`、`LICENSE` | 版本记录；MIT 许可证 |
| `.github/workflows/release.yml`、`release-notes/` | 发布：见下 |
| `tools/` | `hd2patch.py`（资源哈希 MurmurHash64A 和 Lua 补丁文件的读写）、`pack.py`（把 `mod.json` + Lua 打成 Arsenal / HD2 Mod Manager 的 zip）、`inspect_patch.py`（只读地查看/解出补丁文件） |
| `tests/` | 见下 |

MDL3、Chef、HUDdle、BF5 反馈（原版和 MDL3 版）的文件**没有**放进本仓库。

## 开发与测试

```bash
tests/run_all.sh                                       # 快速检查：Python 测试 + Lua 语法 + 交接 addon 在自写假环境里的测试
tests/handoff_sim.sh <Chef-Shared-Loader 仓库路径>     # 主要检查：交接 addon 在真实的 Chef 上，假 MDL3 启动器下
python3 -I tools/pack.py handoff/mod.json dist         # 打包
HUDDLE_LUA=<HUDdle 的 Lua 文件> tests/handoff_sim.sh <Chef 仓库路径>   # 可选：用你自己那份 HUDdle 再跑一遍
```

需要 python3、Pillow（Chef 的构建用）和 lua5.1。2026-11-02 在 Chef 1.4.1（提交 `400cc03`）和 1.5.1（标签 `v1.5.1`）上的结果：

- `tests/run_all.sh`：Python 12 个测试通过（1 个因为没有给真实 mod 的补丁文件而跳过），交接 addon 80 项，全过。
- `tests/handoff_sim.sh`：58 项，在 1.4.1 和 1.5.1 上都全过。五种假 MDL3 启动器（A 在 `init` 里启动 / B 在 `boot` 里启动并先普通 `require` / E 同 B 但只留下 `package.loaded`，就是真实 MDL3 的样子 /
  F 更新链里有一次 3.6 秒的慢调用 / C 自己已交接），检查 Chef 报告被谁交接、自己的 boot stub 没运行、Chef 的 mod 启动并绘制、假 MDL3 的回调每帧照常运行且没有被看门狗终止、游戏的 `init` 恰好一次。
  再给 `HUDDLE_LUA`（真实的 HUDdle 0.6.11，不在仓库里）跑变体 D，共 62 项，全过。F 是为 1.5.x 加的：0.2.0 在 1.5.1 上过不了它（复现的就是这个），0.2.1 过得了。
- 变异检查：故意改坏交接 addon 的 27 处（0.1.0 的 9 处、0.2.0 新增的 11 处、0.2.1 新增的 7 处），自写测试全部抓到（一个防御性的等价变异除外），模拟器测试抓到影响真实 Chef 行为的那些。这是一次性的手工检查，脚本没有放进仓库。
- 补丁写入器：5 个资源哈希向量吻合（含 Chef 公布的 `boot`、`core_1` 和两个真实 mod 的资源 ID）；能把真实 mod 的 Lua 补丁逐字节重建（`HD2_FIXTURE_PATCHES` 给补丁文件路径，用冒号分隔）。打好的 zip 是确定性的。

`tests/handoff_sim.sh` 会先把 Chef 仓库**复制**到临时目录再运行 Chef 自带的模拟器（`tools/modsim/modsim.py`）。它运行的是 Chef 仓库里的代码（模拟器、构建脚本、加载器本体），运行前请先读一遍。

**发布。** 版本号在 `handoff/mod.json`。改完后重新打包进 `dist/` 并推送，再给提交打 `vX.Y.Z` 标签并推送（或者在 GitHub 的 Actions 页手动运行 *Release*，填上标签）。
工作流会先用 `tools/pack.py` 重新构建 zip，和 `dist/` 里的逐字节比较，一致才建 Release；说明取自 `release-notes/<标签>.md`。

## 研究记录：BF5 击杀反馈的 Chef 版（已放弃）

这个仓库最早是为 [Battlefield 5 Hit and Kill Feedback](https://www.nexusmods.com/helldivers2/mods/16927) 做 Chef 版。MDL3 版（v2.0.1）的三样核心数据，在 Chef 下**没有来源**：

| MDL3 版从哪里拿 | Chef（纯 Lua 5.1，没有 ffi，读不了内存）下 |
|---|---|
| 击杀归属、命中/伤害事件：MDL3 原生的 HD2 Data Hub | 没有 |
| 自定义音效：MDL3.audio（原生 XAudio2） | 没有音频接口 |
| 敌人分级表（light/medium/heavy/flying） | **有**，同一套单位资源 ID，可直接复用 |

当时写了一个只读的探针 mod（BFV Chef Probe），去看游戏自己的 Lua 层能让 Chef mod 看到什么。0.1.0 在真实游戏里跑过一轮（结果见 [`docs/probe-run-1.md`](docs/probe-run-1.md)）：敌人死亡的时刻能精确得到（进入死亡动画状态，比状态机消失早 5 秒）；声音没找到路径；击杀凭证和命中信号没有回答到。
0.2.0 针对这些改过，只在模拟器里验证过。作者随后决定改用 MDL3 版，这条路线 2026-11-01 停止，没有得出最终结论。依据见 [`docs/chef-feasibility.md`](docs/chef-feasibility.md)。

**探针已于 2026-11-02 从仓库删除**：它内嵌了一张从 BF5 反馈 MDL3 版提取的敌人分级表，那张表的权利属于该 mod 的作者，不能放在本仓库的 MIT 许可下。删除前的最后一个提交是 `2f5d79b`。

## 贡献者

| 贡献者 | 做了什么 |
|---|---|
| [JFRedist](https://github.com/JFRedist) | 项目发起和方向（先做 Chef 版 BF5，改用 MDL3 后，目标改为在 MDL3 下用 HUDdle）；全部真机测试：在自己的游戏里安装、运行、取日志（MDL3 3.0.0-dev.29、Chef 1.4.1、HUDdle 0.6.11、BF5 击杀反馈、Treasure Radar 0.7.1n），发现并说明了 Treasure Radar 不运行和 ESC 回飞船闪退这两个问题 |
| Claude（Anthropic，Claude Code 会话） | 代码、测试、文档 |

## 致谢

- **Chef Shared Loader**，Th3chef：交接办法是它的文档公开写明的（*"Everything here is free to copy into your loader as it is"*）；本仓库没有它的代码。
- **HUDdle**，rosensterner（部分改编自 luka189 的 NarrowHUD）：本仓库没有它的任何文件。
- **BF5 Hit and Kill Feedback**（原版 [16832](https://www.nexusmods.com/helldivers2/mods/16832) 和 MDL3 版 [16927](https://www.nexusmods.com/helldivers2/mods/16927)）、**MDL3**：它们的作者做了这个仓库围绕的东西；本仓库没有它们的任何文件。

## 许可

本仓库自己的代码和文档用 [MIT 许可](LICENSE)。不在这个授权里的：

- MDL3、Chef、HUDdle、BF5 反馈各有自己的许可，它们的文件不在这个仓库里；文档里引用的 Chef 文档片段归 Chef 的作者。
- 已删除的探针（git 历史里 `2f5d79b` 及更早的提交）内嵌了一张从 BF5 反馈 MDL3 版提取的敌人分级表，权利属于那个 mod 的作者。当前的文件里没有这张表。
