# Chef 版可行性调研

调研日期 2026-11-01。对象：Nexus 上的 [Battlefield 5 Hit and Kill Feedback v2.0.1（MDL3 版）](https://www.nexusmods.com/helldivers2/mods/16927)，
目标：做一个能在 [Chef Shared Loader](https://github.com/Th3chef/Chef-Shared-Loader) 1.4.x 下运行的版本。

依据是用户上传的两个压缩包（原版 16832 的 0.1.13，MDL3 版 16927 的 2.0.1）和 Chef 仓库（提交 `400cc03`）的全部文档与源码。
Nexus 页面本身在这个环境里打不开，所以页面上的文字没有读到。

## 结论

1. **MDL3 版的核心数据在 Chef 下没有来源。** 击杀归属、命中/伤害、自定义音效，在 MDL3 下分别来自 HD2 Data Hub 和 `MDL3.audio`；
   Chef 是纯 Lua 5.1（没有 ffi、读不了游戏内存），文档和 API 里没有这三样东西。
2. **其余部分基本可以复用或有对应物**：画面绘制、设置菜单、字体，以及敌人分级表（见下文，ID 空间一致）。
3. **所以现在不能直接移植**。先弄清游戏自己的 Lua 层到底能看到什么：这就是 [`probe/`](../probe/README.md) 里的探针。
   探针只读，不改游戏，用它的日志决定 Chef 版做到什么程度。

## 1. MDL3 版依赖什么

下面的行号指 MDL3 包里 `BFV Hit and Kill Feedback/9ba626afa44a3aa3.patch_0` 解出来的那个 Lua 资源
（`mods/test_author/battlefield5_kill_feedback`，6.2 MB，其中约 5.5 MB 是内嵌音频）。
可以用 `python3 -I tools/inspect_patch.py <patch> <输出目录>` 自己解出来对照。

| 依赖 | 在代码里的位置 | 说明 |
|---|---|---|
| `HD2Data`（HD2 Data Hub，全局，api 1） | 43–44、51–55、157–200、6596–6690 | 14 个事件名；评分代码订阅其中 12 个：`entity_spawned / entity_died / entity_killed / entity_damaged / player_fired / player_hit / player_damage_dealt / player_kill_credited / explosion / bughole_destroyed / mission_started / mission_ended` |
| 击杀归属 | 6370（`event.local_killer ~= true` 就丢弃）、6432（`player_kill_credited`） | 没有"这个击杀是不是本地玩家的"，击杀图标和得分全部不出 |
| 命中/伤害 | 6295–6360（`entity_damaged` 的 `local_attacker`、`damage`；`player_hit.hits`；`player_damage_dealt.damage`；`player_fired.shots`） | 命中标记靠"本地玩家造成的血量变化"和命中统计对上 |
| `MDL3.audio`（原生 XAudio2，api 1） | 203–293、312、1121（注释：*"The XAudio2 kill/hit/score voice pools run in the MDL3 native owner"*） | 音频资源以 MS-ADPCM 内嵌在 Lua 里，上传给 MDL3 的原生层播放 |
| MDL3 的 UI 服务（字体图集、设置面板、与 MOM 的桥接） | 7044、8886、9251 起 | 菜单和字体 |

Data Hub 是 MDL3 自带的原生服务，不是单独的 Lua mod：HiveLordHUD 的 Nexus 页面说 Data Hub "已经在 MDL3 里"（来自搜索结果摘要，未能打开原页面核实）。

## 2. Chef 提供什么

- Chef 的 README 原话：*"since the October 20, 2026 update (7.2.0) the game runs plain Lua 5.1, with no `ffi`, so no Lua mod can read or write game memory. No loader can bring that back."*
- `docs/MODDING.md` 全文和 `docs/types/chef.lua` 全文都读过。在整个 Chef 仓库里搜索 `audio / sound / wwise / damage / kill / health`，没有任何相关接口（只有资源类型常量）。
- 被 Chef 挡掉的引擎表：`PluginManager`、`Http`、`WebSocket`、`Localizer`、`Console`、`SaveSystem`、`Cloud`、`Friends`、`SteamClient`、`SteamVoip*`；`Application` 里写文件/改设置的调用；`Network`、`GameSession`、`UnitSynchronizer` 只留只读调用。
- Chef 能给的（对应 MDL3 版的需要）：

| 需要 | Chef 里的对应物 |
|---|---|
| 画图标、文字、圆环、动画 | `chef.rect / circle / ring / arc / triangle / text / bitmap / sprite_sheet`，文字用游戏自己的字体 |
| 设置菜单 | `chef.option`（开关、选项、滑条、颜色、按键、按钮），F9 菜单，自动保存 |
| 按键 | `chef.bind`、`chef.key_down / key_pressed` |
| 敌人单位列表、位置、是否存活 | `World.units` 或 `chef.watch`，`chef.unit_kind / unit_position / unit_alive` |
| 判断敌人死亡 | 单位的动画状态机消失（Treasure Radar 就是这么做的：*"a killed enemy's body stays in the world, but its animation state machine goes away"*） |
| 读游戏网络对象的字段 | `GameSession.game_object_field_batched` 等只读调用（Treasure Radar 用它读自己的玩家对象和化身对象） |
| 准星射线 | `chef.ray_box`（射线对一个单位的包围盒；游戏没有给 Lua 世界射线检测） |

## 3. 逐项判断

| MDL3 版需要的 | Chef 下 | 判断 |
|---|---|---|
| 画面、动画、文字 | 有 | 可复用，要改成 `chef.*` 绘制 |
| 设置菜单 | 有 | 可复用，MDL3/MOM 桥接换成 `chef.option` |
| 敌人分级（light/medium/heavy/flying） | 有 ID，没有分级 | **可复用**，见下 |
| 敌人什么时候死、是什么种类 | 有 | **已知**（第一轮）：进入死亡动画状态的那一刻，比状态机消失早 5 秒；见 `docs/probe-run-1.md` |
| 谁击杀了谁（本地玩家的击杀） | 没有已知来源 | **未知**：第一轮只看了 347 个游戏对象里的 40 个，没找到；第二轮看全部 |
| 本地玩家命中了敌人 | 没有已知来源 | **未知**：同上；第二轮把准星下的单位和它的游戏对象对上，看血量字段 |
| 自定义 BF5 音效 | 没有音频接口 | **目前没有路径**（第一轮）：104 张表里没有 Wwise / Audio / Sound；`VideoPlayer` 的声音流、`Unit.flow_event` 等没试过；否则只能做无声版 |

### 敌人分级表可以直接复用

MDL3 版里有一张 142 项的表 `HD2_EVENT_TYPE_MAP`（2078–2220 行），键是 16 位十六进制 ID，值是 `light / medium / heavy / flying`。
代码注释写的是 Hub 的事件类型 *"is the same 64-bit resource type rendered as sixteen hexadecimal digits"*。

这和 Chef 里 `chef.unit_kind(unit)` 给出的是同一套 ID。验证：拿 Treasure Radar 源码里列出的 60 个敌人单位资源 ID 去比，
有 **42 个** 是这张表的键（比如 Charger、Bile Titan），另外 18 个不在表里；表里另有 100 个条目不在 Treasure Radar 的列表里。
（只是比对数量，没有把那份列表抄进本仓库：它的许可证要求复用前先问作者。）
`tools/extract_tiers.py` 把这张表提出来，探针里内嵌了一份，用来在汇总文件里报告"这次任务里见到的会移动的单位种类，有多少已经有分级"。

## 4. 探针要回答的问题，和第一轮的答案

| 问题 | 日志里看什么 | 回答"能"时 Chef 版怎么做 | 第一轮（0.1.0） |
|---|---|---|---|
| Q1 本地玩家的击杀能不能精确得到 | `OBJ`/`GRP`/`AIMOBJ` 里 `字段: a -> b`：你按 F6 前后几秒，有没有字段 +1 | 用这个字段的变化做击杀凭证，其余照 MDL3 版的逻辑（`player_kill_credited`） | **没回答到**：只看了 40/347 个对象 |
| Q2 命中能不能得到 | 同上，F7；或 `AIMOBJ … \| 22: 600 -> 440`（准星下敌人的对象字段） | 命中标记、`entity_damaged` 的替身 | **没回答到** |
| Q3 敌人死亡的时刻和种类 | `DEATH`、`UNIT`、`KIND` | 击杀图标的触发和分级，不用 Hub | **能**：进入死亡状态 = 击杀时刻，状态机 5 秒后才消失；6 种已见种类的死亡状态已记在探针里 |
| Q4 能不能出声 | `bfv_probe_api.txt` 里的 `Wwise*`、`Audio*`、`Sound*` | 能触发游戏已有的声音事件，再配合数据替换换成 BF5 的声音；否则无声版 | **没有路径**；`VideoPlayer.set_sound_stream_enabled`、`FlowComponent.trigger_flow_event`、`Unit.flow_event`、`Level.trigger_event` 没试过 |
| Q5 准星启发式够不够 | `DEATH` 里的 `cone`/`ray`/`fire`、`AIM`、`FIRE`、`MARK` | 没有 Q1/Q2 时的退路：开火 + 准星对准 + 目标进入死亡状态 ≈ 我的击杀（会误判队友、战略支援的击杀） | **部分**：10 次击杀标记里 8 次在前 4 秒内有单位进入死亡状态；射线测试太稀，没有误判率 |

## 5. 验证到了哪一步

见仓库根目录 README 的"验证状态"。要点：

- 0.1.0 在真实游戏里跑过一局；0.2.0 在真实的 Chef Shared Loader 1.4.1 上用它自带的模拟器跑通，战场按第一轮日志重建。
- 模拟器里游戏对象字段的含义和 `UnitSynchronizer.unit_to_game_object_id` 的参数形式是猜的，第二轮要回答的就是它们在真实游戏里是什么样。
- 游戏会不会接受我打出来的补丁文件头：格式已和两个真实 mod 的补丁逐字节对过，0.1.0 的 zip 也在真实游戏里加载成功了。
- 一切关于"Data Hub 是原生的"、"HUDdle 做了什么"的说法，来自搜索结果摘要，没有打开原始页面核实（Nexus 域名在我这里打不开）。
