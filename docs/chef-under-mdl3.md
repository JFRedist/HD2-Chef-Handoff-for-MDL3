# 在 MDL3 下运行 HUDdle：让 Chef 在 MDL3 里启动

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

之后 Chef 把游戏当时的回调（MDL3 包过的 `update`、`render`、`shutdown`）记下来，每帧在自己的回调之后运行（日志：*"running the callbacks the boot script ... set before it started me (3)"*），
MDL3 的 mod 不受影响。

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
| `tests/test_handoff.lua`（64 项） | 假游戏里：6 秒前不交接、之后交接一次、便条内容、状态文件、日志、`update` 链保持；Chef 没装 / 已在运行 / 上次崩溃 / 核心报错 / 各种奇怪的游戏（没有 `can_get`、没有 `update`、坏 dt、加载两次、没有文件夹）。Chef 的全局在假游戏里是只读代理（像真的一样），这一点是真实 Chef 的模拟器测试抓出来的 |
| `tests/handoff_sim.sh`（真实的 Chef，Chef 自带的模拟器） | **A** 假 MDL3 在 `init` 里启动 addon；**B** 假 MDL3 在 `boot` 里启动 addon，并先用普通 `require` 试 Chef 的 mod（登记在 Bingus 式的 `modules` 表里）；**E** 同 B，但只留下 `package.loaded`（真实 MDL3 那一次显示的样子）；**C** 假 MDL3 自己已经交接。 B、E 里有一个像 Treasure Radar 的替身（没有 `HD2-Requires` 头，普通 `require` 不报错）：0.1.0 会把它漏掉（和真机日志里同一句 `already started by another loader (started)`），0.2.0 启动它。检查：Chef 报告被谁交接、自己的 boot stub 没有运行、Chef 的 mod 启动并绘制、交接 addon 不会被 Chef 再启动一次、假 MDL3 的回调（3 个，没有 `init`）每帧照常运行（60 秒约 3600 次）、游戏的 `init` 恰好一次、日志和状态文件。可选 **D**：设置 `HUDDLE_LUA` 用真实的 HUDdle 0.6.11（不在仓库里） |
| 变异检查 | 故意改坏 9 处（没有延迟、没有 `phase`、不检查 Chef 在运行、忽略崩溃标记、不 `pcall`、不写 ok 标记、丢参数、不清便条、不检查 Chef 是否安装）：自写测试全部抓到；模拟器测试抓到其中会影响真实 Chef 行为的三处（延迟、`phase`、已在运行的检查） |

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
- **发现二（未解决）：任务中按 ESC 回飞船，游戏闪退。** `chef_loader.log` 里任务开始 27 秒后就是 `shutdown (clean)`，没有 Chef 在回飞船时平时会记的下一个世界（"world 5: not a mission (24 units, 0 levels)"）：
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

做法：交接前读 `data/9ba626afa44a3aa3.patch_N`（和 Chef 同样的读法：72 字节头、32 字节类型行、80 字节条目；每个 Lua 资源只读前 16 KB；超过 4096 条目的补丁和超过 4 MB 的 Lua 不读），
找 `-- HD2-Addon:` 头，并且（行首的 `local chef = ...`，或 `-- HD2-Requires: chef-shared-loader` 头行）的，就是做给 Chef 的。把它们从 `package.loaded`
（和加载器的 `modules` 表里状态是 loaded / loading 的）里摘掉，再交接。读不了补丁时用内置的两个名字（Treasure Radar、HUDdle）。

## 没有验证的，和怎么从日志判断

- **MDL3 的 mod（BF5 反馈）和交接一起用。** 交接本身已在真实的 MDL3 上成功（见上），但还没有和 MDL3 的 mod 一起试过。如果出问题，看 `chef_handoff.log`：
  - 没有这个文件：MDL3 没启动 addon。需要 MDL3 自己的说明（请上传 MDL3 的包）。
  - 有，但 `update` 不是 function：MDL3 用别的方式调用 addon，日志开头的表里能看出 MDL3 暴露了什么。
  - `not installed`：看 Chef 的补丁是不是被部署了。
  - `started`，但游戏里没有 HUDdle：看 `chef_loader.log` 里 HUDdle 的行。
- **Chef 把 MDL3 的 mod 又启动一份**（MDL3 没把已启动的 mod 登记到 Chef 会看的地方时）：看 `chef_loader.log` 有没有 `started mods/test_author/battlefield5_kill_feedback`。
- **Chef 在运行中途才启动**：模拟器里没问题；真实游戏里 Chef 的世界检测、GUI 创建是否有影响，要看实际。

## 许可

Chef 的 LICENSE 允许把它的一部分代码拿去让你的 mod 与它配合，只要保留署名；这个 addon 里没有 Chef 的代码，只用了它文档里公开的交接办法。
HUDdle 的代码不在这个仓库里，也没有被复制（测试里的可选 D 要你自己提供 Lua 文件）。
