# BFV Chef Probe（探针）

给 Chef Shared Loader 用的**只读**研究 mod，用来回答一个问题：在 7.2.0 之后的纯 Lua 环境里，游戏自己的 Lua 接口到底能让一个 Chef mod 看到什么？
有了答案才能决定 BF5 击杀反馈的 Chef 版能做到什么程度。背景见 [`docs/chef-feasibility.md`](../docs/chef-feasibility.md)。

它**不会**改游戏里的任何东西，不播放声音，只往 Chef 的文件夹里写三个文本文件，并在屏幕左上角显示一行黄色状态字（可以在 F9 菜单里关掉）。

## 安装

1. 装好 Chef Shared Loader（建议 1.4.0 以上，1.0.0 也行），在 Arsenal / HD2 Mod Manager 里给它**最高优先级**。
2. 把 `dist/BFV-Chef-Probe-0.1.0.zip` 加进去并启用，**Purge** 再 **Deploy**。
3. 启动游戏。进任务后左上角出现 `BFV PROBE 0.1.0  FOLLOWED …` 就说明它在工作。

## 第一次运行（安全模式，默认设置）

1. 先删掉旧的 `%APPDATA%\Arrowhead\Helldivers2\bfv_probe.log`（如果有），这样日志只含这一局。
2. 正常打一局，**至少 8～10 分钟**，多打几种敌人，最好有重型（Charger、Hulk、Bile Titan 之类）。
3. 看到游戏自带的反馈时按键做标记（不用每次都按，每种按 3～5 次就够）：
   - **F6**：我刚击杀了一个敌人（看到游戏自带的击杀反馈时）
   - **F7**：我刚命中了一个敌人（看到命中标记时）
   - **F8**：别的值得注意的事（比如手雷、轨道炮、队友击杀）
   按下后屏幕上方会弹出 `PROBE MARK …` 提示。按键可以在 F9 菜单里改；如果你同时装了 Treasure Radar，它默认也占用 F7 和 F8，请改掉其中一边。
4. 任务结束、回到飞船后退出游戏。

## 要发回的文件

都在 `%APPDATA%\Arrowhead\Helldivers2\`：

| 文件 | 内容 |
|---|---|
| `bfv_probe.log` | 事件流：敌人死亡、你的游戏对象字段变化、开火、标记、准星射线 |
| `bfv_probe_api.txt` | 这个游戏版本给 Chef mod 开放的引擎表和函数（含 Wwise / 音频相关） |
| `bfv_probe_summary.txt` | 计数、见到的单位种类（附分级）、被 Chef 拒绝的调用 |
| `chef_loader.log` | （建议一起发）Chef 自己的日志，里面有 Lua 错误和被拒绝的调用 |

隐私：日志里没有 Steam ID、玩家名或文件路径；游戏对象里的文字字段只记长度（`str(5)`），不记内容。有日期和时间。

## 第二次运行（可选，有风险）

F9 → **BFV Chef Probe** → 打开 **Enemy game objects (MAY END THE GAME)**，再打一局，同样标记。
它会去读敌人的网络对象，用来查有没有血量字段（命中标记的来源）。这些调用有可能让游戏崩溃；Chef 的崩溃保护会记住出事的调用，
连续两次在同一处结束后就自动跳过它。如果真崩了，请把 `chef_loader.log` 和 `chef_loader_state.txt` 一起发来，崩在哪一步本身就是答案。

## F9 菜单

| 项 | 默认 | 作用 |
|---|---|---|
| Units: census and deaths | 开 | 跟踪身边会移动的单位，记录它们死亡/消失 |
| My game objects: field changes | 开 | 记录你自己的网络对象（玩家对象、化身、装备）字段变化；默认最多只读编号最小的 40 个对象 |
| Aim ray tests while firing | 开 | 按住鼠标左键时，记录准星射线穿过了哪些被跟踪的单位 |
| Enemy game objects (MAY END THE GAME) | **关** | 见上面的"第二次运行" |
| Show the status line | 开 | 左上角黄色状态字 |
| Write the API list again / Write the summary file now | 按钮 | 立即重写 `bfv_probe_api.txt` / `bfv_probe_summary.txt` |

## 日志里的标签

| 标签 | 意思 |
|---|---|
| `BANNER` `CAPS` `ENV` | 探针版本、Chef 版本和它支持的功能、分辨率 |
| `API` | 引擎接口清单已写入 `bfv_probe_api.txt` |
| `WORLD` `MISSION` | 世界切换、任务开始/结束 |
| `KIND` | 发现一种会移动的单位：`kind`=单位资源 ID，`sm`=有没有动画状态机，`tier`=在 MDL3 版分级表里的档位（`?`=表里没有） |
| `UNIT` | 一个被跟踪的单位**死亡/消失**：`why=sm->none`（状态机消失，最像死亡）、`alive->false`（单位被销毁）、`gone`（从世界列表消失，可能只是走远了）；`d`=离镜头的米数，`ang`=偏离准星的角度，`st`=最后的动画状态，`hist`=最近几次状态变化（负数=事件前多少秒），`fire`=距上次开火 |
| `FIRE` | 鼠标左键按下/松开 |
| `AIM` | 开火时准星射线穿过的单位：`种类前8位#编号:米数@偏角` |
| `OBJSIG` | 发现一种新的网络对象字段布局（字段编号=值）；`n=` 越小越像"独一无二的玩家对象" |
| `OBJ` | 你的某个网络对象字段变了：`字段: 旧 -> 新`。每帧都变的字段（位置之类）会写一次 `muted` 然后不再记录 |
| `EOBJ` | 同上，但是敌人对象（只有开了风险阶段才有） |
| `MARK` | 你按了标记键，附带最近 6 个被跟踪单位的状态 |
| `SUM` | 每 30 秒和任务结束时的计数 |
| `CAP` / `ERR` | 日志预算用完了 / 探针自己某一阶段出错（会自动暂停 60 秒再试） |

## 卸载

在 mod 管理器里取消勾选，Purge 再 Deploy。上面三个文本文件可以直接删掉。

## 它没有验证过的地方

没有在真实游戏里运行过。它在真实的 Chef Shared Loader 1.4.1 上、在 Chef 自带的模拟器（加了我做的假战场）里跑通了，
但假战场里的东西都是我编的，真实游戏会怎样要靠你这一局来回答。
所以第一次启动如果有任何异常（卡顿、崩溃、进任务后左上角没有黄色状态字），请连同 `chef_loader.log` 告诉我。
