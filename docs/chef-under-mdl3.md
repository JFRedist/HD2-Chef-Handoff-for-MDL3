# 在 MDL3 下运行 HUDdle：让 Chef 在 MDL3 里启动

**状态**：交接 addon 0.2.0 在真机上可用（MDL3 3.0.0-dev.29，Chef 1.4.1，HUDdle 0.6.11，Treasure Radar 0.7.1n，BF5 击杀反馈 MDL3 版）。
Chef 1.4.1 和 1.5.x 都会把 0.2.0 交给它的 MDL3 回调放在它的卡死看门狗下面（原来以为只有 1.5.x，见“更正：Chef 1.4.1 也是这样”）。0.2.1、0.2.2 想修，真机上和 Chef 1.5.1 一起跑过（Chef 的 mod 和 BF5 都正常，没有判谁卡死），但 Chef 两次都收下了 MDL3 的两个回调。0.2.2 的日志说明了原因：**MDL3 给每个 addon 一个沙箱**，0.2.1、0.2.2 摘的只是沙箱里的，MDL3 真正的 `update`、`shutdown` 一直在 Chef 的看门狗下面。0.2.3 改在游戏的全局表上摘，**真机上确认了**：Chef 1.5.1 不再收下 MDL3 的任何回调，MDL3 的更新在 Chef 后面每帧运行一次。见“Chef 1.5.x”和“第四次”到“第六次真机结果”。
0.2.1 那次 MDL3 里所有 mod 的分类都显示“未知”：MDL3 自己读文件的服务在启动时就坏了，早于交接；0.2.2 那次又正常了。见“第四次真机结果”和“第五次真机结果”。
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
（0.2.0 和 Chef 1.4.1 的日志里是 *"running the callbacks the boot script ... set before it started me (3)"*）。这样收下的回调在它的卡死看门狗下面（1.4.1 和 1.5.x 都是），见“Chef 1.5.x”一节和“更正：Chef 1.4.1 也是这样”。
所以 0.2.1 在交接前把这四个全局先摘下来（Chef 加载时看到的是空的，就没有东西可收），Chef 加载完再放回去：`update`、`render`、`shutdown` 放在 Chef 自己的回调后面（Chef 的先，MDL3 的链后，用 `pcall` 隔开 Chef 的，MDL3 的错误照原样交给游戏），
`init` 不放回（游戏早就调用过 MDL3 的，也不会再调用）。Chef 没起来（核心报错）时，原样放回。
0.2.2 起，摘下到 Chef 读完全局之间只运行 `rawset` 和 `require`，并把四个回调在加载时、交接前、Chef 加载后各是什么写进日志。
**0.2.3 起，在游戏的全局表上摘**（`getfenv(0)`，Chef 的核心被 `require` 时拿到的就是它），不在本 mod 的 `_G` 上：MDL3 下 addon 的 `_G` 是一个沙箱，见“第五次真机结果”。只有那张表里有引擎的 `stingray` 时才用它，否则用 `_G`（没有沙箱时两者是同一张表）；用那张表自己的 `rawget`、`rawset`。那张表要是守着它没有的键（`__newindex`，或藏起来的元表），四个键都换上空的替身而不是摘下，让 Chef 的赋值落在表上。

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
| `tests/test_handoff.lua`（120 项） | 假游戏里：6 秒前不交接、之后交接一次、便条内容、状态文件、日志、`update` 链保持；0.2.1 起还有：Chef 加载时看不到游戏的回调、`update` / `render` / `shutdown` 里 Chef 的先于链、`init` 是 Chef 的、核心失败时回调原样放回、Chef 的回调报错不影响链、慢调用写进日志、调试钩子的日志；0.2.2 起还有：一个在 mod 打开文件时把自己的 `render`、`shutdown` 放回去的加载器下 Chef 仍然看不到回调（0.2.1 在这一项上失败）、摘不掉的回调会被记下、更新链每帧跑一次 / 两次的判断和日志、回调和全局表的描述行（有没有 `debug`、`getmetatable`、`getfenv` 都能写）；0.2.3 起还有：照 0.2.2 真机日志做的 MDL3 沙箱模型（Chef 在游戏全局表上看不到 MDL3 的回调、MDL3 的更新不在 Chef 里面跑、每帧一次、核心失败时原样放回、`getfenv(0)` 不是游戏的表时照旧），和一个守着新键的游戏全局表（换替身，Chef 的回调落在表上）；Chef 没装 / 已在运行 / 上次崩溃 / 核心报错 / 各种奇怪的游戏（没有 `can_get`、没有 `update`、坏 dt、加载两次、没有文件夹）。Chef 的全局在假游戏里是只读代理（像真的一样），这一点是真实 Chef 的模拟器测试抓出来的 |
| `tests/handoff_sim.sh`（真实的 Chef 1.4.1 和 1.5.1，Chef 自带的模拟器；每个 86 项，加上 D 是 90 项） | **A** 假 MDL3 在 `init` 里启动 addon；**B** 假 MDL3 在 `boot` 里启动 addon，并先用普通 `require` 试 Chef 的 mod（登记在 Bingus 式的 `modules` 表里）；**E** 同 B，但只留下 `package.loaded`（真实 MDL3 那一次显示的样子）；**F** 假 MDL3 的更新链里有一次 3.6 秒 CPU 时间的慢调用（Chef 1.4.1 和 1.5.x 都会把它判成卡死，见下）；**G** 假 MDL3 在有人打开文件时把自己的 `render`、`shutdown` 放回去（0.2.1 之后的猜测，后来证明不是真机的原因，留着检查交接中间不运行别的东西）；**H** MDL3 的沙箱，照 0.2.2 的真机日志做的，加一次 3.6 秒的慢调用（0.2.2 下逐行写出和真机一样的日志，Chef 1.5.1 写出 `(2)` 并把 MDL3 判成卡死；0.2.3 下都没有，见“第五次真机结果”）；**C** 假 MDL3 自己已经交接。 B、E 里有一个像 Treasure Radar 的替身（没有 `HD2-Requires` 头，普通 `require` 不报错）：0.1.0 会把它漏掉（和真机日志里同一句 `already started by another loader (started)`），0.2.0 启动它。检查：Chef 报告被谁交接、自己的 boot stub 没有运行、Chef 的 mod 启动并绘制、交接 addon 不会被 Chef 再启动一次、假 MDL3 的回调（3 个，没有 `init`）每帧照常运行（60 秒约 3600 次）、Chef 没有收下它们、更新链每帧只跑一次、游戏的 `init` 恰好一次、`shutdown` 恰好一次（G）、日志和状态文件。可选 **D**：设置 `HUDDLE_LUA` 用真实的 HUDdle 0.6.11（不在仓库里） |
| 变异检查（一次性的手工检查，脚本没有放进仓库） | 0.1.0：故意改坏 9 处（没有延迟、没有 `phase`、不检查 Chef 在运行、忽略崩溃标记、不 `pcall`、不写 ok 标记、丢参数、不清便条、不检查 Chef 是否安装）：自写测试全部抓到；模拟器测试抓到其中会影响真实 Chef 行为的三处（延迟、`phase`、已在运行的检查）。0.2.0 又加了 11 处（补丁文件的读法、判断做给 Chef 的规则、摘掉的范围等），自写测试全部抓到，只有一个防御性的等价变异除外。0.2.1 再加 7 处（不摘回调、放回时不放在 Chef 后面、顺序反了、核心失败时不放回、不隔开 Chef 的错误、不记慢调用、把 `init` 放回去），全部抓到（其中两处是测试脚本因此直接报错退出）。0.2.2：把 0.2.1 本身当作“变异”跑新测试，守卫模型那一项失败，模拟器的 G 也失败。0.2.3：把 0.2.2 当作变异，沙箱模型的各项和模拟器的 H 都失败；去掉替身那一步，守着新键的全局表那几项失败 |

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

1. 直接读游戏的补丁文件 `data/9ba626afa44a3aa3.patch_0`、`_1` ……（Chef 自己也这样读它们）。连续 8 个号码都不存在就停，总共最多读 0.5 秒。（0.2.4 及以前最多读到 400 号，见“0.2.5”一节。）
2. 每个补丁：开头 4 字节要是 `0xF0000011`；类型数 ≤ 64、条目数 ≤ 4096（再大的是游戏自己的数据，不是 mod 的补丁，跳过）。
3. 条目表（72 字节头、32 字节类型行、80 字节条目）里只看 Lua 类型（类型 id `a14e8dfa2cd117e2`）、长度大于 16 字节且小于 4 MB 的资源，每个先读前 16 KB。（BF5 反馈的 Lua 有 6 MB，所以不读。）
4. 这段源码要以 **`-- HD2-Addon: mods/<作者>/<名字>` 头开头**，才算 addon。
5. 是 addon 之后，看它是不是做给 Chef 的，只认两个标记：
   - **行首的 `local chef = ...`**：Chef 把它的工具表作为 Lua 块的参数交给每个 addon，Chef 的 mod 习惯用这一行接住它。MDL3 的 addon 拿到的是 MDL3 的上下文（有 `log`，没有 `time`），不这样写。
     只认"行首的代码"，注释里提到的（`-- local chef = ...`）不算。**0.2.4 起**，前 16 KB 里两个标记都没有的 addon，会把剩下的部分读完再找这一行（NarrowHUD 1.0.6 前面有 220 KB 的数据表，见“0.2.4”一节）。
   - **`-- HD2-Requires: chef-shared-loader` 头行**：明说需要 Chef。它是开头的头行之一，所以只在前 16 KB 里找。
   交接 addon 自己除外（它的注释里提到 chef）。
6. 认出的名字：从 `package.loaded` 里摘掉（`require` 留下的占位 userdata 不动，Chef 会照常启动那种）；在加载器自己的 `modules` 表里状态是 `loaded` / `loading` 的，改成 `load failed: made for Chef Shared Loader`。然后再交接，Chef 就把它们当作还没启动的 mod 启动。
7. 一个补丁文件都读不了时，用内置的两个名字（Treasure Radar、HUDdle）。

日志里能看到结果：`patch files read: N (X addons, Y made for Chef, …)`、`made for Chef: …`、`taken off package.loaded, so that Chef starts them: …`。

**会漏掉什么。** 既没有 `local chef = ...` 这一行（比如写成 `local c = ...`、`local chef, log = ...`、`local chef = select(1, ...)`，或者前面有缩进）、也没有 `HD2-Requires` 头的 Chef mod 认不出来，
症状和原来的 Treasure Radar 一样：`chef_loader.log` 里 `already started by another loader (started), not started again`。Lua 超过 4 MB 的也认不出来；0.2.3 及更早，标记在前 16 KB 之后的也认不出来。
**会多摘什么。** 一个 MDL3 的 addon 如果恰好有一行行首的 `local chef = ...`，会被摘掉，Chef 会再启动它一份，`chef_loader.log` 里会有 `started mods/<作者>/<名字>`。没见过，也想不出谁会这样写。

`tests/test_handoff.lua` 里每条规则都有例子：有 / 没有 `HD2-Requires` 头、`local chef` 在长注释之后、`local chef` 在 220 KB 的数据之后、`local chef` 正好被 16 KB 那条线切开、16 KB 之后才有 `HD2-Requires` 行和缩进的 `local chef` 的 MDL3 addon（不算）、MDL3 的 addon、超过 4 MB 的 Lua、上千条目的补丁、魔数不对的文件、只在注释里提到 chef、交接 addon 自己、读文件抛错、读不了补丁时的内置名单。

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
- ~~1.4.1 没有这一条：同样的调用没人计时。所以交接 addon 0.2.0 在 1.4.1 上一直正常，在 1.5.x 上不行。~~ **错了**，见下面“更正：Chef 1.4.1 也是这样”。

**复现**（`tests/handoff_sim.sh` 的变体 F，真实的 Chef 核心，Chef 自带的模拟器；用的 1.5.1 就是作者上传的那个包：用标签 `v1.5.1` 的源码重新构建，zip 逐字节一样，sha256 `79b4ff67…370d`）：假 MDL3 的更新链在第 900 帧有一次 3.6 秒 CPU 时间的调用。
0.2.0 + Chef 1.5.1：`the boot script in ...: update error: stopped by the hang watchdog: it ran over 3 s (an endless loop?)`，接着 `switched off boot:... for this session: it hung (a call ran over 3 s)`，屏幕上也有一条 `... STOPPED: IT HUNG (SEE CHEF_LOADER.LOG)` 的提示；那次调用被中止，整条链从此不再被调用（假 MDL3 的 `shutdown` 行也没有了）。
0.2.0 + Chef 1.4.1：~~没有这一行，链一直跑~~ 这一句原来写错了（没有实际跑过），2026-11-02 补测：同样被终止。0.2.1 + Chef 1.5.1 和 1.4.1：没有这一行，链每帧都跑，慢的那一次在 `chef_handoff.log` 里记一行 `took 3600 ms of CPU time`，Chef 的 mod 照常运行。

**修法**：不把 MDL3 的回调交给 Chef。见上面“回调（0.2.1 起）”。这样 Chef 不拥有、不计时、不终止它们（模拟器里如此；真机上 0.2.1 还是让 Chef 收下了两个，见“第四次真机结果”，0.2.2 针对这个）。对方自己用调试钩子的三种做法（每帧设置并还原 / 设置了不还原 / 清除）也在 Chef 1.5.1 上试过，没有出问题。

**没有验证的**：

- **评论里的“卡死”。** 没有 0.2.0 + 1.5.x 的真机日志，所以**不知道真实的 MDL3 在哪一次调用里超过了 3 秒**，也不知道评论里说的“卡死”是不是就是这条看门狗（它的日志行应该是 `... update error: stopped by the hang watchdog ...` 和 `switched off boot:... for this session: it hung`）。
  这个修法不依赖原因：Chef 不收下的回调，它就不给计时。0.2.1 + Chef 1.5.1 的那次真机运行（“第四次真机结果”）没有判卡死，`chef_handoff.log` 也没有记到超过 0.5 秒的调用。
- **Chef 的 mod 在 MDL3 菜单里的错误**没有处理：本 mod 不去改 MDL3 怎么显示它们。MDL3 的菜单怎么读它的内部状态我没看过，直接改它的表有风险。

### 更正：Chef 1.4.1 也是这样（2026-11-02）

作者转述：Chef 1.4.1 下也有人遇到 MDL 被 Chef 的看门狗终止。核对之后，上面“1.4.1 没有这一条”是错的：

- 看门狗是 Chef **1.4.0** 加的（1.4.0 的更新记录：“A hang watchdog: a mod's call that runs on for more than 3 s ... is stopped”）。
- 1.4.1 的 `call_boots`（调用收下的回调的地方）在调用前就 `D.enter(b, t0)`，除了 `shutdown`：收下的 `update`、`render` 在 1.4.1 里已经在看门狗下面。
- 1.5.0 那一句 “A boot script's update hooks are now covered by the hang watchdog and end when the script stops” 说的是另一回事（启动脚本的 update 钩子），我把它读成了“1.5.0 起才这样”。“0.2.0 + Chef 1.4.1 没有这一行”那一句也不是跑出来的。
- 补测（真实的 Chef 1.4.1，提交 `400cc03`，Chef 自带的模拟器）：0.2.0 在变体 F 上 `update error: stopped by the hang watchdog: it ran over 3 s`、`switched off boot:... for this session: it hung`；0.2.2 在变体 H（MDL3 的沙箱）上一样；**0.2.3 在 F 和 H 上都没事**（慢调用跑完，看门狗没有动作）。
- 所以作者的机器上 0.2.0 + 1.4.1 一直正常，只是因为 MDL3 没有超过 3 秒的调用。0.2.3 的修法不依赖 Chef 的版本：MDL3 的回调根本不交给 Chef，哪个版本的看门狗都碰不到。真机上 0.2.3 只和 1.5.1 一起跑过；1.4.1 收下回调的代码和 1.5.1 一样（核心一开始从全局表读那四个），所以结果应当相同。
- 0.2.3 的 Lua 文件开头的注释里还写着 “From 1.5.0 it does that under its hang watchdog”，下一个版本改；已经发布的 v0.2.3 的说明里也有“Chef 1.5.0 起”的说法。

## 第四次真机结果（2026-11-02，0.2.1 + Chef 1.5.1）

作者的报告：HUDdle 和 BF5 反馈都正常运行；MDL3 设置里所有 mod 的名字正常，但分类都是“未知”。传了 `chef_handoff.log`、`chef_handoff_state.txt`（`ok 0.2.1`）、`chef_loader.log`、`MDL.log`、`MDL3.log`。

**交接和 Chef**（时间是日志里的本地时间）：

- 05:09:35 交接 addon 加载；05:09:41（6.0 秒）读了 91 个补丁文件，认出 Treasure Radar 和 HUDdle，把 Treasure Radar 从 `package.loaded` 摘掉；`debug hook before: none`，`debug hook after: [function] (mask "", count 1000000)`（Chef 的看门狗）；`Chef Shared Loader 1.5.1 started (api 1)`。
- Chef：`started by MDL3 chef_handoff 0.2.1`，`hang watchdog: on`，`started mods/chef/treasure_radar 0.7.1`、`started mods/rosensterner/minimal_hud 0.6.11`；认出了任务世界（19296 个单位）；状态行里加载器平均 0.03–0.10 毫秒/帧，HUDdle 0.035–0.076 毫秒；退出 `shutdown (clean)`。
  **没有** `hung`、`switched off`、`stopped by the hang watchdog`。
- **但是有** `running the callbacks the boot script in 9ba626afa44a3aa3.patch_89 set before it started me (2)`。

**那个 (2) 是什么意思。** Chef 在它的核心一开始就数全局上的 `init`、`update`、`render`、`shutdown`（`rawget(_G, k)`），便条里有 `phase = 'init'` 时再去掉 `init`。
所以 Chef 的核心开始运行时，`update`、`render`、`shutdown` 里有两个在全局上，虽然 0.2.1 在 `require` 之前把四个都摘了（`chef_handoff.log` 说摘下的是 `update, render, shutdown`）。
之前几次（0.1.0、0.2.0，Chef 1.4.1）都是 (3)，就是这三个。0.2.1 在摘下和 `require` 之间做的事：写了两行日志（打开 `chef_handoff.log` 两次）、调了一次 `debug.gethook`。

**当时的一个猜测（后来证明是错的，见“第五次真机结果”）。** 如果 MDL3 在 mod 打开文件时会运行它自己的代码（比如为了限制 mod 能写哪里，给 `io.open` 包了一层），并在那时检查、放回它自己的 `render`、`shutdown`，Chef 就正好看到两个。
模拟器的变体 G 照这个样子做了一个假 MDL3：0.2.1 下真实的 Chef 1.5.1 写出了 `running the callbacks the boot script in 9ba626afa44a3aa3.patch_3 set before it started me (2)`，和真机同一句；0.2.2 下没有这一行。
同样能解释的还有别的可能（比如 MDL3 的 `require` 不是游戏原来的那个），这次的日志分不出来。

**（如果这个猜测对，0.2.1 下的后果**：Chef 收下的那两个（`render`、`shutdown`）每次被调用两遍：一遍是 Chef 当作“启动脚本的回调”调用的（又在它的看门狗下面），一遍是 0.2.1 放在 Chef 后面的。
变体 G 里假 MDL3 的 `shutdown` 就打印了两次。`update` 链大概不在那两个里面（没有判卡死；按这个猜测也不在），但日志没有说是哪两个。游戏里没看出问题，但这不是设计的样子。）

**0.2.2 改了什么**：摘下回调到 Chef 读完全局之间，只运行 `rawset` 和 `require`，日志和状态文件挪到前面或后面；并且多记：

| 日志行 | 回答什么 |
|---|---|
| `the game's callbacks: ...`（加载时）、`the game's callbacks before: ...`（交接前） | 四个回调各是哪个函数（地址，和定义它的文件、行号）。MDL3 自己的会显示成 `MDL3/boot` 一类的名字 |
| `around the globals: ...` | `_G` 有没有元表（`__index` / `__newindex`，加载器守着全局时会有）；`_G` 是不是全局表、本 mod 是不是在全局表里运行；`require` 和 `package.loaders` 是 C 函数还是谁的 Lua |
| `still on the globals right after they were taken off: ...` | 摘了还在的（只在有时出现） |
| `the game's callbacks after Chef loaded: ...` | Chef 加载后四个回调是什么；`(the one taken off)` 表示刚摘下的那个又回来了 |
| `the game's update chain ran N times in Chef's first 600 updates: ...` | 交接后 MDL3 的更新链每帧跑几次（本 mod 自己的钩子就在链里，怎么被调用都数得到）：一次是正常的，两次说明 Chef 收下了它，也在跑它 |

下一次真机要看的：`chef_loader.log` 里还有没有 `running the callbacks ... set before it started me`；`chef_handoff.log` 里上面这几行。（结果见“第五次真机结果”。）

**MDL3 里分类全是“未知”。** 这一次的 `MDL.log`：

- 05:09:34 MDL3 启动；05:09:35 `boot phase done; waiting for the sys service`，`SYS_READY`，接着几次 `SYS_BATCH_FAILED E_BUDGET: instruction/time/stop limit`，`sys mkdir ... failed: no result`。
  这些每次启动都有（`MDL3.log` 里 02:23、02:47、04:17、05:09 四次启动各有 16、6、6、7 次），上一次分类正常的那次（02:23，0.2.0 + Chef 1.4.1）也有。
- 05:09:35 `ready: 19 mods known` 之后，mod 库扫描的**每一个** `sys list`、`sys tree`（Arsenal 的 mods 文件夹、每个 mod 的文件夹、游戏的 data 文件夹）都失败：`owner/mdl3_sys/sys:601: attempt to index upvalue 'kernel' (a nil value)`。
  `library: 13 Arsenal mod(s) completed from modsLibrary`、`library: scan complete in 2 round(s), 80 ms`。02:23 那次同一步是 2375 毫秒，没有这种错误。
- 打开 MDL3 菜单时（05:10:22 起）读图标也都失败：`owner/mdl3_sys/sys:694: attempt to index upvalue 'images' (a nil value)`。
- 02:23 那次 MDL3 把 Chef 认作启动加载器、不列出来（`startup loader hidden from the list: Chef Shared Loader 1.4.1 (LOADER)`）；这次没有这一行，而且它去读了 Chef 1.5.1 的图标，所以 Chef 这次出现在了 MDL3 的列表里。

名字来自 Arsenal 的 mod 列表（`modsLibrary`），读得到；分类要读每个 mod 的文件夹，读不了，所以是“未知”。
这一切发生在 05:09:35，交接在 05:09:41：那时交接 addon 只在加载时写了几行日志（这些写入在 MDL3 的 sys 服务就绪之前就已经成功，不依赖它），Chef 的代码还没有加载。
所以**看起来和交接、和 Chef 1.5.1 都无关**，更像是 MDL3 的 sys 服务那一次没有初始化完（`kernel`、`images` 都还是空的）。但这只是从时间顺序推的；没有做过对照实验：
同样的安装多启动几次，看分类是不是有时正常；再不启用交接 addon 启动一两次。02:47、04:17 两次的 `MDL.log` 没有了（每次启动会覆盖），不知道那两次分类是否正常。

## 第五次真机结果（2026-11-02，0.2.2 + Chef 1.5.1）

作者传了 `chef_handoff.log`、`chef_loader.log`、`MDL.log`。

**Chef 那边和上次一样**：`started by MDL3 chef_handoff 0.2.2`，看门狗开着，Treasure Radar 0.7.1 和 HUDdle 0.6.11 启动，认出任务世界（15936 个单位），退出 `shutdown (clean)`，没有 `hung`、`switched off`。
**还是有** `running the callbacks the boot script in 9ba626afa44a3aa3.patch_89 set before it started me (2)`。0.2.2 在摘下和 `require` 之间什么也没写，所以“中间写文件”的猜测是错的。

**0.2.2 多记的几行说清了原因**：

- 加载时：`the game's callbacks: init=nil update=[function] [MDL3/boot:1] render=[function] [MDL3/boot:1] shutdown=[function] [MDL3/boot:1]`。（MDL3 把函数的 `tostring` 改成了 `[function]`，看不到地址。）
- `around the globals: metatable of _G: __index=[function] [MDL3/boot:1] __newindex=[function] [MDL3/boot:1]; _G is the global table: no, this addon runs in it: no; require: [function] [C]; package.loaders: [C] ×5`。
  **MDL3 让每个 addon 在它自己的沙箱里运行**：addon 的 `_G` 不是游戏的全局表（`getfenv(0)` 是另一张表），有 MDL3 的 `__index`、`__newindex`。`require` 和加载器都是游戏原来的 C 函数。
- 交接前：`update` 是本 mod 自己的钩子，`render`、`shutdown` 是 MDL3/boot 的。
- `still on the globals right after they were taken off: update, shutdown`：在沙箱里把它们设成 nil，读回来还在。
- Chef 加载后（沙箱里看）：`update` 是 MDL3/boot 的另一个函数（不是摘下的那个），`render` 是 Chef 的（`core_1.lua:17619`），`shutdown` 是摘下的那个原封不动。
- `the game's update chain ran 600 times in Chef's first 600 updates: once a frame`：这一行在沙箱下数的是本 mod 沙箱里那个包装被调用的次数，说明不了 Chef 有没有在跑 MDL3 的更新（0.2.3 改了，见下）。

**这些合起来是这样**（和 `MDL.log` 里的 “It has no shutdown of its own: anything it changed outside its update stays until restart” 也对得上）：

- MDL3 给每个 addon 的 `update`、`shutdown`（看来还有 `init`）是 addon **自己的**：MDL3 从它自己的 update、shutdown 里调用每个 addon 的。addon 设成 nil 时，`update` 回到 MDL3 给的默认函数，`shutdown` 不变。
- 其余的全局（`render`、`__CHEF_HANDOFF_ADDON` 这类）写到游戏的全局表上（Chef 的日志里看得到 `__CHEF_HANDOFF_ADDON`）。
- Chef 的核心从**游戏的全局表**读回调：那里是 MDL3 自己的 `update`、`render`、`shutdown`。0.2.1、0.2.2 在沙箱里摘，只有 `render` 真的从游戏的全局表上摘掉了，所以 Chef 看到 2 个（`update`、`shutdown`），0.2.0 时是 3 个。
- 所以 0.2.1、0.2.2 在真实的 MDL3 下只把 `render` 拿出了 Chef 的手。**MDL3 的 `update`（MDL3 和它所有 mod 每帧的工作）一直在 Chef 1.5.1 的看门狗下面跑**，作者的机器上只是没有超过 3 秒的调用。评论里那种“MDL3 被判卡死”，0.2.1、0.2.2 在真实的 MDL3 下拦不住。
- 0.2.1 之后说的“Chef 收下的是 `render`、`shutdown`，各跑两遍”也是错的：收下的是 `update`、`shutdown`，由 Chef 调用；沙箱里那份 `update` 包装是 MDL3 调用的。

**模拟器复现**（变体 H）：照上面的规则做了一个 MDL3 沙箱的替身（addon 在自己的环境里，`update`、`shutdown` 是它自己的，设成 nil 时的表现和日志一样，其余写到全局表，`getfenv(0)` 是全局表），再加 F 那样一次 3.6 秒的慢调用。
0.2.2 在它上面写出的日志和真机逐行对得上（`init=nil`、沙箱的元表、`still on the globals ... update, shutdown`、Chef 加载后 `render` 是 Chef 的、`shutdown (the one taken off)`），真实的 Chef 1.5.1 写出 `running the callbacks ... (2)`；
到慢调用那一帧，`the boot script in ...: update error: stopped by the hang watchdog: it ran over 3 s`，接着 `switched off boot:... for this session: it hung`，MDL3 从此不再更新。这就是评论里说的情况。

**0.2.3 改了什么**：

- 回调在**游戏的全局表**上摘下、放回：`getfenv(0)`（正在运行的线程的全局表；Chef 的核心被 `require` 时拿到的就是它，MDL3 的回调也在那里）。只在它里面有引擎的 `stingray` 表时才用；否则照旧用本 mod 的 `_G`。用那张表自己的 `rawget`、`rawset`（沙箱给 addon 的可能是别的）。便条也直接放在那张表上。本 mod 在沙箱里自己的 `update` 不动。
- 那张表要是守着它没有的键（有 `__newindex`，或者 `getmetatable` 拿不到真的元表），就不摘下，四个键都换上什么也不做的替身：Chef 用普通赋值设它的回调，键不存在时这种守卫可能把它们收走（Chef 加载完会调用它自己的 `init`，收走了就会报错）。这样 Chef 收下的是替身。真机上那张表有没有元表，0.2.3 的日志会写（`metatable of the global table: ...`）。
- 交接后的计数改为：游戏全局表上的 `update`（放在 Chef 后面的那个）每被游戏调用一次算一帧，看本 mod 的钩子（由 MDL3 的更新调用）跑了几次。每帧一次是对的；两次说明 Chef 也在跑 MDL3 的更新。
- 变体 H 下：Chef 一个回调也没收下，慢调用跑完（`chef_handoff.log` 里 `took 3600 ms of CPU time`），看门狗没有动作，MDL3 60 秒里更新 3600 次，`shutdown` 一次，计数 `once a frame`。全部模拟器检查在 Chef 1.4.1 和 1.5.1 上都通过。

**当时没有验证的**（真机结果见“第六次真机结果”）：0.2.3 还没在真机上跑过。替身和 0.2.2 的日志逐行对得上，但 MDL3 的沙箱可能还有日志没显示出来的地方，比如游戏的全局表是不是也有守卫、MDL3 会不会把自己的 `update` 放回去。下一次真机要看的：
`chef_handoff.log` 里 `the game's global table: getfenv(0) ...`、`metatable of the global table`、`the game's callbacks before / after Chef loaded (its global table)` 和最后的计数；`chef_loader.log` 里没有 `running the callbacks`。

**MDL3 里的分类这次正常**：同样的安装、同样启用交接，`MDL.log` 里 `library: startup loader hidden from the list: Chef Shared Loader 1.5.1 (LOADER)`、`scan complete in 2 round(s), 1306 ms`，没有 `kernel` 那种错误（只有每次启动都有的 `E_BUDGET` 和读图标的 `nil`）。
所以第四次的“分类全是未知”是时有时无的，更像 MDL3 自己的问题。仍然没有做过不启用交接的对照。

## 第六次真机结果（2026-11-02，0.2.3 + Chef 1.5.1）

作者的报告：跑起来似乎正常。传了 `chef_handoff.log`、`chef_loader.log`、`MDL.log`。

`chef_handoff.log`：

- 加载时，本 mod 沙箱里看：`init=nil update=... render=... shutdown=...`（MDL3/boot 的）；游戏的全局表上：`init`、`update`、`render`、`shutdown` 都是 MDL3/boot 的。
- `the game's global table: getfenv(0) (this addon's _G is a sandbox of its own, not the global table)`：0.2.3 的修法用上了。
- `metatable of the global table: none`：游戏的全局表没有守卫，所以是直接摘下，没有用替身。
- 交接前，游戏的全局表上是 MDL3 的四个；没有 `still on` 那一行（都摘下来了）。
- Chef 加载后，游戏的全局表上四个都是 Chef 的（`core_1.lua:17595 / 17555 / 17619 / 17638`），没有哪个是摘下的又回来了。随后 `update, render, shutdown now run behind Chef's own`。
- `the game's update chain ran 600 times in the first 600 frames after the hand-off: once a frame`：游戏每帧调用一次放在 Chef 后面的那个 `update`，MDL3 的更新（它调用本 mod 的钩子）也正好每帧一次，不在 Chef 里面。

`chef_loader.log`：`started by MDL3 chef_handoff 0.2.3`，看门狗开着，启动了 Treasure Radar 0.7.1 和 HUDdle 0.6.11，认出任务世界（15936 个单位），引擎三角形正常，退出 `shutdown (clean)`。
**没有** `running the callbacks ... set before it started me`：Chef 1.5.1 第一次没有收下 MDL3 的任何回调。也没有 `hung`、`switched off`。

`MDL.log`：mod 库扫描正常（1350 毫秒，Chef 1.5.1 被认作启动加载器），分类应当正常；退出时 MDL3 自己的停止顺序照常（它的 shutdown 在 Chef 的之后被调用）。
有一处和以前不同：`mods/jfredist/chef_handoff: stopped - Off. It has no shutdown of its own`。0.2.2 把它的包装放进了本 mod 沙箱里自己的 `shutdown`，0.2.3 不碰沙箱，所以 MDL3 说本 mod 没有自己的 shutdown。本 mod 也不需要。

**结论**：在真机上，0.2.3 让 MDL3 的回调离开了 Chef 的手：Chef 不再收下它们，MDL3 的更新在 Chef 后面、它的看门狗外面每帧运行一次。
**没有在真机上验证的**：看门狗真的碰上 MDL3 一次超过 3 秒的调用时会怎样（这台机器上没有这种调用；模拟器的变体 H 里 0.2.3 下没事）；更长的运行（这一次约 1 分 45 秒，任务里约半分钟）。

## 第七次真机结果（2026-11-02，0.2.3 + MDL3 3.0.0-dev.33 + Chef 1.5.1）

作者在 Arsenal 里把 MDL3 换成 3.0.0-dev.33（HD2 Data Hub 仍是 0.3.0，本地组件 `mdl_native_bridge.dll` 仍是 0.4.5），别的没变，启动了两次。
补丁的位置：本 mod 在 `patch_0`（最低优先级），Chef 的启动桩在 `patch_86`，MDL3 的 boot 在 `patch_87`，Data Hub 在 `patch_88`；Lua 那个包（`9ba626afa44a3aa3`）一共 89 个补丁文件，`MDL.log` 里的 `in 89 archive(s)` 数的就是它们。

**第二次（16:06，约 2 分钟，进了一局任务）：正常。** 作者：HUDdle、Treasure Radar、BF5 反馈都正常。

- `chef_handoff.log` 和 dev.29 下一样：`the game's global table: getfenv(0) (this addon's _G is a sandbox of its own, not the global table)`，`metatable of the global table: none`；交接前游戏全局表上是 MDL3 的回调（`render` 这次是 First Person Camera 链上去的那个），Chef 加载后是 Chef 的四个；`once a frame`。`patch files read: 89 (5 addons, 2 made for Chef, 0 read errors) in 7 ms`。
- `chef_loader.log`：`start-up: started by the boot in 9ba626afa44a3aa3.patch_87 (MDL3 3.0.0-dev.33 game boot (PUC Lua 5.1, protected preview)), which handed off to me`；没有 `running the callbacks ...`；启动了 Treasure Radar 0.7.1 和 HUDdle 0.6.11；看门狗开着，没有动作；退出 `shutdown (clean)`。
- `MDL.log`：和 dev.29 一样，每个 addon 都是 `enabled (deployed addon, managed by MDL)`，HUDdle 是 `load failed (managed): ... attempt to call field 'time' (a nil value)`（MDL3 用 `require` 启动它，`...` 只是模块名这个字符串，`chef.time` 是 nil），`CowboyBingusModLoader.modules` 里是 `managed` 一类的状态。

**第一次（15:49，更新后的第一次启动，约 3 分半）：本 mod 没有运行。**

- `MDL.log` 里有 `mods/jfredist/chef_handoff: enabled (deployed addon, managed by MDL)` 和 `addon mods/jfredist/chef_handoff: managed`，可是 `chef_handoff.log` 一行都没写（本 mod 一加载就会重写这个文件），`chef_handoff_state.txt` 没变，`chef_loader.log` 里没有这次启动：Chef 没起来。
- 两次启动的 `MDL3.log`，除了时间，逐行一样；`MDL.log` 也看不出区别。磁盘上别处也没有这次写的 `chef_handoff.log`。
- 原因没找到。dev.33 的说明里提到，更新后的第一次启动 MDL3 可能要安装自己的组件、要求重开游戏，但这次的日志里没有看到那样的迹象。之后没有再出现。

## MDL3 dev.33 只看了 512 个补丁文件（一位玩家的日志，2026-11-02）

一位玩家报告交接不工作，猜的原因是“本 mod 不在 MDL3 允许的 managed addon 目录里，`hd2arsenal_mods` 也不是 MDL3 的 allowed roots，MDL3 读不了它”。他传了一份 `MDL.log`（MDL3 3.0.0-dev.33）和一份 `chef_loader.log`（早 20 分钟的另一次启动）。

- `MDL.log` 第 9 行：`coordinator: discovery 3 declared entries in 512 archive(s)`。MDL3 认出的 addon 只有三个：driver_hud、BF5 反馈、aggro_counter（后者 `load failed`）。**没有本 mod。**
- 那份 `chef_loader.log` 是 Chef 在最上面的一次（`started by my start-up stub`，本 mod 当时还没部署）：`found 8 addon(s) ... in 837 patch files`，8 个 addon 在 `patch_99`、`493`、`515`、`543`、`546`、`596`、`640`、`790`。MDL3 认出的正好是 512 以内的两个（aggro_counter 在 99，driver_hud 在 493），512 以后的六个一个也没认出来。
- 所以看起来 MDL3 dev.33 只看前 512 个补丁文件（Lua 那个包的，按编号），部署得晚、编号在 511 以后的 addon 它发现不了，也就不启动。本 mod 照原来的建议放在 MDL3 和 Chef 之间，mod 多的时候编号正好在最后面。
- `sys path outside allowed roots`：那份日志里有 176 行 `sys tree ...` 和读图标的失败，都是 MDL3 的模组库去读 Arsenal 的 mod 文件夹（他放在游戏目录下的 `hd2arsenal_mods`），外加几个 `%LOCALAPPDATA%` 下的 `mkdir`。这些只影响 MDL3 设置里的列表和图标：BF5 反馈的文件夹同样失败，它照样 `enabled (deployed addon, managed by MDL)`。部署好的 addon 是从补丁文件里启动的，不经过这些文件夹。

**限制**：只有这一份日志；两份日志不是同一次启动，中间如果重新部署过，编号可能有变化（在更高优先级加 mod 只会加在后面，不改前面的编号）。512 是不是 MDL3 固定的上限，要等 MDL3 的作者确认。

**改法**：本 mod 没有 boot，放在哪里都不影响它运行，所以安装说明改成“本 mod 放在最低优先级”（最先部署，编号最小）。作者自己的安装本来就是这样（`patch_0`，第七次真机结果）。别的 MDL3 mod 排在 511 以后也会遇到同样的事，这不是本 mod 能修的。

## 0.2.4：标记在 16 KB 之后的 Chef mod（issue #1，NarrowHUD 1.0.6）

[GitHub issue #1](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/1)（MDL3 3.0.0-dev.32，Chef 1.5.1，0.2.3）：交接成功，但 NarrowHUD 1.0.6（Nexus 17882）没有运行。
`chef_handoff.log` 的 `made for Chef:` 里没有 `mods/luka189/narrowhud`，所以它留在 `package.loaded` 里，Chef 当它已经被别的加载器启动而跳过。
报告者查到的原因：0.2.3 每个 Lua 只读前 16 KB；NarrowHUD 1.0.6 的 Lua 有 401095 字节，开头是一大段数据表，`local chef = ...` 在第 222443 字节。他把 16 KB 改成 256 KB，本地就认出来了。

用作者给的 NarrowHUD 2.2.0 核对（只读）：2.2.0 的第 2 行是 `-- HD2-Requires: chef-shared-loader >= 1.2.3`，在前 16 KB 里，0.2.3 本来就认得出（另一位玩家的 `chef_loader.log` 里 NarrowHUD 2.2.0 也是 Chef 启动的）；它的 `local chef = ...` 在第 1648 行、约 305 KB 处。
1.0.6 认不出，说明它没有那一行头，只能靠后面的 `local chef = ...`。把 2.2.0 的那一行头去掉、重新打成补丁再试：0.2.3 认不出，0.2.4 认得出。

**0.2.4 改了什么**：前 16 KB 里两个标记都没有的 addon（只有带 `-- HD2-Addon:` 头的），把剩下的部分读完，再找行首的 `local chef = ...`；仍然不读超过 4 MB 的 Lua。

- 不带头的 Lua 资源还是只读 16 KB；addon 一般只有几个，所以多读的不多：作者的安装里是 2 个（HD2 Data Hub、First Person Camera，都是 MDL3 的，约 470 KB）。去掉头行的 NarrowHUD 2.2.0（743 KB）在 Lua 5.1 里读完加查找约 7 毫秒。
- 16 KB 那条线可能正好把 `local chef = ...` 切成两半：读剩下的部分时，前 16 KB 的最后一行也放进去一起找。
- `-- HD2-Requires:` 那一行只在前 16 KB 里找：它是开头的头行，正文后面的注释里提到它不算。
- 0.5 秒的预算是在两个补丁文件之间检查的，读一个文件中途不会停。
- 没有用报告者的方案 A（固定改成 256 KB）：数据表再大一点的 mod 还会碰上。
- 日志多一段：`patch files read: ... in N ms; K addon(s) read past the first 16 KB`。

在作者自己的补丁文件上模拟（只读，按 0.2.4 的读法读全文）：认出的还是 Treasure Radar 和 HUDdle，没有多认出 MDL3 的 mod。

**测试**：`tests/test_handoff.lua` 加了三个例子（124 项）：`local chef` 在 220 KB 数据之后（认出）、`local chef` 被 16 KB 那条线切开（认出）、16 KB 之后才有 `HD2-Requires` 行和缩进的 `local chef` 的 MDL3 addon（不认）。0.2.3 在新例子上失败 6 项；去掉“前 16 KB 的最后一行一起找”那一步，切开的那个例子失败。
同一个版本里还改了：Lua 开头注释里“看门狗从 Chef 1.5.0 起”改成 1.4.0（见“更正：Chef 1.4.1 也是这样”），`mod.json` 的说明（Arsenal 里显示的那段）也改了这一处，并加了“本 mod 放在最低优先级”。别的行为没有变。

**真机（2026-11-02 16:49，0.2.4 + MDL3 3.0.0-dev.33 + Chef 1.5.1，约 3 分半，进了一局任务）**：作者说测好了。这次装的是 NarrowHUD 2.2.0，没有 HUDdle。

- `chef_handoff.log`：`chef_handoff 0.2.4 loaded`；`patch files read: 87 (5 addons, 2 made for Chef, 0 read errors) in 10 ms; 2 addon(s) read past the first 16 KB`（多读的是 HD2 Data Hub 和 First Person Camera，都没认成 Chef 的）；`made for Chef: mods/chef/treasure_radar mods/luka189/narrowhud`，两个都从 `package.loaded` 摘掉；游戏的全局表 `getfenv(0)`，`once a frame`。
- `chef_loader.log`：`started by MDL3 chef_handoff 0.2.4`；`started mods/chef/treasure_radar 0.7.1`、`started mods/luka189/narrowhud 2.2.0`；认出任务世界（13966 个单位）；没有 `running the callbacks ...`，看门狗没有动作；退出 `shutdown (clean)`。
- `MDL.log`：MDL3 也“启动”过 NarrowHUD（`managed`，它的头两行日志出现在 `MDL.log` 里），和 Treasure Radar 一样没报错，所以要靠摘掉 `package.loaded` 让 Chef 启动它。BF5 反馈被 MDL3 启用，注册了 51 个选项。

**没有在真机上验证的**：NarrowHUD 1.0.6 本身（没有拿到；2.2.0 有 `HD2-Requires` 头行，0.2.3 也认得出），也就是“读完全文才认出”这条路在真机上只走过“没认出”的那一半（两个 MDL3 的 addon）。认出的那一半在自写测试和去掉头行的 2.2.0 上验证过。

## 0.2.5：补丁文件超过 400 个（issue #2 的日志，2026-11-03）

[GitHub issue #2](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/2)（MDL3 3.0.0-dev.33，Chef 1.5.1，0.2.4）：一个 MDL3 的击杀反馈（`mods/codex/cod20_kill_feedback`，“MW2019 & 2023 击杀反馈”，需要 MDL3 和 HD2 Data Hub 0.3）没有运行，别的 MDL3 mod 正常。他传了 `chef_handoff.log` 和 `chef_loader.log`，没有 `MDL.log`。

**那个击杀反馈为什么不运行：MDL3 的 512 个补丁文件。** 他有 529 个补丁文件（`chef_loader.log`：`in 529 patch files`），MDL3 的 boot 在 `patch_527`，MDL3 自带的 HD2 Data Hub 在 `patch_528`，都在 512 之后（见“MDL3 dev.33 只看了 512 个补丁文件”）。
所以 MDL3 没有启动 Data Hub：`chef_handoff.log` 里 `HD2Data = nil`，MDL3 的 `modules` 表里没有 `hd2_data_hub`（17 个条目），最后是 Chef 启动了它（`started mods/codex/hd2_data_hub (9ba626afa44a3aa3.patch_528 ...)`）。那个击杀反馈也不在 `modules` 表里，多半也在 512 之后；它的 Lua 有 28.7 MB，Chef 不读超过 4 MB 的 Lua，它本来也要 MDL3。
Data Hub 和 MDL3 在同一个包里，要一起放在最高优先级，所以补丁文件一多于 512，依赖 Data Hub 的 MDL3 mod（BF5 反馈也是）都会不运行。这要 MDL3 修；本 mod 修不了。玩家能做的是让补丁文件不超过 512 个。

**顺带发现的本 mod 的问题：只读到 `patch_400`。** 同一份 `chef_handoff.log`：`patch files read: 400 (1 addons, 0 made for Chef, 0 read errors) in 210 ms`。扫描的循环写死了 `for n = 0, 400`，所以 401 号以后的补丁都没读，他在 442 和 486 的 HUDdle、Treasure Radar 没被看到。
那一次没出事：两个在 MDL3 里都加载失败了（`load failed (managed)`），本来就不在 `package.loaded` 里，Chef 照样启动了它们。但如果 401 号以后有一个 MDL3 “启动”时不报错的 Chef mod（像 Treasure Radar 0.7.1），本 mod 不会把它摘掉，Chef 就会跳过它。

**0.2.5 改了什么**：去掉 400 的上限，一直读到连续 8 个号码都不存在为止；0.5 秒的预算不变（读不完时日志写 `stopped after 0.5 s, at patch_N`）。那份日志里 400 个补丁文件读了 210 毫秒，照这个速度，0.5 秒能读九百多个。
`tests/test_handoff.lua` 加了一个例子：`patch_7` 到 `patch_449` 是不含 addon 的补丁，`patch_450` 是一个 Chef addon，要被认出、摘掉，日志要数到 449 个补丁文件。0.2.4 在这两项上失败。
**还没有在真机上验证。** 0.2.5 还改了 Rat's Shared Loader 的事，见下一节。

## Rat's Shared Loader 和 HD2 Transmog（0.2.5，2026-11-03）

[Rat's Shared Loader](https://www.nexusmods.com/helldivers2/mods/18234) 1.0.1 是第三个要当 boot 的加载器；HD2 Transmog Foundation 1.1.2（Nexus 16633，连同它的 Cache 和 Style Library）只能在它下面运行，用它带的 HD2 Lua Runtime（`mods/hd2rt/core`）。读了两个包里的 Lua（只读）和 Chef 1.5.1 的源码：

- **Rat 只启动自己标了的 mod**：头几行注释里有 `-- @loader rat` 的（Transmog、Native Notification、运行库自己），别的都留给别的加载器。它也要求放在最高优先级。
- **Rat 在最上面时**，它把下面的 boot 当客人运行：Chef 用 Chef 的交接办法启动；Chef 起来后，普通的 boot 脚本交给 Chef 去跑。MDL3 的 boot 会是其中一个普通 boot 脚本，放在 Chef 的看门狗下面（0.2.3 修的那件事），MDL3 自己也要求最高。所以**不建议** Rat 放最高。
- **Rat 不在最上面时**，谁运行它的启动桩，它就在谁下面启动：只启动自己标了的 mod，不带客人，日志写一条“请把 Rat 放到最高优先级”。Chef 1.5.1 专门支持这样：它把 Rat 的启动桩当普通 boot 脚本运行（`starter.rat_stub`），被交接时也一样（`boot_one` 不看交接）。
- 所以在 MDL3 → 本 mod → Chef 的装法里，Rat 放在 MDL3 下面就行：交接后 Chef 把 Rat 拉起来，Rat 启动 Transmog。

**真机（0.2.4，MDL3 3.0.0-dev.33，Chef 1.5.1，Rat 1.0.1，Transmog 1.1.2）：Transmog 没有运行。** Chef 的 F9 里它是 “Left to MDL3 chef_handoff, not running”。

- Rat 确实起来了（`SharedLoader-loader.log`：`the boot the game runs is not ours: MDL3 ... runs this loader as one of its boot scripts`；Chef：`running another mod's boot script too ...: patch_95 (Rat's Shared Loader)`），运行库 `running`，加载画面也正常出现、关掉。
- 但 Transmog 和 Native Notification 都是 `elsewhere: Chef Shared Loader`：Rat 启动它们时，`package.loaded` 里已经有东西，Rat 就当别的加载器已经启动过。
- 那是 MDL3 留下的：MDL3 也“启动”了它们，都失败了（`MDL.log`：Transmog `module 'hd2rt' not found`，Native Notification `require('ffi') is not available`）。Lua 5.1 的 `require` 先在 `package.loaded` 里放一个占位（light userdata），模块出错时不拿掉。Chef 看到这个占位，记成交接方“试过、没起来”（`left to MDL3 chef_handoff, which didn't start it`）；Rat 的检查（`elsewhere`）只放过空的和它自己的标记表，占位也算“别人启动过”。
- 运行库不受影响：没有 Rat 时它不报错，返回 `{shared_loader = ...}` 这个 Rat 认得的标记，所以 Rat 照样启动了它。

**0.2.5 改了什么**：读补丁时多认一种头，`-- @loader rat`（规则和 Rat、Chef 一样：文件开头那几行注释里，前 4096 字节，`@loader` 行都是 `rat`）。交接前，这些 mod 在 `package.loaded` 里如果只是 `require` 的占位（userdata），就拿掉；真在 MDL3 下跑起来、留下了值的不动，免得 Rat 再启动一份。日志多一行 `made for Rat's Shared Loader: ...; require's placeholder (MDL3 tried it and it failed) taken off, so that it starts them: ...`。
照 Chef 和 Rat 的代码，拿掉以后：Chef 把 Transmog 当作“留给捆着运行库的那个加载器”，自己不启动；接着运行 Rat 的启动桩，Rat 看到 `package.loaded` 里没有它，就启动它。

`tests/test_handoff.lua` 加了例子（130 项）：失败占位被拿掉、真跑过的值留着、`@loader rat` 不在开头注释里的不算。0.2.4 在其中两项上失败。用作者游戏里真实的补丁文件（只读）、照那次 MDL3 留下的样子摆好 `package.loaded`：0.2.5 认出 3 个 Rat 的 mod，拿掉 Transmog 和 Native Notification 的占位，运行库的标记表留着。

**还剩下的**（本 mod 改不了）：Chef 的 F9 里这些 mod 写的是 “Run by MDL3 chef_handoff”（被交接时，Chef 把交接方当成运行它们的加载器）；Rat 的回调在 Chef 的卡死看门狗下面（Transmog 某次调用超过 3 秒，Chef 会把 Rat 整个关掉）；Rat 晚 6 秒才起来，加载画面会显示 READY WITH WARNINGS。
**还没有在真机上验证。**

## 按键冲突：MDL3 下运行、自己用 F9 的 mod（2026-11-02）

作者装了 **First Person Camera by Webbox**（Nexus 17827，Lua 里是 `First Person Camera 1.0.190-release`，资源 `mods/webbox/first_person_prototype`）之后，看到两件事：
Chef 的菜单里它只有一行 “managed by handoff” 一类的说明，没有设置；它自己有独立的设置菜单，也能正常工作。把 Chef 的菜单键从 F9 改到 F10 之后一切正常。

读它的 Lua（只读，没有运行）：

- 头是 `-- HD2-Addon:`，两种加载器都能用。开头一段：`local api=...`，不是表就试 `rawget(G,'chef')`，要有 `loader_version` 和 `bind` 才当作 Chef 的工具表（注释：“Optional Chef API is used only for the original menu shortcut”）。
  没有 `local chef = ...` 那种行首写法，也没有 `HD2-Requires` 头，所以交接 addon 不把它当成做给 Chef 的 mod，留给 MDL3：这是对的，它不用 Chef 也能完整运行。
- 菜单键：有 Chef 的工具表时，它用 `chef.bind('original_menu_key', 'f10', ...)` 把自己的菜单键设成 F10；没有时用固定的 F9（`pressed(c and 'f10' or 'f9')`）。它自己的按键设置不让选 F9。
- 它在启动时链上游戏的 `update`、`render`、`shutdown`，并用全局 `__webbox_first_person` 防止第二份。

在这里 MDL3 启动它（MDL3 启动所有带 `HD2-Addon` 头的 Lua），它拿不到 Chef 的工具表，于是用 F9；交接之后 Chef 也在运行，菜单键默认也是 F9，一按两个菜单一起出来。
Chef 的那一行：`package.loaded` 里有它，Chef 就不再启动它（`starter.elsewhere`），菜单里只列一行只读的说明（`svc.mod_left`，文字是 `'Run by ' .. host`）。
`package.loaded` 只能说明是“别的加载器”，所以 `host` 用的是把游戏交给 Chef 的那一个的名字（`starter.host_name`：交接便条的 `from`，去掉版本号），也就是 “MDL3 chef_handoff”；实际运行它的是 MDL3。

**改法**：把 Chef 的菜单键改到别的键（Chef 的 README：F9 > Chef Shared Loader > Open this menu；或者在 `chef_loader_settings.txt` 里放 `_loader<Tab>opt.menu_key<Tab>s<Tab><键>`）。改到 F10 之后，别再在这个摄像头 mod 里把按键设成 F10。
同样的事可能发生在别的“两种加载器都能用”的 mod 上：它们在这里由 MDL3 运行，按“没有 Chef”的方式选键。

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

- **看门狗真的碰上 MDL3 的慢调用时**：真机上没有出现过超过 3 秒的调用；0.2.3 下 MDL3 的更新已经不在看门狗下面（第六次真机结果），模拟器里慢调用没事。
- **MDL3 里分类全是“未知”**：出现过一次，下一次就正常了；没有做过不启用交接的对照。见“第四次”“第五次真机结果”。
- **ESC 闪退的原因。** 见上。
- **别的 MDL3 版本。** 在 MDL3 3.0.0-dev.29 和 3.0.0-dev.33（都是 "protected preview"）上测过。MDL3 以后怎么启动 addon、给 addon 什么全局，可能会变；`chef_handoff.log` 开头列出的全局表能看出变化。
- **MDL3 dev.33 的 512 个补丁文件**：是不是固定上限，按什么顺序数；那位玩家把本 mod 改到最低优先级以后能不能用。见“MDL3 dev.33 只看了 512 个补丁文件”。
- **更新到 dev.33 后第一次启动时本 mod 为什么没运行。** 见“第七次真机结果”。
- **0.2.5 在真机上**：400 号以后的补丁、Rat's Shared Loader 和 Transmog。见上面两节。
- **别的 Chef mod。** 真机上只有 HUDdle 0.6.11 和 Treasure Radar 0.7.1n。其它 Chef mod 只在模拟器里用替身测过。
- **更长的运行。** 我手上带交接的真机日志里，最长一次约 12 分钟（一局任务，0.1.0）；0.2.3 只有一次约 1 分 45 秒的。
- **真实的 MDL3 为什么会有超过 3 秒的调用**（评论里 1.5.1 判卡死的原因）：没有 0.2.0 + 1.5.x 的日志。0.2.1 那次 Chef 没有判卡死，`chef_handoff.log` 也没有记到超过 0.5 秒的调用。

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
