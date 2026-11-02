# BFV Chef Probe（探针）0.2.0

> **已停用（2026-11-01）。** 这个探针是为做 BF5 击杀反馈的 Chef 版而写的；作者随后改用 MDL3 版，探针 0.2.0 只在模拟器里验证过，没有在真实游戏里运行。
> **不需要安装它**（`dist/BFV-Chef-Probe-0.2.0.zip` 留作记录）。现在的项目是 Chef Hand-off for MDL3，见 [README](../README.md)。
> 探针里内嵌的敌人分级表是从 BF5 反馈的 MDL3 版提取的，权利属于那个 mod 的作者，不在本仓库 MIT 许可的范围内（见 README 的"许可"）。

给 Chef Shared Loader 用的**只读**研究 mod，用来回答一个问题：在 7.2.0 之后的纯 Lua 环境里，游戏自己的 Lua 接口到底能让一个 Chef mod 看到什么？
有了答案才能决定 BF5 击杀反馈的 Chef 版能做到什么程度。背景见 [`docs/chef-feasibility.md`](../docs/chef-feasibility.md)，
第一次真机运行（0.1.0）的结果见 [`docs/probe-run-1.md`](../docs/probe-run-1.md)。

它**不会**改游戏里的任何东西，不播放声音，只往 Chef 的文件夹里写三个文本文件，并在屏幕左上角显示一行黄色状态字（可以在 F9 菜单里关掉）。

## 0.2.0 比 0.1.0 多了什么

第一次运行显示：敌人进入"死亡动画状态"的时刻比动画状态机消失早 5 秒；0.1.0 只看了 347 个游戏对象里的 40 个，所以没找到击杀凭证和命中信号；
79% 的 `UNIT` 行是噪声。0.2.0 针对这些改了：

- 进入死亡状态的瞬间就记 `DEATH`，并写出那一刻准星离它多远、多久前开过火。
- 看**全部**游戏对象（房主有几百个），不再只看 40 个；同一种布局的对象轮流读，噪声字段自动静音。
- 把准星下的单位和它的游戏对象对上（只读查询），开火时盯着那个对象的字段（血量会不会掉）。
- 过滤附件和短命单位；准星射线在开火瞬间就测，松开后再测 1.5 秒。

## 安装

1. 装好 Chef Shared Loader（建议 1.4.0 以上，1.0.0 也行），在 Arsenal / HD2 Mod Manager 里给它**最高优先级**。
2. **先删掉 0.1.0 的探针**，再把 `dist/BFV-Chef-Probe-0.2.0.zip` 加进去并启用，**Purge** 再 **Deploy**。
3. 启动游戏。进任务后左上角出现 `BFV PROBE 0.2.0  FOLLOWED …` 就说明它在工作。

## 这一局怎么打

1. 先删掉旧的 `%APPDATA%\Arrowhead\Helldivers2\bfv_probe.log`（如果有），这样日志只含这一局。
2. **做房主**（单人，或者自己开房）。非房主时敌人的游戏对象在别人那里，探针默认不读，那一局只能得到 `LINK … not in my list` 这类行。
3. 至少打 8～10 分钟，多打几种敌人，**一定要有大只的**（Charger、Hive Guard、Bile Titan 之类，血量多，一枪打不死）。
4. 看到游戏自带的反馈时按键做标记，**不用每次都按**：
   - **F6**：我刚击杀了一个敌人（看到击杀反馈时）
   - **F7**：我刚命中了一个敌人（看到命中标记时）
   - **F8**：别的值得注意的事（手雷、轨道炮、队友击杀……）
   按下后屏幕上方弹出 `PROBE MARK …`。按键可以在 F9 菜单里改；Treasure Radar 默认也占 F7、F8，请改掉其中一边。
5. 建议的节奏（这比随便打更有用）：
   - 对一只**大只的敌人**持续点射，**每看到一次命中标记就按一下 F7**，它倒下时按 F6。做 3～4 次。
   - 对**小只的敌人**，每只打一枪：命中按 F7，击杀按 F6。做 10 次左右。
   - 偶尔让队友/手雷/轨道炮杀一只，按 F8，用来区分"我的击杀"和"别人的击杀"。
6. 任务结束、回到飞船后退出游戏。

## 要发回的文件

都在 `%APPDATA%\Arrowhead\Helldivers2\`：

| 文件 | 内容 |
|---|---|
| `bfv_probe.log` | 事件流：敌人进入死亡状态/死亡、游戏对象字段变化、开火、标记、准星射线 |
| `bfv_probe_api.txt` | 这个游戏版本给 Chef mod 开放的引擎表和函数 |
| `bfv_probe_summary.txt` | 计数、死亡状态表、见到的单位种类（附分级）、游戏对象的字段布局表、被 Chef 拒绝的调用 |
| `chef_loader.log` | （建议一起发）Chef 自己的日志：Lua 错误、被拒绝的调用、探针每分钟的耗时 |

隐私：日志里没有 Steam ID、玩家名或文件路径；游戏对象里的文字字段只记长度和一个编号（`str#3:16`：第 3 种不同的文字，16 个字符；相同的文字编号相同），不记内容。有日期和时间。

## 风险与恢复

- **默认只做读取**：`GameSession.objects_owned_by`、`game_object_field_batched`（只读**你自己的**对象）、`GameSession.unit_synchronizer`、
  `UnitSynchronizer.unit_to_game_object_id`（查询）。这些调用都经过 Chef 的崩溃保护。
- 0.1.0 读了 40 个自己的对象，没出过问题；0.2.0 会读全部，每帧最多 14 个。如果觉得卡，F9 里关掉 **All of my game objects**。
- `UnitSynchronizer.unit_to_game_object_id` 是第一次在真实游戏里用。如果游戏崩溃，重启后 Chef 会记住出事的调用并跳过它；
  请把 `chef_loader.log`（和 `chef_loader_state.txt`，如果有）发来，崩在哪一步本身就是答案。想先排除它，F9 里关掉 **Unit under the crosshair <-> its game object**。
- **Other players' game objects (MAY END THE GAME)** 默认关。它读别的玩家拥有的对象，别的 mod 在这上面崩过。除非我让你开，不要开。

## F9 菜单

| 项 | 默认 | 作用 |
|---|---|---|
| Units: census and deaths | 开 | 跟踪身边会移动的单位，记录它们进入死亡状态、死亡、消失 |
| My game objects: field changes | 开 | 记录你自己的网络对象字段变化 |
| All of my game objects, not just the oldest 40 | 开 | 读你拥有的全部对象（房主有几百个）；关掉就像 0.1.0 一样只看编号最小的 40 个 |
| Aim ray tests while firing | 开 | 开火时（和开火后 1.5 秒）记录准星射线穿过了哪些被跟踪的单位 |
| Unit under the crosshair <-> its game object | 开 | 查准星下单位的游戏对象，开火时每 0.25 秒读它的字段 |
| Other players' game objects (MAY END THE GAME) | **关** | 见上面的"风险" |
| Show the status line | 开 | 左上角黄色状态字 |
| Write the API list again / Write the summary file now | 按钮 | 立即重写 `bfv_probe_api.txt` / `bfv_probe_summary.txt` |

## 日志里的标签

| 标签 | 意思 |
|---|---|
| `BANNER` `CAPS` `ENV` | 探针版本、Chef 版本和它支持的功能、分辨率、游戏版本 |
| `API` | 引擎接口清单已写入 `bfv_probe_api.txt` |
| `WORLD` `MISSION` | 世界切换、任务开始/结束 |
| `SESSION` | 每个世界一次：你是不是房主、几个玩家 |
| `KIND` | 发现一种会移动的单位：`kind`=单位资源 ID，`sm`=有没有动画状态机，`tier`=在 MDL3 版分级表里的档位（`?`=表里没有） |
| `DEATH id=… kind=… st=…` | **进入死亡状态**（约等于击杀时刻）。`src=seed/learned`；`d`/`ang`=离镜头的米数/偏离准星的角度；`cone`=准星最近一次在它 6° 内是多少秒前，`ray`=射线最近一次打中它是多少秒前（`-` 表示没有），`fire`=距上次开火，`obj`=它的游戏对象编号 |
| `DEATH late/cancel/learned` | 第一次看到时它已经在死亡状态 / 离开了死亡状态（撤销）/ 学到了一个新种类的死亡状态 |
| `UNIT` | 一个被跟踪的单位**消失**：`why=sm->none`（状态机消失，死亡约 5 秒后）、`alive->false`（单位被销毁）、`gone`（从世界列表消失）；`dying`=距 DEATH 多少秒，`hist`=最近几次状态变化（负数=事件前多少秒） |
| `STATE` | 准星 12° 内的单位在开火时的动画状态变化（受击动作会出现在这里） |
| `IGNORE` | 一种单位被自动忽略（太多 3 秒内消失、没有状态机的单位） |
| `FIRE` | 鼠标左键按下/松开 |
| `AIM` | 准星射线穿过的单位：`种类前8位#编号:米数@偏角` |
| `OBJSIG` | 发现一种新的游戏对象字段布局（字段编号=值）；`field … muted` 表示这种布局里这个字段变得太频繁，不再记 |
| `OBJ` | 一个布局独一无二的对象（玩家、计时器……）的字段变了：`字段: 旧 -> 新` |
| `GRP` | 一个和别的对象共享布局的对象（敌人……）的字段变了 |
| `AIMOBJ` | 准星下（或刚进入死亡状态）的单位的游戏对象字段变了；`first look` 是第一次看到它的全部字段 |
| `SIGKIND` | 某种字段布局属于某种单位（通过 unit synchronizer 对上的） |
| `LINK` | 单位↔对象查询的问题：没有对象 / 对象不是你的（没读） |
| `NEW` `GONE` | 任务中出现/消失的游戏对象 |
| `MARK` | 你按了标记键，附带最近 6 秒内的 DEATH 和最近 6 个被跟踪单位的状态 |
| `SUM` | 每 30 秒和任务结束时的计数 |
| `CAP` / `ERR` | 日志预算用完了 / 探针自己某一阶段出错（会自动暂停 60 秒再试） |

## 卸载

在 mod 管理器里取消勾选，Purge 再 Deploy。上面三个文本文件可以直接删掉。

## 验证到了哪一步

0.1.0 已经在你的真实游戏里跑过（`docs/probe-run-1.md`）。0.2.0 在真实的 Chef Shared Loader 1.4.1 上、在 Chef 自带的模拟器里跑通了，
战场是我按你那一局的日志重建的：同样的敌人种类和死亡状态、5 秒的死亡状态、附件、短命单位、房主的几百个游戏对象。
战场里的**游戏对象字段含义和 `unit_to_game_object_id` 的参数形式是我猜的**，真实游戏会怎样要靠你这一局来回答。
所以如果有任何异常（卡顿、崩溃、进任务后左上角没有黄色状态字），请连同 `chef_loader.log` 告诉我。
