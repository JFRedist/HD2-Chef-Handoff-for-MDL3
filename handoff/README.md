# Chef Hand-off for MDL3 0.2.1

让 **Chef Shared Loader**（以及只能在它上面运行的 mod，比如 **HUDdle**、**Treasure Radar**）和 **MDL3**（以及 BF5 反馈这类 MDL3 mod）在同一个游戏里一起工作。

## 为什么需要它

游戏只运行一个 `boot`：优先级最高的那个补丁里的。Chef 和 MDL3 都想当这个 boot，所以：

- Chef 的优先级高：只有 Chef 运行，Chef 不会运行别的加载器的 boot（它的文档写明了），MDL3 和它的 mod 不工作。
- MDL3 的优先级高：只有 MDL3 运行，Chef 和 HUDdle 不工作。

Chef 的文档（"For other loaders"）给其它加载器留了一个交接办法：设一个便条，再 `require` Chef 的核心，Chef 就在当前的游戏里启动。
这个 mod 在 MDL3 那一边做这件事：进游戏 6 秒后把游戏交给 Chef。之后 MDL3 照常运行它的 mod，Chef 运行它的 mod（HUDdle 之类）。
它不改任何别的东西；没装 Chef 或者 Chef 已经在运行时什么也不做。

## 0.2.0 比 0.1.0 多了什么

第一次真机运行（见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)）显示：MDL3 会把**所有**带 `HD2-Addon` 头的 Lua 都启动一遍，包括 Chef 的 mod，只是给它们的不是 Chef。
HUDdle 在这种启动里会报错，所以 Chef 之后正常启动了它；Treasure Radar 没报错，MDL3 就当它已经在运行，Chef 看到后也跳过了它，所以 Treasure Radar 一直没有运行。
0.2.0 在交接前读游戏的补丁文件（Chef 自己也这样读），找出做给 Chef 的 addon，把它们从 `package.loaded`（以及加载器自己的 `modules` 表，如果有）里摘掉，Chef 就会正常启动它们。
MDL3 自己仍然是按它的方式看这些 mod 的（它的 `MDL.log` 里 HUDdle 是 `enable failed`，Treasure Radar 是 `enabled`），这不影响 Chef 运行它们。

**怎么认出"做给 Chef"的 addon：** MDL3 的 addon 和 Chef 的 addon 用同一个 `-- HD2-Addon:` 头，所以要再看一样东西。带这个头的 Lua 里，有**行首的 `local chef = ...`**
（Chef 把它的工具表交给 addon，Chef 的 mod 习惯在开头用这一行接住它），或者有 `-- HD2-Requires: chef-shared-loader` 头行的，就是做给 Chef 的；MDL3 的 addon 没有这两样。
只看每个 Lua 的前 16 KB，超过 4 MB 的 Lua（比如 BF5 反馈）不读。两样都没有的 Chef mod 认不出来，症状和原来的 Treasure Radar 一样：`chef_loader.log` 里有 `already started by another loader (started)`。
规则的完整说明和会漏掉什么，见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)。

## 0.2.1 比 0.2.0 多了什么：和 Chef 1.5.x 一起用

Chef 被交接时，会把当时游戏里的 `init`、`update`、`render`、`shutdown`（MDL3 和它的 mod 串起来的那条链）收下，在它自己的回调之后每帧运行，当作"一个启动脚本的回调"。
Chef 1.5.0 起，这些回调**放在它的卡死看门狗下面**：一次调用超过 3 秒没返回，就判卡死、终止，整条链被关掉，MDL3 和它的 mod 也就停了。
（Chef 1.5.0 的更新记录里写的："A boot script's update hooks are now covered by the hang watchdog and end when the script stops."）
0.2.0 在 1.5.x 上就会这样；1.4.1 没有这一条，所以 1.4.1 上一直正常。

0.2.1 不再把这些回调交给 Chef：交接时先把它们从全局里摘下来，Chef 加载完再放回去，放在 Chef 自己的回调后面（Chef 的先，MDL3 的链后，游戏照常调用）。
Chef 不再拥有、计时或终止 MDL3 的回调，所以不管 MDL3 的某次调用多久，Chef 的看门狗都不会判它卡死。Chef 自己的 mod 照常受看门狗保护。
Chef 要是没起来（核心报错），回调原样放回去。MDL3 的某次调用超过 0.5 秒 CPU 时间时，`chef_handoff.log` 会记一行 `took N ms of CPU time`，并且在交接前后各记一行调试钩子的状态（`debug hook before / after`），这些在排查时有用。

**状态：** 在 Chef 自带的模拟器里，用真实的 Chef 1.5.1 复现了问题（0.2.0 下，对方更新链里一次 3.6 秒的调用被 `stopped by the hang watchdog: it ran over 3 s` 中止，接着 Chef 记 `switched off boot:... for this session: it hung`，整条链从此不再被调用），0.2.1 下不会；1.4.1 上两版都正常。
**还没有在真机上用 1.5.x 试过。** 真实的 MDL3 为什么会有超过 3 秒的调用（或者别的什么让 Chef 判它卡死），我没有看到过 1.5.x 的日志，所以不知道。如果 0.2.1 在 1.5.x 上还是不行，请把 `chef_handoff.log`、`chef_loader.log` 和 `MDL.log` 发出来。

## 安装

1. 你已经有：MDL3 和它的 mod（BF5 反馈）、Chef Shared Loader（1.2.0 以上；真机上测过 1.4.1，**1.5.x 要用 0.2.1 或更新的版本**）、HUDdle 等 Chef 的 mod。
2. 把 `dist/Chef-Hand-off-for-MDL3-0.2.1.zip` 加进 Arsenal / HD2 Mod Manager 并启用。
3. **优先级：MDL3 的优先级要比 Chef 高**（说的是优先级，不是"先加载"：优先级高的那个启动器，游戏才会运行它）。其余 mod 的顺序没关系。
   Chef 和 HUDdle 的说明都要求 Chef 的优先级最高，这里正相反：游戏运行的 boot 必须是 MDL3 的。
   在 Arsenal 里怎么摆，看它的设置：
   - **First mod highest priority**（第一个优先级最高）：列表越靠上优先级越高，MDL3 放在 Chef **上面**。
   - **Last mod highest priority**（最后一个优先级最高）：列表越靠下优先级越高，MDL3 放在 Chef **下面**。
   - 拿不准的话：你原来把 Chef 放在"最高优先级"的那个位置；现在把 MDL3 放到那个位置，Chef 挪到它旁边的一格。
4. **Purge**，再 **Deploy**。
5. 启动游戏，在标题画面停 10 秒以上，再进一局任务。

运行起来的顺序其实是：MDL3 先运行（游戏运行的是它的 boot），它启动本 mod，6 秒后本 mod 再启动 Chef。这是结果，不是你要在 Arsenal 里摆出来的东西。

## 怎么知道成功了

| 看哪里 | 成功的样子 |
|---|---|
| `%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log` | 最后一行是 `Chef Shared Loader 1.4.x started` |
| `chef_loader.log`（同一个文件夹） | 有 `started by MDL3 chef_handoff 0.2.1, which handed off to me`，和 `started mods/rosensterner/minimal_hud`、`started mods/chef/treasure_radar`（有 Treasure Radar 的话） |
| `chef_handoff.log` 的中段 | 真机上是这样的：`patch files read: 91 (4 addons, 2 made for Chef, 0 read errors) in 5 ms`、`made for Chef: mods/chef/treasure_radar mods/rosensterner/minimal_hud`、`taken off package.loaded, so that Chef starts them: mods/chef/treasure_radar`。HUDdle 不在最后一行里是正常的：它在 MDL3 里加载就失败了，本来就不在 `package.loaded` 里 |
| 游戏里 | 任务中出现 HUDdle 的 HUD；按 F9 出 Chef 的菜单；BF5 反馈照常 |

## 不看日志，先看哪个不工作

| 现象 | 多半是 |
|---|---|
| BF5 反馈（MDL3）正常，HUDdle 没有 | MDL3 的优先级是对的，交接没成功：看 `chef_handoff.log` |
| HUDdle 正常，BF5 反馈（MDL3）没有（也没有 `chef_handoff.log`） | Chef 的优先级还是高的（顺序摆反了）：把 MDL3 放到更高优先级，Purge 再 Deploy |
| 两个都没有 | 看 `chef_handoff.log` 和 `chef_loader.log` |

## 日志里的状态

| `chef_handoff.log` 里 | 意思 |
|---|---|
| 文件不存在 | MDL3 没有运行，或者没有启动这个 mod：多半是 Chef 的优先级更高（上一节），也可能这个 mod 没有启用或没有部署 |
| `Chef Shared Loader ... started` | 成功 |
| `Chef Shared Loader is not installed` | 游戏里找不到 Chef 的核心：Chef 没装、没部署，或者被禁用了 |
| `Chef Shared Loader is running already` | Chef 已经在运行（MDL3 自己交接了，或者 Chef 排在最上面），本 mod 什么也没做 |
| `the last launch ended during the hand-off` | 上次启动在交接过程中结束（崩溃）。为了不反复崩，这次没有再试。删掉同一文件夹里的 `chef_handoff_state.txt` 可以再试一次 |
| `the hand-off did not start Chef (require false: ...)` | Chef 的核心报错，原因在括号里 |

## 出问题时，需要这些文件

`chef_handoff.log`、`chef_loader.log`，MDL3 的 `MDL.log`，如果有 `chef_handoff_state.txt`，再加一句现象：游戏起不来 / 崩溃 / 进游戏没有 HUDdle / BF5 没反应。
`MDL.log` 每次启动都会被覆盖：闪退后先把它拷出来，再重开游戏。
`chef_handoff.log` 开头会列出 MDL3 给 mod 的那些全局表（`CowboyBingusModLoader`、`MDL3`、`HD2Data` ……）里有什么，MDL3 换了版本之后，这能看出它变了什么。
交接那几行里的 `debug hook before / after` 是交接前后这个线程上有没有调试钩子（Chef 的看门狗和 MDL3 自己的预算限制都可能用到），`took N ms of CPU time` 是 MDL3 的某次调用花了多久。

## 可能的副作用

- Chef 启动时（第 6 秒左右，一般在标题画面）会有几十毫秒的卡顿。
- Chef 会把所有带 `HD2-Addon` 头的 mod 都看一遍，已经由 MDL3 启动的它会跳过（靠 `package.loaded` 和 MDL3 登记的列表）；真机日志里能看到 `hd2_data_hub` 这类被跳过。BF5 反馈的 Lua 有 6 MB，Chef 不读超过 4 MB 的 Lua。
  如果哪个 MDL3 的 mod 被 Chef 再启动了一份，`chef_loader.log` 里会有 `started mods/<作者>/<名字>`：在 Chef 的 F9 菜单里把它关掉，并告诉作者。
- Chef 的 mod（HUDdle 之类）在 MDL3 自己的菜单和日志里会显示错误：`MDL.log` 里 HUDdle 是 `enable failed ... attempt to call field 'time' (a nil value)`，因为 MDL3 给它的不是 Chef，没有 `time`。这是 MDL3 眼里的失败，实际是 Chef 在运行它们，游戏里能正常用（评论里也有人这样说，作者转述）。本 mod 不去改 MDL3 怎么显示它们。

## 卸载

在 mod 管理器里取消勾选，Purge 再 Deploy。`chef_handoff.log` 和 `chef_handoff_state.txt` 可以直接删。

## 验证到了哪一步

**真机**（作者的游戏：MDL3 3.0.0-dev.29，Chef 1.4.1，HUDdle 0.6.11，BF5 击杀反馈 MDL3 版 2.0.1，Treasure Radar 0.7.1n）：

- 0.1.0（有日志）：交接成功；HUDdle 正常，一局约 8 分钟没有错误；正常结算回飞船没问题；BF5 反馈被 MDL3 启用；Treasure Radar 被 Chef 跳过（0.2.0 修的就是这个）；任务中按 ESC 回飞船闪退过一次，没有找到原因，之后没有再出现。
- 0.2.0（Chef 1.4.1）：作者的试玩报告说 Treasure Radar 起来了，ESC 回飞船没有闪退，BF5 反馈正常（Chef 的日志没传）。`chef_handoff.log` 证实补丁扫描在真机上起作用：读了 91 个补丁文件，认出 Treasure Radar 和 HUDdle 是做给 Chef 的，把 Treasure Radar 从 `package.loaded` 里摘掉，然后 Chef 1.4.1 启动。

**模拟器**：在 Chef 自带的模拟器里，用我写的**假 MDL3 启动器**（代替 MDL3 的 boot）测过：启动器在 `init` 里启动 mod / 在 `boot` 里启动 mod（并先用普通 `require` 试一遍 Chef 的 mod）/
同前但只留下 `package.loaded`（真实 MDL3 的样子）/ 更新链里有一次 3.6 秒的慢调用 / 自己已经交接给 Chef。几种情况下 Chef 都按预期运行，假 MDL3 的回调每帧照常被调用，游戏自己的 `init` 没有被重复或跳过；用真实的 HUDdle 0.6.11 也试过，能启动。
Chef 1.4.1 和 1.5.1 上都是这样（0.2.1）。另外试了对方自己用调试钩子的三种情况（每帧设置并还原 / 设置了不还原 / 清除），Chef 1.5.1 上也都没有出问题。
假启动器只是照真机日志和 BF5 的 MDL3 版代码推出来的样子，不是真的 MDL3。

只在 MDL3 3.0.0-dev.29（"protected preview"）上测过；MDL3 以后怎么启动 mod 如果变了，上面"出问题时"的文件能看出来。
详细见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)。

## 许可

MIT，见仓库根目录的 [`LICENSE`](../LICENSE)。
