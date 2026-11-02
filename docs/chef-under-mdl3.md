# 在 MDL3 下运行 HUDdle：让 Chef 在 MDL3 里启动

**状态**：交接 addon 0.2.0 在真机上可用（MDL3 3.0.0-dev.29，Chef 1.4.1，HUDdle 0.6.11，Treasure Radar 0.7.1n，BF5 击杀反馈 MDL3 版）。
Chef 1.5.x 和 0.2.0 不兼容（Chef 把 MDL3 的回调放在它的卡死看门狗下面）；0.2.1 修了，**在模拟器里用真实的 Chef 1.5.1 验证过，真机还没有确认**，见“Chef 1.5.x”一节。
还没有解释的一件事：任务中 ESC 回飞船闪退过一次（0.1.0），原因没找到，之后没有再出现。见“ESC 回飞船闪退”和“还没有确认的”两节。
使用说明在 [`handoff/README.md`](../handoff/README.md)，项目概览在 [`README.md`](../README.md)。

## 问题

HUDdle（Nexus 18108，作者 rosensterner）是 **Chef Shared Loader** 的 addon，没有 MDL3 版：
manifest 和 README 都写明需要 Chef 1.2.0 以上，Lua 里 500 多行调用 `chef.*`，整个包里一次也没有出现 MDL3。
BF5 反馈的 MDL3 版需要 MDL3（它的 manifest：*"MDL3 is required as a prerequisite"*）。想两个都用，就得让 Chef 和 MDL3 在同一个游戏里工作。

## 为什么默认不能一起工作

游戏只运行一个 `boot`：优先级最高的补丁里的那个。Chef 的文档（`docs/MODDING.md`，"Compatibility with mods that still replace `boot`"）写得很明白：

- *"When that mod deploys after Chef Shared Loader: the game runs only that mod's `boot`, and no Chef Shared Loader mod runs, unless its `boot` is the start-up stub."*
- *"Another mod loader's `boot` (one that reads the patches for mods itself, such as Boot Mod Loader or Bingus Shared Loader v21) is not run: it would start every mod a second time."*

BF5 的 MDL3 版自己的代码也表明 MDL3 是这一类加载器：它读 `CowboyBingusModLoader`（Bingus / Boot Mod Loader 的接口）、
包住全局 `update`，头一行是 `-- HD2-Addon: mods/test_author/battlefield5_kill_feedback`。所以 Chef 的优先级高，MDL3 不运行；MDL3 的优先级高，Chef 不运行。（"高"指部署顺序里靠后、赢得 `boot` 的那一边；Arsenal 里是列表的上端还是下端，取决于它的 First / Last mod highest priority 设置。）

## 做法：从 MDL3 这边把游戏交给 Chef

Chef 的文档（"For other loaders"，"Handing off to it"）给其它加载器留了交接办法，并且说 *"Everything here is free to copy into your loader as it is"*：

```lua
rawset(_G, 'ChefSharedLoaderHandoff', { from = 'My Loader 1.0' })     -- 加 phase = 'init'：游戏已经调用过 init
require('mods/chef_shared_loader/core_1')
```

文档给的是写在加载器的 `boot` 最前面。MDL3 的 boot 不是我们的，但 MDL3 会启动带 `HD2-Addon` 头的 Lua（BF5 就是这样启动的），
所以 `handoff/chef_handoff.lua` 是这样一个 addon，在 MDL3 启动它之后：

1. **包住 `update`**（BF5 的 MDL3 版同样的做法），累计 dt。
2. **6 秒后**（第一帧之后，MDL3 的 addon 都启动完了，游戏的 `init` 早已调用过）才交接。这样 Chef 扫描 mod 时，MDL3 已经启动的 mod 已经登记在
   `package.loaded` / `CowboyBingusModLoader.modules` 里，Chef 会跳过它们（文档："A mod found there isn't started again"）。
   也因为游戏已经调用过 `init`，便条里写 `phase = 'init'`：Chef 自己调用一次 `init`，不再重复调用启动器留下的 `init`。
3. **交接**：设便条，`pcall(require, core)`，清掉便条。
4. **保护**：Chef 没装（`Application.can_get('lua', core)` 不是 true）、Chef 已经在运行（`ChefSharedLoader` 全局存在）、
   上次启动在交接中结束（`chef_handoff_state.txt` 里是 `attempt`）这三种情况都什么也不做；任何错误都被 `pcall` 接住，不会弄断 MDL3 的 `update` 链。
5. **日志**：`%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log`，开头列出启动时能看到的加载器全局表（`CowboyBingusModLoader`、`MDL3`、`HD2Data`、
   `ModOptionsMenu`……）里有什么，交接的结果，Chef 的版本。几十行。

**回调（0.2.1 起）**：Chef 被交接时，会把当时的 `init`、`update`、`render`、`shutdown`（MDL3 和它的 mod 串起来的链）收下，每帧在自己的回调之后运行
（0.2.0 和 Chef 1.4.1 的日志里是 *"running the callbacks the boot script ... set before it started me (3)"*）。Chef 1.5.0 起这样收下的回调在它的卡死看门狗下面，见“Chef 1.5.x”一节。
所以 0.2.1 在交接前把这四个全局先摘下来（Chef 加载时看到的是空的，就没有东西可收），Chef 加载完再放回去：`update`、`render`、`shutdown` 放在 Chef 自己的回调后面（Chef 的先，MDL3 的链后，用 `pcall` 隔开 Chef 的，MDL3 的错误照原样交给游戏），
`init` 不放回（游戏早就调用过 MDL3 的，也不会再调用）。Chef 没起来（核心报错）时，原样放回。

## 考虑过的另一条路：写一个桥，不用 Chef

HUDdle 只用了大约 50 个 `chef.*` 函数（画矩形/三角/弧/文字、相机、按键、选项、读写表……），可以在 MDL3 下用游戏自己的 `Gui` 等接口重新实现，
让 HUDdle 的 Lua 在桥上运行。没有这么做，因为：

- 要重新实现 Chef 用血换来的引擎细节（立即模式 GUI、`Color`/`Vector3` 只活一帧、GUI 在世界销毁后再用会让游戏结束、主世界和 UI 世界的层次、字体……），
  而这些只能靠玩家的游戏来验证，模拟器里只是猜测。
- 桥只是 HUDdle 要用的那一部分；你已经装的其它 Chef mod 仍然跑不起来。
- 交接这条路几乎是 30 行，用的是真正的 Chef，行为和你现在用的完全一样（F9 菜单、设置、HUDdle 的全部功能）。
- 如果交接走不通，桥还可以再做；交接 addon 的日志会告诉我走不通在哪里。

## 验证

| 检查 | 内容 |
|---|---|
| `tests/test_handoff.lua`（80 项） | 假游戏里：6 秒前不交接、之后交接一次、便条内容、状态文件、日志、`update` 链保持；0.2.1 起还有：Chef 加载时看不到游戏的回调、`update` / `render` / `shutdown` 里 Chef 的先于链、`init` 是 Chef 的、核心失败时回调原样放回、Chef 的回调报错不影响链、慢调用写进日志、调试钩子的日志；Chef 没装 / 已在运行 / 上次崩溃 / 核心报错 / 各种奇怪的游戏（没有 `can_get`、没有 `update`、坏 dt、加载两次、没有文件夹）。Chef 的全局在假游戏里是只读代理（像真的一样），这一点是真实 Chef 的模拟器测试抓出来的 |
| `tests/handoff_sim.sh`（真实的 Chef 1.4.1 和 1.5.1，Chef 自带的模拟器；每个 58 项，加上 D 是 62 项） | **A** 假 MDL3 在 `init` 里启动 addon；**B** 假 MDL3 在 `boot` 里启动 addon，并先用普通 `require` 试 Chef 的 mod（登记在 Bingus 式的 `modules` 表里）；**E** 同 B，但只留下 `package.loaded`（真实 MDL3 那一次显示的样子）；**F** 假 MDL3 的更新链里有一次 3.6 秒 CPU 时间的慢调用（Chef 1.5.x 会把它判成卡死，见下）；**C** 假 MDL3 自己已经交接。 B、E 里有一个像 Treasure Radar 的替身（没有 `HD2-Requires` 头，普通 `require` 不报错）：0.1.0 会把它漏掉（和真机日志里同一句 `already started by another loader (started)`），0.2.0 启动它。检查：Chef 报告被谁交接、自己的 boot stub 没有运行、Chef 的 mod 启动并绘制、交接 addon 不会被 Chef 再启动一次、假 MDL3 的回调（3 个，没有 `init`）每帧照常运行（60 秒约 3600 次）、游戏的 `init` 恰好一次、日志和状态文件。可选 **D**：设置 `HUDDLE_LUA` 用真实的 HUDdle 0.6.11（不在仓库里） |
| 变异检查（一次性的手工检查，脚本没有放进仓库） | 0.1.0：故意改坏 9 处（没有延迟、没有 `phase`、不检查 Chef 在运行、忽略崩溃标记、不 `pcall`、不写 ok 标记、丢参数、不清便条、不检查 Chef 是否安装）：自写测试全部抓到；模拟器测试抓到其中会影响真实 Chef 行为的三处（延迟、`phase`、已在运行的检查）。0.2.0 又加了 11 处（补丁文件的读法、判断做给 Chef 的规则、摘掉的范围等），自写测试全部抓到，只有一个防御性的等价变异除外。0.2.1 再加 7 处（不摘回调、放回时不放在 Chef 后面、顺序反了、核心失败时不放回、不隔开 Chef 的错误、不记慢调用、把 `init` 放回去），全部抓到（其中两处是测试脚本因此直接报错退出） |

## 第一次真机结果（2026-11-02，MDL3 3.0.0-dev.29，Chef 1.4.1）

来自用户上传的 `chef_handoff.log`、`chef_loader.log`、`chef_handoff_state.txt`：

- **交接成功。** `chef_handoff.log`：6.0 秒时交接，`Chef Shared Loader 1.4.1 started`；`chef_loader.log`：`started by MDL3 chef_handoff 0.1.0, which handed off to me`，
  `start-up: started by the boot in ...patch_85 (MDL3 3.0.0-dev.29 game boot (PUC Lua 5.1, protected preview))`，Chef 自己的 boot stub 没运行，HUDdle 0.6.11 启动并在任务里出现，
  任务识别（world 4: mission, 9260 units, 1061 levels）、F9 菜单、引擎三角形绘制都正常，开销平均 0.04～0.19 ms/帧。
- **MDL3 启动 addon 的办法确认了**：它启动带 `HD2-Addon` 头的 Lua（交接 addon 被启动了；`hd2_data_hub`、`treasure_radar` 也被它启动过，Chef 因此跳过它们）。
- MDL3 给 addon 的全局（交接 addon 启动时的日志）：`CowboyBingusModLoader`（10 项：`api discovery guards log_directory mdl3 modules open_log open_log_direct provider version`）、
  `MDL3`（44 项，含 `audio bridge_epoch generation heartbeat reconnects stopping pending performance version`……）、`MDL`（34 项）、`HD2Data`（20 项，含 `aim player_ammo players mission stratagems`……）、
  `ModOptionsMenu`（MDL3 自己的，`provider` 字段）。`HD2Data.player_ammo` / `aim` 说明 MDL3 的数据中心本身就有弹药和瞄准的数据。
- **发现一：Chef 的 mod 如果没有 `HD2-Requires: chef-shared-loader` 头，并且被 MDL3 用普通 `require` 启动时没有报错，Chef 会认为它"已经被别的加载器启动"而跳过。**
  Treasure Radar（`local chef = ...` 之后只在函数里用 `chef.`）就是这样：日志里 `mods/chef/treasure_radar: already started by another loader (started), not started again`，实际没有运行。
  HUDdle 因为加载时就报错（`attempt to call field 'time' (a nil value)`），被当作失败而被 Chef 启动。修法：交接前把这类 mod 从 `package.loaded` 里摘掉（还没做）。
- **发现二（只出现过一次，没有找到原因）：任务中按 ESC 回飞船，游戏闪退。** `chef_loader.log` 里任务开始 27 秒后就是 `shutdown (clean)`，没有 Chef 在回飞船时平时会记的下一个世界（"world 5: not a mission (24 units, 0 levels)"）：
  游戏没有切换场景，直接走了退出流程。同一个日志里，只用 Chef 的那些启动（多次任务来回）回飞船都正常。
  模拟器里同样的安排（假 MDL3 + 交接 + 真 HUDdle）加"任务中途换世界"没有崩溃，所以 Chef 自己的世界切换逻辑不是原因；是 MDL3 预览版自己、HD2 Data Hub、
  交接、还是 HUDdle 与 MDL3 的相互影响，需要隔离实验（见下一次来回的结果）。

## 第二次真机结果（2026-11-02，同一个 MDL3，BF5 反馈也已部署）

来自 `MDL.log`（MDL3 自己的日志）、`chef_loader.log`、`minimal_hud.log`、`chef_handoff.log`：

- **正常完成任务后回飞船没有问题。** Chef 日志里 world 3: mission（9260 单位）→ world 4: not a mission（24 单位，加载）→ world 5（飞船）→ 退出游戏时 `shutdown (clean)`；
  HUDdle 整局 8 分钟没有一条错误，任务里平均 0.7 ms/帧（低于它 1 ms 的预算）。**ESC 回飞船那条路这次没有再测**，上一次的闪退还没有复现，也没有解释。
  上一次 HUDdle 的日志在退出前一切正常（最后是 `HUD woke from calm`，1.3 秒后 `bye`），Chef 的日志是 `shutdown (clean)`：游戏自己走了退出流程。
- **MDL3 怎么启动 addon**（`MDL.log`）：它自己的协调器（"coordinator: discovery 5 declared entries in 91 archive(s)"）读各个补丁里 `HD2-Addon` 头声明的 addon，逐个 `enable`。
  5 个：`hd2_data_hub`、`chef_handoff`、`battlefield5_kill_feedback`、`minimal_hud`、`treasure_radar`。BF5 反馈启用成功，并在 MDL3 自己的 Mod Options Menu 里注册了它的 50 多个选项。
  Chef 没有读 BF5 的 Lua（6 MB，"too big to be a mod"），所以不会把它再启动一份。
- **HUDdle 在 MDL3 里"加载失败"**（`enable failed ... attempt to call field 'time' (a nil value)`）：MDL3 给 addon 的不是 Chef，没有 `time`；这是 MDL3 眼里的失败，实际是 Chef 在运行它。
- **Treasure Radar 在 MDL3 里"启用成功"**：它给 addon 的参数里有一个 `log`（Treasure Radar 的日志行出现在 `MDL.log` 里，格式没展开），Treasure Radar 加载时只用了 `chef.log`，没报错就返回了。
  Chef 看到 `package.loaded` 里有它，以为是别的加载器启动的，跳过。这就是它没有运行的原因（本版 0.2.0 修）。
- MDL3 的内部：`native binding ... mdl_native_bridge.dll`、`Preview: read-only data via HD2Data`、`MDL provides the Mod Options Menu API`（Chef 的同名替身没有启用，正确）、
  `SYS_BATCH_FAILED E_BUDGET: instruction/time/stop limit`（MDL3 的 sys 服务启动时的预算超限，反复出现，与我们无关）、`library: startup loader hidden from the list: Chef Shared Loader 1.4.1 (LOADER)`（MDL3 认识 Chef，把它当作启动加载器）。

### 0.2.0：交接前把 Chef 的 mod 从 MDL3 的"已启动"里摘出来

**为什么要认。** Chef 自己不需要认：在 Chef 的世界里，每个带 `HD2-Addon` 头的 Lua 都是它的 mod。但 MDL3 也用同一个头，所以交接 addon 得把"做给 Chef 的"和"做给 MDL3 的"分开，只摘前者。

**怎么认**（`handoff/chef_handoff.lua` 的 `scan_patch` / `scan_chef_addons`）：

1. 直接读游戏的补丁文件 `data/9ba626afa44a3aa3.patch_0`、`_1` ……（Chef 自己也这样读它们）。连续 8 个号码都不存在就停，最多到 400 号，总共最多读 0.5 秒。
2. 每个补丁：开头 4 字节要是 `0xF0000011`；类型数 ≤ 64、条目数 ≤ 4096（再大的是游戏自己的数据，不是 mod 的补丁，跳过）。
3. 条目表（72 字节头、32 字节类型行、80 字节条目）里只看 Lua 类型（类型 id `a14e8dfa2cd117e2`）、长度大于 16 字节且小于 4 MB 的资源，每个只读前 16 KB。（BF5 反馈的 Lua 有 6 MB，所以不读。）
4. 这段源码要以 **`-- HD2-Addon: mods/<作者>/<名字>` 头开头**，才算 addon。
5. 是 addon 之后，看它是不是做给 Chef 的，只认两个标记（都在前 16 KB 里）：
   - **行首的 `local chef = ...`**：Chef 把它的工具表作为 Lua 块的参数交给每个 addon，Chef 的 mod 习惯在开头用这一行接住它。MDL3 的 addon 拿到的是 MDL3 的上下文（有 `log`，没有 `time`），不这样写。
     只认"行首的代码"，注释里提到的（`-- local chef = ...`）不算。
   - **`-- HD2-Requires: chef-shared-loader` 头行**：明说需要 Chef。
   交接 addon 自己除外（它的注释里提到 chef）。
6. 认出的名字：从 `package.loaded` 里摘掉（`require` 留下的占位 userdata 不动，Chef 会照常启动那种）；在加载器自己的 `modules` 表里状态是 `loaded` / `loading` 的，改成 `load failed: made for Chef Shared Loader`。然后再交接，Chef 就把它们当作还没启动的 mod 启动。
7. 一个补丁文件都读不了时，用内置的两个名字（Treasure Radar、HUDdle）。

日志里能看到结果：`patch files read: N (X addons, Y made for Chef, …)`、`made for Chef: …`、`taken off package.loaded, so that Chef starts them: …`。

**会漏掉什么。** 既没有 `local chef = ...` 这一行（比如写成 `local c = ...`、`local chef, log = ...`、`local chef = select(1, ...)`，或者前面有缩进）、也没有 `HD2-Requires` 头的 Chef mod 认不出来，
症状和原来的 Treasure Radar 一样：`chef_loader.log` 里 `already started by another loader (started), not started again`。标记在前 16 KB 之后的、Lua 超过 4 MB 的，也认不出来。
**会多摘什么。** 一个 MDL3 的 addon 如果恰好有一行行首的 `local chef = ...`，会被摘掉，Chef 会再启动它一份，`chef_loader.log` 里会有 `started mods/<作者>/<名字>`。没见过，也想不出谁会这样写。

`tests/test_handoff.lua` 里每条规则都有例子：有 / 没有 `HD2-Requires` 头、`local chef` 在长注释之后、MDL3 的 addon、超过 4 MB 的 Lua、上千条目的补丁、魔数不对的文件、只在注释里提到 chef、交接 addon 自己、读文件抛错、读不了补丁时的内置名单。

## 第三次真机结果（2026-11-02，0.2.0）

作者的试玩报告，**没有传 Chef 的日志**：

- **任务中按 ESC 回飞船没有闪退。**
- **BF5 反馈（MDL3 版）正常。**
- **Treasure Radar 没问题。**（0.1.0 时被 Chef 跳过的那个。）

后来传了 0.2.0 的 `chef_handoff.log`（02:47）：

- 6.0 秒：`patch files read: 91 (4 addons, 2 made for Chef, 0 read errors) in 5 ms`。读了 91 个补丁文件，找到 4 个 addon（交接 addon、Treasure Radar、HD2 Data Hub、HUDdle），认出 2 个做给 Chef 的（Treasure Radar 和 HUDdle），没有读文件的错误，用了 5 毫秒。
  **所以补丁扫描在真机上起作用，不是靠内置名单。**
- `taken off package.loaded, so that Chef starts them: mods/chef/treasure_radar`：只有 Treasure Radar 在 `package.loaded` 里（HUDdle 在 MDL3 里加载就失败了，不在）。摘掉之后 `Chef Shared Loader 1.4.1 started (api 1)`。
- MDL3 的 `CowboyBingusModLoader.modules` 表有 19 个条目，状态是 `managed`、`not installed`、`load failed (managed): …`（HUDdle），**没有** `loaded` / `loading`。
  所以交接 addon 里改 `modules` 表的那一步（针对 Bingus 式加载器）在这个 MDL3 上用不上，起作用的只有 `package.loaded`。

## Chef 1.5.x：看门狗和 MDL3 的回调（0.2.1）

**现象**（作者转述评论里的报告，没有日志）：Chef 出了 1.5.1，和交接似乎不兼容，Chef 把 MDL3 当成一直在运行的卡死而终止它，只有 1.4.1 能用；另外 Chef 的 mod 在 MDL3 的菜单里显示错误，实际能正常运行（后一条一直如此，见第二次真机结果）。

**原因**（读 Chef 的代码和更新记录，并在模拟器里复现）：

- 交接时 Chef 会收下当时的 `init`、`update`、`render`、`shutdown`，当作“启动它的那个脚本的回调”，每帧在自己的 `update` 末尾调用（1.5.1 的 `starter.call_boot`）。
- Chef 1.5.0 的更新记录：*"A boot script's update hooks are now covered by the hang watchdog and end when the script stops."* 看门狗的规则（1.5.1 的 `docs/MODDING.md`）：对一个 mod 的任何调用运行超过 3 秒，就用错误中止它，并在下一帧把整个 mod 关掉。
  收下的 MDL3 回调从 1.5.0 起属于这一类：`call_boot` 在调用前登记“这次调用的主人是 MDL3 的启动脚本”，看门狗的钩子每 100 万条指令看一次钟。
- 1.5.1 的更新记录说它修了“看门狗无故关掉健康的 mod”和“游戏偶尔的一次卡顿不再算在 mod 头上”，这没有改变上面这一点：MDL3 的链里只要有一次调用的 Lua 连续跑了 3 秒以上，就算卡死。
- 1.4.1 没有这一条：同样的调用没人计时。所以交接 addon 0.2.0 在 1.4.1 上一直正常，在 1.5.x 上不行。

**复现**（`tests/handoff_sim.sh` 的变体 F，真实的 Chef 核心，Chef 自带的模拟器；用的 1.5.1 就是作者上传的那个包：用标签 `v1.5.1` 的源码重新构建，zip 逐字节一样，sha256 `79b4ff67…370d`）：假 MDL3 的更新链在第 900 帧有一次 3.6 秒 CPU 时间的调用。
0.2.0 + Chef 1.5.1：`the boot script in ...: update error: stopped by the hang watchdog: it ran over 3 s (an endless loop?)`，接着 `switched off boot:... for this session: it hung (a call ran over 3 s)`，屏幕上也有一条 `... STOPPED: IT HUNG (SEE CHEF_LOADER.LOG)` 的提示；那次调用被中止，整条链从此不再被调用（假 MDL3 的 `shutdown` 行也没有了）。
0.2.0 + Chef 1.4.1：没有这一行，链一直跑。0.2.1 + Chef 1.5.1 和 1.4.1：没有这一行，链每帧都跑，慢的那一次在 `chef_handoff.log` 里记一行 `took 3600 ms of CPU time`，Chef 的 mod 照常运行。

**修法**：不把 MDL3 的回调交给 Chef。见上面“回调（0.2.1 起）”。Chef 不拥有、不计时、不终止它们。对方自己用调试钩子的三种做法（每帧设置并还原 / 设置了不还原 / 清除）也在 Chef 1.5.1 上试过，没有出问题。

**没有验证的**：

- **真机。** 我没有看到过 1.5.x 下的日志，所以**不知道真实的 MDL3 在哪一次调用里超过了 3 秒**，也不知道评论里说的“卡死”是不是就是这条看门狗（它的日志行应该是 `... update error: stopped by the hang watchdog ...` 和 `switched off boot:... for this session: it hung`）。
  这个修法不依赖原因：不管 MDL3 的哪次调用多慢，Chef 都不再给它计时。但如果 0.2.1 在 1.5.x 上还是不行，说明还有别的原因。0.2.1 会在 `chef_handoff.log` 里记下超过 0.5 秒的调用和交接前后的调试钩子，请连同 `chef_loader.log`、`MDL.log` 一起发出来。
- **Chef 的 mod 在 MDL3 菜单里的错误**没有处理：本 mod 不去改 MDL3 怎么显示它们。MDL3 的菜单怎么读它的内部状态我没看过，直接改它的表有风险。

## ESC 回飞船闪退：知道什么，不知道什么

三次相关的真机运行（时间是 Chef 日志里的本地时间）：

| 运行 | 版本 | BF5 反馈 | 做了什么 | 结果 |
|---|---|---|---|---|
| 02:16 | 0.1.0 | **没装**：Chef 日志里 87 个补丁文件，没有 BF5 的全局表 `__KILL_FEEDBACK_MOD`，也没有"一个 Lua 超过 4 MB"那一行；作者当时说还没试 MDL3 的 mod | 任务开始后约 27 秒按 ESC 回飞船 | 游戏退出；Chef 日志 `shutdown (clean)`，没有下一个世界 |
| 02:24 | 0.1.0 | 装了：91 个补丁文件，有 `__KILL_FEEDBACK_MOD` | 完成任务，正常结算 | 世界 3 任务 → 4 加载 → 5 飞船，退出时 `shutdown (clean)`；没有问题 |
| （之后） | 0.2.0 | 装了 | 按 ESC 回飞船 | 没有闪退（作者的报告，没有日志） |

- 只出现过一次，原因没有找到。那一次 HUDdle 的日志到退出前一切正常（最后是 `HUD woke from calm`，1.3 秒后 `bye`），Chef 的日志是 `shutdown (clean)`：游戏自己走了退出流程，Chef 没有崩。
- 0.2.0 没有做任何针对它的改动（它只在交接前摘掉 `package.loaded` 里几个 Chef mod 的名字，让 Chef 多启动 Treasure Radar 之类），所以不能说是 0.2.0 修好的。
- 能确定的只有：出现的那一次没有装 BF5，之后装了 BF5 的几次（正常结算、ESC）都没有出现。这可能是巧合，也可能不是；样本太少，没有结论。
- 模拟器里同样的安排（假 MDL3 + 交接 + 真 HUDdle）加"任务中途换世界"不崩，所以 Chef 自己的世界切换逻辑不是原因。
- 再出现时：先把 `MDL.log` 拷出来再重开游戏（它每次启动会被覆盖），连同 `chef_loader.log`、`chef_handoff.log` 一起留着。

## 还没有确认的

- **Chef 1.5.x + 0.2.1 在真机上。** 见“Chef 1.5.x”一节。
- **ESC 闪退的原因。** 见上。
- **别的 MDL3 版本。** 只在 MDL3 3.0.0-dev.29（"protected preview"）上测过。MDL3 以后怎么启动 addon、给 addon 什么全局，可能会变；`chef_handoff.log` 开头列出的全局表能看出变化。
- **别的 Chef mod。** 真机上只有 HUDdle 0.6.11 和 Treasure Radar 0.7.1n。其它 Chef mod 只在模拟器里用替身测过。
- **更长的运行。** 我手上带交接的真机日志里，最长一次约 12 分钟（一局任务）。

## 已经有答案的（原来的疑问）

- **MDL3 会启动 addon 吗？** 会：所有带 `HD2-Addon` 头的 Lua，包括交接 addon，也包括 Chef 的 mod（见第二次真机结果）。
- **Chef 会把 MDL3 的 mod 再启动一份吗？** 真机上没有。MDL3 启动过的 addon 在 `package.loaded` 里，被 Chef 跳过（日志里的 `hd2_data_hub`）；BF5 反馈的 Lua 有 6 MB，Chef 不读超过 4 MB 的 Lua。
  如果哪个 MDL3 的 mod 被再启动了，`chef_loader.log` 里会有 `started mods/<作者>/<名字>`。
- **Chef 在游戏运行 6 秒才启动，它的世界检测和 GUI 受影响吗？** 真机上没有：识别了任务世界，引擎三角形绘制正常，HUDdle 平均 0.7 毫秒/帧。
- **BF5 反馈（MDL3）和交接一起用？** 0.1.0 的 `MDL.log`：它被 MDL3 启用并注册了选项；0.2.0 作者报告正常。
- **Treasure Radar 会运行吗？** 0.1.0 不会：MDL3 "启动"过它，Chef 就当它已经被别的加载器启动而跳过。0.2.0 起来了（作者的试玩报告）。
- **补丁扫描在真机上读得到、认得出吗？** 读得到、认得出：91 个补丁文件 5 毫秒，认出 2 个做给 Chef 的（见第三次真机结果）。

## 许可

本仓库自己的代码和文档用 MIT 许可（根目录的 `LICENSE`），例外见根目录 README 的"许可"。
Chef 的 LICENSE 允许把它的一部分代码拿去让你的 mod 与它配合，只要保留署名；这个 addon 里没有 Chef 的代码，只用了它文档里公开的交接办法。
HUDdle 的代码不在这个仓库里，也没有被复制（测试里的可选 D 要你自己提供 Lua 文件）。
