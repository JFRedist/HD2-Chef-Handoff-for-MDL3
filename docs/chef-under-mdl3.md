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
包住全局 `update`，头一行是 `-- HD2-Addon: mods/test_author/battlefield5_kill_feedback`。所以 Chef 在上面，MDL3 不运行；MDL3 在上面，Chef 不运行。

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
| `tests/test_handoff.lua`（40 项） | 假游戏里：6 秒前不交接、之后交接一次、便条内容、状态文件、日志、`update` 链保持；Chef 没装 / 已在运行 / 上次崩溃 / 核心报错 / 各种奇怪的游戏（没有 `can_get`、没有 `update`、坏 dt、加载两次、没有文件夹）。Chef 的全局在假游戏里是只读代理（像真的一样），这一点是真实 Chef 的模拟器测试抓出来的 |
| `tests/handoff_sim.sh`（真实的 Chef，Chef 自带的模拟器） | **A** 假 MDL3 在 `init` 里启动 addon；**B** 假 MDL3 在 `boot` 里启动 addon，并先用普通 `require` 试 Chef 的 mod；**C** 假 MDL3 自己已经交接。检查：Chef 报告被谁交接、自己的 boot stub 没有运行、Chef 的 mod 启动并绘制、交接 addon 不会被 Chef 再启动一次、假 MDL3 的回调（3 个，没有 `init`）每帧照常运行（60 秒约 3600 次）、游戏的 `init` 恰好一次、日志和状态文件。可选 **D**：设置 `HUDDLE_LUA` 用真实的 HUDdle 0.6.11（不在仓库里） |
| 变异检查 | 故意改坏 9 处（没有延迟、没有 `phase`、不检查 Chef 在运行、忽略崩溃标记、不 `pcall`、不写 ok 标记、丢参数、不清便条、不检查 Chef 是否安装）：自写测试全部抓到；模拟器测试抓到其中会影响真实 Chef 行为的三处（延迟、`phase`、已在运行的检查） |

## 没有验证的，和怎么从日志判断

- **真实的 MDL3。** 我没有它，三个假启动器是按 BF5 的 MDL3 版代码和 Chef 的文档推出来的。要看 `chef_handoff.log`：
  - 没有这个文件：MDL3 没启动 addon。需要 MDL3 自己的说明（请上传 MDL3 的包）。
  - 有，但 `update` 不是 function：MDL3 用别的方式调用 addon，日志开头的表里能看出 MDL3 暴露了什么。
  - `not installed`：看 Chef 的补丁是不是被部署了。
  - `started`，但游戏里没有 HUDdle：看 `chef_loader.log` 里 HUDdle 的行。
- **Chef 把 MDL3 的 mod 又启动一份**（MDL3 没把已启动的 mod 登记到 Chef 会看的地方时）：看 `chef_loader.log` 有没有 `started mods/test_author/battlefield5_kill_feedback`。
- **Chef 在运行中途才启动**：模拟器里没问题；真实游戏里 Chef 的世界检测、GUI 创建是否有影响，要看实际。

## 许可

Chef 的 LICENSE 允许把它的一部分代码拿去让你的 mod 与它配合，只要保留署名；这个 addon 里没有 Chef 的代码，只用了它文档里公开的交接办法。
HUDdle 的代码不在这个仓库里，也没有被复制（测试里的可选 D 要你自己提供 Lua 文件）。
