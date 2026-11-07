# Chef Hand-off for MDL3 0.2.6

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
先看每个 Lua 的前 16 KB（0.2.4 起，前 16 KB 里两样都没有的 addon 会读完再找 `local chef = ...`，见下面 0.2.4 一节），超过 4 MB 的 Lua（比如 BF5 反馈）不读。两样都没有的 Chef mod 认不出来，症状和原来的 Treasure Radar 一样：`chef_loader.log` 里有 `already started by another loader (started)`。
规则的完整说明和会漏掉什么，见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)。

## 0.2.1 比 0.2.0 多了什么：Chef 的卡死看门狗

Chef 被交接时，会把当时游戏里的 `init`、`update`、`render`、`shutdown`（MDL3 和它的 mod 串起来的那条链）收下，在它自己的回调之后每帧运行，当作"一个启动脚本的回调"。
这些回调**放在它的卡死看门狗下面**：一次调用超过 3 秒没返回，就判卡死、终止，整条链被关掉，MDL3 和它的 mod 也就停了。
看门狗是 Chef 1.4.0 加的，1.4.1 和 1.5.x 都这样调用收下的回调（1.4.1 的 `call_boots` 在调用前就登记了主人）。
**更正：** 这里原来写着“只有 1.5.0 起才这样，1.4.1 上一直正常”，根据的是 Chef 1.5.0 更新记录里的一句（"A boot script's update hooks are now covered by the hang watchdog..."），那句说的是另一回事。2026-11-02 用真实的 Chef 1.4.1 在模拟器里补测，0.2.0 下对方的更新链同样被终止。作者的机器上 0.2.0 + 1.4.1 没出事，只是因为 MDL3 没有超过 3 秒的调用。

0.2.1 不再把这些回调交给 Chef：交接时先把它们从全局里摘下来，Chef 加载完再放回去，放在 Chef 自己的回调后面（Chef 的先，MDL3 的链后，游戏照常调用）。
这样 Chef 不拥有、不计时、不终止 MDL3 的回调，不管 MDL3 的某次调用多久，Chef 的看门狗都不会判它卡死。Chef 自己的 mod 照常受看门狗保护。（在真实的 MDL3 下 0.2.1、0.2.2 没有做到，0.2.3 才做到，见下面两节。）
Chef 要是没起来（核心报错），回调原样放回去。MDL3 的某次调用超过 0.5 秒 CPU 时间时，`chef_handoff.log` 会记一行 `took N ms of CPU time`，并且在交接前后各记一行调试钩子的状态（`debug hook before / after`），这些在排查时有用。

**模拟器：** 在 Chef 自带的模拟器里，用真实的 Chef 1.5.1 和 1.4.1 复现了问题（0.2.0 下，对方更新链里一次 3.6 秒的调用被 `stopped by the hang watchdog: it ran over 3 s` 中止，接着 Chef 记 `switched off boot:... for this session: it hung`，整条链从此不再被调用），0.2.1 下不会（没有沙箱的加载器下）。
真实的 MDL3 为什么会有超过 3 秒的调用（或者别的什么让 Chef 判它卡死），没有那样的真机日志，仍然不知道。

## 0.2.2：多记日志（它对原因的猜测是错的）

作者用 0.2.1 + Chef 1.5.1 在真机上跑了一局：HUDdle、Treasure Radar、BF5 反馈都正常，Chef 的看门狗开着，没有判谁卡死。但 `chef_loader.log` 里还是有 `running the callbacks the boot script in ...patch_89 set before it started me (2)`：Chef 仍然收下了 MDL3 的两个回调，这正是 0.2.1 要避免的。

0.2.2 猜的原因是：0.2.1 在摘下回调和 `require` Chef 之间写了两行日志，也许 MDL3 在 mod 写文件时会把回调放回去。所以 0.2.2 让这中间什么也不运行，并多记了几行日志。**这个猜测是错的**：0.2.2 的真机日志里 Chef 照样收下两个，而多记的那几行说清了真正的原因（下一节）。

## 0.2.3 比 0.2.2 多了什么：在游戏真正的全局表上摘

0.2.2 的真机日志：

- `around the globals: metatable of _G: __index=[function] [MDL3/boot:1] __newindex=[function] [MDL3/boot:1]; _G is the global table: no, this addon runs in it: no`：**MDL3 给每个 addon 一个沙箱**，addon 的 `_G` 不是游戏的全局表。
- `still on the globals right after they were taken off: update, shutdown`：在沙箱里，`update`、`shutdown` 是 addon 自己的（MDL3 从它自己的 update 里调用每个 addon 的；`MDL.log` 里的 “It has no shutdown of its own” 说的就是这个），摘不掉；只有 `render` 是游戏全局表上的，摘掉了。
- Chef 的核心是从**游戏的全局表**读回调的，那里 MDL3 自己的 `update`、`shutdown` 一直都在：3 个减去摘掉的 `render`，就是 Chef 看到的 2 个（0.2.0 时是 3 个）。

所以 0.2.1、0.2.2 在真实的 MDL3 下**只把 `render` 拿出了 Chef 的手**；MDL3 的 `update`（MDL3 和它所有 mod 每帧的工作）一直在 Chef 的看门狗下面跑。作者的机器上没有超过 3 秒的调用，所以没出事；评论里那种“MDL3 被判卡死”，0.2.1、0.2.2 在真实的 MDL3 下拦不住。

0.2.3：

- 回调在**游戏的全局表**上摘下和放回：`getfenv(0)`，Chef 的核心被 `require` 时拿到的就是这张表。只有它里面有引擎的 `stingray` 表时才用它，否则照旧用本 mod 的 `_G`（没有沙箱的加载器下，两者是同一张表）。用的是那张表自己的 `rawget`、`rawset`。本 mod 在沙箱里自己的 `update` 不动。
- 那张表要是守着它没有的键（有 `__newindex`，或者把元表藏起来了），就不摘下，换上空的替身：Chef 用普通赋值设它自己的回调，键不存在时这种守卫可能把它们收走。这样 Chef 收下的是替身（什么也不做），它的赋值都落在表上。
- 日志写清用的是哪张表（`the game's global table: ...`）、那里的四个回调在交接前后各是什么、那张表有没有元表；交接后 600 帧里 MDL3 的更新跑了几次（每帧一次是对的；两次说明 Chef 也在跑它）。0.2.2 的同一行在真实的 MDL3 下数的是本 mod 沙箱里的包装，说明不了问题。

**模拟器**：照 0.2.2 的真机日志做了一个 MDL3 沙箱的替身（变体 H，外加 F 那样一次 3.6 秒的慢调用）。0.2.2 在它上面逐行写出和真机一样的日志，真实的 Chef 1.5.1 写出同样的 `(2)`，并在那次慢调用上 `stopped by the hang watchdog`、`switched off boot:... it hung`，MDL3 从此不再更新。
0.2.3 在它上面：Chef 一个回调也没收下，慢调用跑完（日志里 `took 3600 ms of CPU time`），MDL3 每帧都在更新，看门狗没有动作。Chef 1.4.1 和 1.5.1 上全部检查都通过。

**真机（0.2.3 + Chef 1.5.1）：** 作者说跑起来正常。`chef_handoff.log` 里 `the game's global table: getfenv(0) ...`、`metatable of the global table: none`（没有守卫，直接摘下），Chef 加载后游戏全局表上是 Chef 的四个回调，`once a frame`；`chef_loader.log` 里**没有** `running the callbacks ...` 了：Chef 第一次没有收下 MDL3 的任何回调。真机上还没有碰上过超过 3 秒的调用，所以看门狗那一幕只在模拟器里看过。

## 0.2.4 比 0.2.3 多了什么：`local chef = ...` 在 16 KB 之后的 Chef mod

[issue #1](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/1)：NarrowHUD 1.0.6 没有运行。它的 Lua 开头是 220 KB 的数据表，`local chef = ...` 在那之后，也没有 `HD2-Requires` 头行；0.2.3 只看前 16 KB，所以没认出它，Chef 当它已经被别的加载器启动而跳过。

0.2.4：前 16 KB 里两样标记都没有的 addon，把剩下的部分读完，再找行首的 `local chef = ...`（仍然不读超过 4 MB 的 Lua）。`HD2-Requires` 头行还是只在前 16 KB 里找。
多读的只有 addon，开销很小：作者的安装里多读了 2 个 MDL3 的 addon（约 470 KB）；去掉头行的 NarrowHUD 2.2.0（743 KB）在 Lua 5.1 里读完加查找约 7 毫秒。`chef_handoff.log` 的 `patch files read: ...` 那一行后面会多一段 `; N addon(s) read past the first 16 KB`。
同时改了：Lua 开头注释里看门狗的版本（1.4.0 起，不是 1.5.0 起），`mod.json` 的说明（Arsenal 里显示的）也改了这一处，并加上“本 mod 放在最低优先级”。别的行为没有变。细节见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md) 的“0.2.4”一节。

NarrowHUD 1.0.6 本身没有拿到，是用去掉头行的 NarrowHUD 2.2.0 代替的：0.2.3 认不出，0.2.4 认得出。
**真机（0.2.4 + MDL3 3.0.0-dev.33 + Chef 1.5.1，带 NarrowHUD 2.2.0）：** 作者测好了。Treasure Radar 和 NarrowHUD 2.2.0 由 Chef 启动，BF5 反馈由 MDL3 启用，退出 `shutdown (clean)`；补丁扫描多读了 2 个 MDL3 的 addon，没有把它们认成 Chef 的。

## 0.2.5 比 0.2.4 多了什么：Rat's Shared Loader 的 mod，和补丁文件超过 400 个时

**Rat's Shared Loader（HD2 Transmog 要它）。** Rat 放在 MDL3 下面任意位置（不要放最高：那样 MDL3 会被当作它下面的普通 boot 脚本）。交接以后，Chef 会把 Rat 当作一个 boot 脚本拉起来，Rat 再启动 Transmog 这些标了 `-- @loader rat` 的 mod。
0.2.4 下 Transmog 没有运行（Chef 的 F9 里是 “Left to MDL3 chef_handoff, not running”）：MDL3 先“启动”过这些 mod，在 `package.loaded` 里留了东西，Rat 就不再真正启动它们。Transmog 失败留下的占位让 Rat 当作别人已经启动过；运行库留下的“未启动”标记让 Rat 的 `require` 直接返回，运行库的代码没运行，Transmog 也就找不到 `hd2rt`。MDL3 还在 `package.preload` 里给它们挂了自己的加载函数，把当初的结果原样交回。0.2.5 在交接前把这些都拿掉；真在 MDL3 下跑起来、留下别的值的不动。
还剩下的：Chef 的 F9 里它们写 “Run by MDL3 chef_handoff”（实际是 Rat 在运行）；Rat 的回调在 Chef 的卡死看门狗下面；Rat 的加载画面会显示 READY WITH WARNINGS，因为它要求放最高。细节见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md) 的“Rat's Shared Loader 和 HD2 Transmog”一节。

**补丁文件超过 400 个时。** 0.2.4 及以前，补丁扫描最多读到 `patch_400`。[issue #2](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/2) 的日志里，那位玩家有 529 个补丁文件，`chef_handoff.log` 只读了 400 个：再往后的 Chef mod，如果 MDL3 “启动”它时没报错（像 Treasure Radar 0.7.1 那样），本 mod 就不会把它从 `package.loaded` 摘掉，Chef 会跳过它。那一次没出事，因为他的两个 Chef mod 在 MDL3 里都加载失败了。
0.2.5 一直读到连续 8 个号码都不存在为止，仍然最多读 0.5 秒（读不完时日志写 `stopped after 0.5 s, at patch_N`）。别的行为没有变。作者的安装只有 96 个补丁文件，这一条在真机上还没碰上过。

## 0.2.6 比 0.2.5 多了什么：状态文件不再停在 `attempt`

[issue #4](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/4)：一位玩家（Chef 1.5.3，MDL3 3.0.0-dev.43 + HD2 Data Hub 0.6.0，105 个条目）每次交接成功后，`chef_handoff_state.txt` 都停在 `attempt 0.2.5`。下一次启动就当作“上次在交接中崩溃”，不再交接，每次都得先删掉这个文件。
0.2.5 要等回调放回去、几行日志写完才写 `ok`，这中间任何一步出错或者写文件失败，标记就一直是 `attempt`。日志每次启动都清空，出事那一次的记录被下一次覆盖了，所以那位玩家那里具体是哪一步，没有查到。不过那几次 MDL3 都正常工作，说明回调已经放回去了（0.2.5 先放回调、后写 `ok`）：最可能的是写 `ok` 时文件没打开（比如刚写过的文件正被别的程序占着），而 0.2.5 不检查、也不重试。这是推测。作者用同样的版本（dev.43 + 1.5.3 + Data Hub 0.6.0）跑，状态是 `ok`。

0.2.6：

- `require` 一返回就先写 `ok` / `failed`，再读回来核对；没写进去，就在后面的帧里每 30 帧再写一次，最多 20 次（日志写 `could not be written`、`written on a later frame`）。之后的每一步都有保护，出了错回调也照样放回去：0.2.5 在这里出错时，MDL3 的回调就回不到游戏的全局表上了（测试里复现过）。
- 写 `attempt` 时带上时间（`attempt 0.2.6 2026-11-07T00:47:51`），`require` 返回后的第一行日志带着同一个时间（`back from require (attempt 2026-11-07T00:47:51): Chef Shared Loader 1.5.3 started`）。
- 每次启动先把上一次的日志另存为 `chef_handoff.previous.log`，再开新的。状态写着 `attempt`，而上一次的日志里有那次的 `back from require`：那次启动过了交接，只是标记没写进去，这次照常交接。真在交接里崩了的，日志停在交接前，照旧不再试。旧版本留下的 `attempt`（比如 `attempt 0.2.5`）会再试一次。
- 本 mod 被加载器再启动一份时（重新加载），判断“已经有一份”的标记放在游戏的全局表上：第一份还在等交接，就由新的一份接手；已经交接过，新的一份什么也不做。日志不再被第二份清空。
- 没有 `os` 库时补丁扫描也能跑（0.2.5 在那里会出错，退回内置的名单）。

## 安装

1. 你已经有：MDL3 和它的 mod（BF5 反馈）、Chef Shared Loader（1.2.0 以上；真机上测过 1.4.1、1.5.1 和 1.5.3；**请用 0.2.6**，Chef 1.4.x 和 1.5.x 都是）、HUDdle 等 Chef 的 mod。
2. 把 `dist/Chef-Hand-off-for-MDL3-0.2.6.zip` 加进 Arsenal / HD2 Mod Manager 并启用。
3. **优先级：MDL3 的优先级要比 Chef 高**（说的是优先级，不是"先加载"：优先级高的那个启动器，游戏才会运行它）。其余 mod 的顺序没关系（本 mod 见下一步）。
   Chef 和 HUDdle 的说明都要求 Chef 的优先级最高，这里正相反：游戏运行的 boot 必须是 MDL3 的。
   在 Arsenal 里怎么摆，看它的设置：
   - **First mod highest priority**（第一个优先级最高）：列表越靠上优先级越高，MDL3 放在 Chef **上面**。
   - **Last mod highest priority**（最后一个优先级最高）：列表越靠下优先级越高，MDL3 放在 Chef **下面**。
   - 拿不准的话：你原来把 Chef 放在"最高优先级"的那个位置；现在把 MDL3 放到那个位置，Chef 挪到它附近，本 mod 放到另一头（下一步）。
4. **本 mod 放在最低优先级**（最先部署，它的补丁编号就最小）。它没有 boot，放在哪里都不影响它运行；但 MDL3 3.0.0-dev.33 在一位玩家那里只看了前 512 个补丁文件，mod 多的时候，部署得晚的 addon 它发现不了，也就不启动（见下面“不看日志”那张表）。作者自己的安装就是这样摆的（本 mod 在 `patch_0`）。原来这里建议放在 MDL3 和 Chef 之间，mod 多时那里正好在 512 之后。
5. **Purge**，再 **Deploy**。
6. 启动游戏，在标题画面停 10 秒以上，再进一局任务。

运行起来的顺序其实是：MDL3 先运行（游戏运行的是它的 boot），它启动本 mod，6 秒后本 mod 再启动 Chef。这是结果，不是你要在 Arsenal 里摆出来的东西。

## 怎么知道成功了

| 看哪里 | 成功的样子 |
|---|---|
| `%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log` | 有 `the game's global table: getfenv(0) ...`（MDL3 下）和 `back from require (attempt ...): Chef Shared Loader 1.x.x started`；稍后还有一行 `the game's update chain ran 600 times in the first 600 frames after the hand-off: once a frame` |
| `chef_loader.log`（同一个文件夹） | 有 `started by MDL3 chef_handoff 0.2.6, which handed off to me`，没有 `running the callbacks ... set before it started me`，和 `started mods/rosensterner/minimal_hud`、`started mods/chef/treasure_radar`（有 Treasure Radar 的话） |
| `chef_handoff_state.txt`（同一个文件夹） | `ok 0.2.6` |
| `chef_handoff.log` 的中段 | 真机上是这样的：`patch files read: 91 (4 addons, 2 made for Chef, 0 read errors) in 5 ms`、`made for Chef: mods/chef/treasure_radar mods/rosensterner/minimal_hud`、`taken off package.loaded, so that Chef starts them: mods/chef/treasure_radar`。HUDdle 不在最后一行里是正常的：它在 MDL3 里加载就失败了，本来就不在 `package.loaded` 里。0.2.4 起第一行后面可能多一段 `; 2 addon(s) read past the first 16 KB` |
| 游戏里 | 任务中出现 HUDdle 的 HUD；按 F9 出 Chef 的菜单；BF5 反馈照常 |

## 不看日志，先看哪个不工作

| 现象 | 多半是 |
|---|---|
| BF5 反馈（MDL3）正常，HUDdle 没有 | MDL3 的优先级是对的，交接没成功：看 `chef_handoff.log` |
| 同上，而且没有 `chef_handoff.log`；`MDL.log` 开头写着 `discovery ... in 512 archive(s)`，下面没有 `mods/jfredist/chef_handoff` 那一行 | mod 太多，本 mod 排得太靠后：MDL3 3.0.0-dev.33 只看了前 512 个补丁文件，没发现它，也就没启动它。把本 mod 放到最低优先级，Purge 再 Deploy。同样排在后面的 MDL3 mod 也不会运行 |
| HUDdle 正常，BF5 反馈（MDL3）没有（也没有 `chef_handoff.log`） | Chef 的优先级还是高的（顺序摆反了）：把 MDL3 放到更高优先级，Purge 再 Deploy |
| 两个都没有 | 看 `chef_handoff.log` 和 `chef_loader.log` |
| 按 F9 时 Chef 的菜单和某个 mod 自己的菜单一起出来 | 按键冲突，见下面“可能的副作用”：把 Chef 的菜单键改到别的键 |
| Chef 的菜单里某个 mod 只有一行 “Run by MDL3 chef_handoff”，没有开关和设置 | 正常：那个 mod 由 MDL3 运行，Chef 不再启动第二份；它的设置在它自己的菜单里 |

## 日志里的状态

| `chef_handoff.log` 里 | 意思 |
|---|---|
| 文件不存在 | MDL3 没有运行，或者没有启动这个 mod：多半是 Chef 的优先级更高（上一节），也可能这个 mod 没有启用或没有部署，或者 mod 太多、它排得太靠后（`MDL.log` 开头 `in 512 archive(s)`，上一节）。`MDL.log` 里有 `mods/jfredist/chef_handoff: enabled` 却还是没有这个文件的，作者遇到过一次（更新到 MDL3 dev.33 后的第一次启动），原因没找到，再启动一次就好了 |
| `back from require (attempt ...): Chef Shared Loader ... started` | 成功 |
| `Chef Shared Loader is not installed` | 游戏里找不到 Chef 的核心：Chef 没装、没部署，或者被禁用了 |
| `Chef Shared Loader is running already` | Chef 已经在运行（MDL3 自己交接了，或者 Chef 排在最上面），本 mod 什么也没做 |
| `the last launch ended during the hand-off` | 上次启动在交接过程中结束（崩溃），上一次的日志（`chef_handoff.previous.log`）也停在交接前。为了不反复崩，这次没有再试。删掉同一文件夹里的 `chef_handoff_state.txt` 可以再试一次；请把 `chef_handoff.previous.log` 一起发上来 |
| `... says that hand-off came back from require: that launch went on` | 状态写着 `attempt`，但上一次的日志表明那次交接已经返回，只是标记没写进去：这次照常交接 |
| `... ended during a hand-off by chef_handoff 0.2.5. This is 0.2.6: trying once more` | 旧版本留下的 `attempt`：再试一次。这次也崩在交接里的话，下一次就不再试 |
| `chef_handoff_state.txt could not be written (...)` | 状态文件没写进去（括号里是原因），后面的帧会再写；之后有 `written on a later frame` 就好了 |
| `the hand-off did not start Chef (require false: ...)` | Chef 的核心报错，原因在括号里 |

## 出问题时，需要这些文件

`chef_handoff.log`、`chef_handoff.previous.log`（上一次启动的日志）、`chef_loader.log`，MDL3 的 `MDL.log`，如果有 `chef_handoff_state.txt`，再加一句现象：游戏起不来 / 崩溃 / 进游戏没有 HUDdle / BF5 没反应。
`MDL.log` 每次启动都会被覆盖：闪退后先把它拷出来，再重开游戏。
`chef_handoff.log` 开头会列出 MDL3 给 mod 的那些全局表（`CowboyBingusModLoader`、`MDL3`、`HD2Data` ……）里有什么，MDL3 换了版本之后，这能看出它变了什么。
交接那几行里的 `debug hook before / after` 是交接前后这个线程上有没有调试钩子（Chef 的看门狗和 MDL3 自己的预算限制都可能用到），`took N ms of CPU time` 是 MDL3 的某次调用花了多久。
`the game's global table` 是摘回调用的哪张表；`the game's callbacks ...` 几行是四个回调在加载时、交接前、Chef 加载后各是什么（`(its global table)` 是游戏全局表上的，`(the one taken off)` 表示刚摘下的那个又回来了），`around the globals` 是本 mod 的 `_G` 和游戏全局表的元表、`require` 的来历，`update chain ran N times` 是交接后 MDL3 的更新每帧跑几次。

## 可能的副作用

- Chef 启动时（第 6 秒左右，一般在标题画面）会有几十毫秒的卡顿。
- Chef 会把所有带 `HD2-Addon` 头的 mod 都看一遍，已经由 MDL3 启动的它会跳过（靠 `package.loaded` 和 MDL3 登记的列表）；真机日志里能看到 `hd2_data_hub` 这类被跳过。BF5 反馈的 Lua 有 6 MB，Chef 不读超过 4 MB 的 Lua。
  如果哪个 MDL3 的 mod 被 Chef 再启动了一份，`chef_loader.log` 里会有 `started mods/<作者>/<名字>`：在 Chef 的 F9 菜单里把它关掉，并告诉作者。
- MDL3 设置里所有 mod 的分类都显示“未知”（名字正常）：0.2.1 那次真机出现过。那次 MDL3 自己读文件的服务在启动时就坏了（`MDL.log` 里每个 `sys list`、`sys tree` 都是 `attempt to index upvalue 'kernel' (a nil value)`），比交接早 6 秒。下一次（0.2.2）同样的安装就正常了（扫描 1306 毫秒，没有这种错误）。看起来是 MDL3 自己时有时无的问题，没有做过不启用本 mod 的对照。见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)。
- **按键冲突：Chef 的菜单键（默认 F9）。** 有些 mod 两种加载器都能用：Chef 给了它工具表，它就用 Chef 的；没给，它就自己处理按键。MDL3 会启动所有带 `HD2-Addon` 头的 mod，所以在这里它们由 MDL3 运行，以为没有 Chef，可能会用上 Chef 的 F9。作者遇到的是 **First Person Camera by Webbox**（1.0.190）：在 Chef 下它把自己的菜单键设成 F10，特意避开 Chef；在 MDL3 下它的菜单键固定是 F9（F6 切换第一人称），和 Chef 的菜单一按就一起出来。改法：把 Chef 的菜单键改到别的键。在 Chef 的菜单里按 F9 > Chef Shared Loader > Open this menu，按右方向键（或回车），再按新键（比如 F10）。不进菜单也行：关掉游戏，在 `%APPDATA%\Arrowhead\Helldivers2\chef_loader_settings.txt` 里放一行 `_loader<Tab>opt.menu_key<Tab>s<Tab>f10`（四段之间是 Tab 键，不是空格；已有 `opt.menu_key` 那一行就替换它；文件没有就新建）。作者改到 F10 之后两个都正常。之后在这个摄像头 mod 自己的按键设置里不要再选 F10（F9 它本来就不让选）。
- **Chef 菜单里的 “Run by MDL3 chef_handoff”。** 别的加载器（这里是 MDL3）已经启动的 mod，Chef 不再启动第二份，只在菜单里列一行只读的说明，没有开关和设置。Chef 从 `package.loaded` 只能看出是“别的加载器”启动的，就写上把游戏交给它的那一个的名字，也就是本 mod 便条里的 `MDL3 chef_handoff`；实际运行那个 mod 的是 MDL3。这类 mod 的设置在它自己的菜单（或 MDL3 的菜单）里。
- Chef 的 mod（HUDdle 之类）在 MDL3 自己的菜单和日志里会显示错误：`MDL.log` 里 HUDdle 是 `enable failed ... attempt to call field 'time' (a nil value)`，因为 MDL3 给它的不是 Chef，没有 `time`。这是 MDL3 眼里的失败，实际是 Chef 在运行它们，游戏里能正常用（评论里也有人这样说，作者转述）。本 mod 不去改 MDL3 怎么显示它们。

## 卸载

在 mod 管理器里取消勾选，Purge 再 Deploy。`chef_handoff.log`、`chef_handoff.previous.log` 和 `chef_handoff_state.txt` 可以直接删。

## 验证到了哪一步

**真机**（作者的游戏：MDL3 3.0.0-dev.29、3.0.0-dev.33 和 3.0.0-dev.43，Chef 1.4.1、1.5.1 和 1.5.3，HUDdle 0.6.11，BF5 击杀反馈 MDL3 版 2.0.1，Treasure Radar 0.7.1n）：

- 0.1.0（有日志）：交接成功；HUDdle 正常，一局约 8 分钟没有错误；正常结算回飞船没问题；BF5 反馈被 MDL3 启用；Treasure Radar 被 Chef 跳过（0.2.0 修的就是这个）；任务中按 ESC 回飞船闪退过一次，没有找到原因，之后没有再出现。
- 0.2.0（Chef 1.4.1）：作者的试玩报告说 Treasure Radar 起来了，ESC 回飞船没有闪退，BF5 反馈正常（Chef 的日志没传）。`chef_handoff.log` 证实补丁扫描在真机上起作用：读了 91 个补丁文件，认出 Treasure Radar 和 HUDdle 是做给 Chef 的，把 Treasure Radar 从 `package.loaded` 里摘掉，然后 Chef 1.4.1 启动。
- 0.2.1（Chef 1.5.1，有日志）：HUDdle、Treasure Radar 0.7.1、BF5 反馈都正常；看门狗开着，没有 `hung`、`switched off`；退出 `shutdown (clean)`。Chef 仍然收下了两个回调。那次 MDL3 里分类全是“未知”（见“可能的副作用”）。
- 0.2.2（Chef 1.5.1，有日志）：同样都正常，Chef 同样收下两个；日志显示了 MDL3 的沙箱（见上面 0.2.3 一节）。MDL3 的 mod 库扫描这次正常。
- 0.2.3（Chef 1.5.1，有日志）：作者说跑起来正常；Chef 没有收下 MDL3 的任何回调，MDL3 的更新每帧一次、在 Chef 后面；HUDdle、Treasure Radar 启动，退出 `shutdown (clean)`；MDL3 的 mod 库扫描正常。这一次约 1 分 45 秒。
- 0.2.3 + **MDL3 3.0.0-dev.33**（Chef 1.5.1，有日志）：作者说 HUDdle、Treasure Radar、BF5 反馈都正常；日志和 dev.29 下一样（游戏的全局表 `getfenv(0)`，没有元表；Chef 没有收下 MDL3 的回调；`once a frame`；退出 `shutdown (clean)`）。更新到 dev.33 后的第一次启动里本 mod 没有运行，原因没找到，下一次起正常。
- 一位玩家（MDL3 3.0.0-dev.33，837 个补丁文件，有日志）：MDL3 只看了 512 个补丁文件，没发现本 mod（当时放在 MDL3 和 Chef 之间），交接没有发生。所以第 4 步改成了最低优先级；改了以后的结果还没有回报。
- 0.2.4 + MDL3 3.0.0-dev.33（Chef 1.5.1，带 NarrowHUD 2.2.0，有日志）：作者测好了；Chef 启动了 Treasure Radar 0.7.1 和 NarrowHUD 2.2.0，BF5 反馈由 MDL3 启用；`2 addon(s) read past the first 16 KB`（两个 MDL3 的 addon，没认成 Chef 的）；进了一局任务，约 3 分半，退出 `shutdown (clean)`。这次没有装 HUDdle。
- 0.2.4 + Rat's Shared Loader 1.0.1 + HD2 Transmog 1.1.2（MDL3 3.0.0-dev.33，Chef 1.5.1，有日志）：Chef 把 Rat 拉起来了，Rat 的运行库在跑，但 Transmog 和它的通知模块被 Rat 当作“别人已经启动过”而跳过（原因见上面 0.2.5 一节）。
- 0.2.5（Rat's Shared Loader 1.0.1 + HD2 Transmog 1.1.2，MDL3 3.0.0-dev.33，Chef 1.5.1，有日志）：作者测过：Rat 1.0.1 + HD2 Transmog 1.1.2，MDL3 3.0.0-dev.33，Chef 1.5.1，Transmog 起来了（运行库、通知模块、Transmog 都是 `running`，错误 0；交接 mod 拿掉的三个 `package.preload` 加载函数都定义在 `MDL3/boot:1`；Chef 没有判卡死，退出 `shutdown (clean)`）。之前两个没发布的版本不行，原因见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)。
- 0.2.5 + **MDL3 3.0.0-dev.43 + HD2 Data Hub 0.6.0 + Chef 1.5.3**（作者的游戏，有日志）：交接正常，`Chef Shared Loader 1.5.3 started`，`once a frame`，状态文件是 `ok 0.2.5`。
- 0.2.5 + 同样的版本，一位玩家（105 个条目，有日志，[issue #4](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/4)）：交接成功后状态文件停在 `attempt 0.2.5`，之后每次启动都跳过交接。原因没查到（见上面 0.2.6 一节）。
- **0.2.6** + MDL3 3.0.0-dev.43 + Data Hub 0.6.0 + Chef 1.5.3（作者的游戏，有日志）：0.2.6 连续启动两次，每次都交接成功，状态文件都是 `ok 0.2.6`；第二次启动时，第一次的日志留成了 `chef_handoff.previous.log`（日志里 `back from require (attempt 2026-11-07T00:54:25): Chef Shared Loader 1.5.3 started`）。第一次进了一局任务，约 23 分钟，Chef 退出 `shutdown (clean)`。

**模拟器**：在 Chef 自带的模拟器里，用我写的**假 MDL3 启动器**（代替 MDL3 的 boot）测过：启动器在 `init` 里启动 mod / 在 `boot` 里启动 mod（并先用普通 `require` 试一遍 Chef 的 mod）/
同前但只留下 `package.loaded` / 更新链里有一次 3.6 秒的慢调用 / mod 打开文件时就把自己的 `render`、`shutdown` 放回去 / **MDL3 的沙箱（照 0.2.2 的真机日志做的）加一次慢调用** / 自己已经交接给 Chef。几种情况下 Chef 都按预期运行，假 MDL3 的回调每帧照常被调用，游戏自己的 `init` 没有被重复或跳过；用真实的 HUDdle 0.6.11 也试过，能启动。
Chef 1.4.1 和 1.5.1 上都是这样（0.2.3、0.2.4、0.2.5 和 0.2.6），0.2.5 和 0.2.6 在 Chef 1.5.3 上也是。另外试了对方自己用调试钩子的三种情况（每帧设置并还原 / 设置了不还原 / 清除），Chef 1.5.1 上也都没有出问题。
假启动器只是照真机日志和 BF5 的 MDL3 版代码推出来的样子，不是真的 MDL3；沙箱那一个和 0.2.2 的真机日志逐行对得上，但 MDL3 的沙箱可能还有日志没显示出来的地方。

在 MDL3 3.0.0-dev.29、3.0.0-dev.33 和 3.0.0-dev.43（都是 "protected preview"）上测过；MDL3 以后怎么启动 mod 如果变了，上面"出问题时"的文件能看出来。
详细见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)。

## 许可

MIT，见仓库根目录的 [`LICENSE`](../LICENSE)。
