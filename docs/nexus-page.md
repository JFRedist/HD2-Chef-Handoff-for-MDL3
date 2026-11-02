# Nexus Mods 页面文字（Chef Hand-off for MDL3 0.2.3）

上传页的每一栏分别复制下面的代码块。正文是 BBCode（Nexus 的描述框用的格式），英文为主，简体中文放在页尾的折叠块里。
发布前先看最后的"发布前检查"：有几项只能你在上传页上选，我替不了。

## 名称

```
Chef Hand-off for MDL3
```

## 摘要（Summary）

```
Run Chef Shared Loader mods (HUDdle, Treasure Radar...) and MDL3 mods in the same game. A tiny MDL3 addon that hands the game over to Chef a few seconds after launch. No Chef, HUDdle or MDL3 files included.
```

## 描述（Description，BBCode）

```
[center][size=6][b]Chef Hand-off for MDL3[/b][/size]
[i]Use Chef Shared Loader mods and MDL3 mods in the same game[/i][/center]

[line]

[size=4][b]The problem[/b][/size]
Helldivers 2 runs only one [b]boot[/b] script: the one in the highest-priority patch. [b]Chef Shared Loader[/b] and [b]MDL3[/b] both want to be that boot, so normally you get one or the other:
[list]
[*][b]Chef on top:[/b] Chef and the mods made for it (HUDdle, Treasure Radar ...) run. MDL3 and its mods do not.
[*][b]MDL3 on top:[/b] MDL3 and its mods run (for example the MDL3 build of BF5 Hit and Kill Feedback). Chef and everything made for it do not.
[/list]
HUDdle, for example, exists only as a Chef mod, while the BF5 feedback mod needs MDL3. This mod lets you run both.

[size=4][b]What it does[/b][/size]
It is a tiny addon that MDL3 starts like any other addon. About 6 seconds into the game it hands the game over to the real Chef Shared Loader, using the hand-off that Chef's own documentation describes for other loaders. After that MDL3 keeps running its mods and Chef runs its mods.
[list]
[*]Nothing of Chef, HUDdle or MDL3 is included or changed. Lua only: no DLLs, no memory access.
[*]If Chef is not installed, or is already running, it does nothing.
[*]It writes two small files, [i]chef_handoff.log[/i] and [i]chef_handoff_state.txt[/i], to [i]%APPDATA%\Arrowhead\Helldivers2[/i]. That is all.
[/list]

[size=4][b]New in 0.2.0: Chef mods that MDL3 "started" without Chef[/b][/size]
MDL3 starts every addon that has an [i]HD2-Addon[/i] header, Chef's mods too, but without Chef. Some of them (Treasure Radar) do not fail at that point, so Chef thinks another loader already started them and skips them. Before the hand-off, 0.2.0 now reads the game's patch files, recognises the addons made for Chef and takes them off [i]package.loaded[/i], so Chef starts them properly.

[size=4][b]New in 0.2.3: works with Chef Shared Loader 1.5.x[/b][/size]
When Chef is handed the game it also takes over the game's callbacks (MDL3's own update, render and shutdown) and runs them itself. From Chef 1.5.0 those callbacks sit under Chef's hang watchdog: one call that runs for more than 3 seconds counts as a hang, and the whole chain is switched off, MDL3 with it. The hand-off now takes them off the game's global table while Chef loads and puts them back behind Chef's own, so that Chef does not keep them.
The earlier attempts (0.2.1, 0.2.2, never uploaded here) took them off the addon's own globals, but MDL3 runs every addon in a sandbox of its own, so Chef still kept MDL3's update and shutdown; my 0.2.2 log showed it. If you use Chef 1.5.x, use 0.2.3. (Tested in the game with Chef 1.5.1: Chef no longer keeps any of MDL3's callbacks.)

[size=4][b]Requirements[/b][/size]
[list]
[*][b]MDL3[/b], with the MDL3 mods you like (for example [url=https://www.nexusmods.com/helldivers2/mods/16927]BF5 Hit and Kill Feedback, MDL3 build[/url])
[*][b]Chef Shared Loader 1.2.0 or newer[/b] (1.4.1 and 1.5.1 tested in the game; for Chef 1.5.x use 0.2.3): [url=https://github.com/Th3chef/Chef-Shared-Loader/releases/latest]download[/url]
[*]The Chef mods you want, for example [url=https://www.nexusmods.com/helldivers2/mods/18108]HUDdle[/url] or [url=https://www.nexusmods.com/helldivers2/mods/18265]Treasure Radar[/url]
[*]A mod manager that installs Helldivers 2 patch zips (Arsenal or HD2 Mod Manager)
[/list]

[size=4][b]Installation[/b][/size]
[list=1]
[*]Install MDL3, Chef Shared Loader and your mods as usual.
[*]Add [b]Chef-Hand-off-for-MDL3-0.2.3.zip[/b] to your mod manager and enable it.
[*][b]Give MDL3 a higher priority than Chef.[/b] This is the opposite of what the Chef and HUDdle instructions say (they want Chef on top): the game has to run MDL3's boot. In Arsenal, if the setting is [i]First mod highest priority[/i], put MDL3 [b]above[/b] Chef in the list; if it is [i]Last mod highest priority[/i], put MDL3 [b]below[/b] Chef. If you are unsure: put MDL3 where Chef used to be and Chef right next to it. The order of all other mods does not matter.
[*]Purge, then Deploy.
[*]Start the game, wait about 10 seconds at the title screen, then start a mission.
[/list]

[size=4][b]How to tell it works[/b][/size]
[list]
[*]In [i]%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log[/i] there is a line [i]Chef Shared Loader 1.x.x started[/i] (about 6 seconds after launch), and a little later [i]the game's update chain ran 600 times in the first 600 frames after the hand-off: once a frame[/i]. Before them you see lines like [i]patch files read: 91 (4 addons, 2 made for Chef, 0 read errors)[/i].
[*][i]chef_loader.log[/i] (same folder) contains [i]started by MDL3 chef_handoff 0.2.3, which handed off to me[/i], and no line [i]running the callbacks ... set before it started me[/i].
[*]In game: the HUDdle HUD in missions, Chef's menu on F9, and your MDL3 mods working as before.
[/list]

[size=4][b]Troubleshooting[/b][/size]
[list]
[*][b]MDL3 mods work, Chef mods do not:[/b] the hand-off did not start Chef. Read chef_handoff.log. "Chef Shared Loader is not installed" means Chef's patch is not deployed or is disabled.
[*][b]Chef mods work, MDL3 mods do not (and there is no chef_handoff.log):[/b] Chef still has the higher priority. Swap them, Purge, Deploy.
[*][b]A Chef mod does not start and chef_loader.log says "already started by another loader (started), not started again":[/b] 0.2.0 only recognises Chef addons that have a line starting with "local chef = ..." or a "-- HD2-Requires: chef-shared-loader" header. Tell me which mod it is.
[*][b]Chef 1.5.x, and chef_loader.log says "switched off boot:... for this session: it hung":[/b] you are on 0.2.0. Chef judged MDL3's callbacks to be hung and stopped them. Update to 0.2.3.
[*][b]"the last launch ended during the hand-off":[/b] the previous launch ended while handing off, so it was not tried again, to avoid a crash loop. Delete chef_handoff_state.txt to try again.
[/list]

[size=4][b]Known issues[/b][/size]
[list]
[*]With 0.1.0 the game closed once when I pressed ESC to return to the ship in the middle of a mission. I could not reproduce it (not with 0.2.0 either) and I do not know the cause. If it happens to you, copy MDL.log before you restart the game and send it with chef_handoff.log and chef_loader.log.
[*]MDL3's own menu and log show Chef mods such as HUDdle as failed or with an error ("enable failed"). That is MDL3's view (it gives addons its own context, not Chef's); Chef is the one running them, and they work in game.
[*]Once, MDL3's mod list showed every mod's category as unknown (the names were fine). In that launch MDL3's own file service failed at startup, 6 seconds before the hand-off (MDL.log: attempt to index upvalue 'kernel' (a nil value)), and the next launch with the same setup was fine, so it looks like an intermittent MDL3 issue; I have not tested a launch without this mod.
[*]0.2.3 has had one short test run in the game so far (Chef 1.5.1). If it does not work for you, please send chef_handoff.log, chef_loader.log and MDL.log.
[*]Tested only with MDL3 3.0.0-dev.29, a preview build. A different MDL3 version may start addons differently.
[/list]

[size=4][b]Tested with[/b][/size]
MDL3 3.0.0-dev.29, Chef Shared Loader 1.4.1 (0.1.0, 0.2.0) and 1.5.1 (0.2.1, 0.2.2), HUDdle 0.6.11, Treasure Radar 0.7.1n, BF5 Hit and Kill Feedback (MDL3 build) 2.0.1. 0.2.3: Chef 1.5.1 in the game, and Chef 1.4.1 and 1.5.1 in Chef's simulator.

[size=4][b]Good to know[/b][/size]
[list]
[*]Cost: reading the patch files takes a few milliseconds (5 ms for 91 patch files here). Chef starting causes a hitch of a few tens of milliseconds, once, normally on the title screen.
[*]Uninstall: disable it in your mod manager, Purge, Deploy. You can delete chef_handoff.log and chef_handoff_state.txt.
[/list]

[size=4][b]Credits and links[/b][/size]
[list]
[*][b]Chef Shared Loader[/b] by Th3chef. The hand-off used here is the one in Chef's own documentation ("Everything here is free to copy into your loader as it is").
[*][b]HUDdle[/b] by rosensterner, and [b]Treasure Radar[/b], [b]MDL3[/b] and [b]BF5 Hit and Kill Feedback[/b] by their authors. None of their files are included.
[*]Source code, issue tracker and documentation: [url=https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3]GitHub[/url] (MIT license).
[*]The code was written with the help of Claude (Anthropic's AI) and tested in the real game by me.
[/list]

[spoiler][b]Technical details[/b]
The game's patch files (data/9ba626afa44a3aa3.patch_N) are read directly, the same way Chef reads them. Only Lua resources between 16 bytes and 4 MB are looked at, and only their first 16 KB, in patches with at most 4096 entries (bigger ones are built game data).
An addon is a Lua resource that starts with a "-- HD2-Addon: mods/author/name" header. It counts as made for Chef if it has a line that starts with "local chef = ..." (Chef hands its helper table to each addon as the chunk argument) or a "-- HD2-Requires: chef-shared-loader" header line. Mentions in comments do not count.
Those names are taken off package.loaded (and marked as not running in a Bingus-style loader's modules table, if it has one). The game's init, update, render and shutdown are taken off the game's global table (getfenv(0): MDL3 runs addons in a sandbox, so not the addon's own _G), so that Chef finds no callbacks to keep (from 1.5.0 it would run them under its hang watchdog), and put back behind Chef's own once it has loaded. If that table guards keys it does not have, empty stand-ins are put there instead. Between taking them off and requiring Chef nothing else runs (no log line, no file). The hand-off itself: the note ChefSharedLoaderHandoff = { from = ..., phase = 'init' } is set and Chef's core (mods/chef_shared_loader/core_1) is required.
If the patch files cannot be read, a built-in list (Treasure Radar, HUDdle) is used.
A Chef mod that has neither marker is not recognised.
[/spoiler]

[spoiler][b]简体中文[/b]
[b]解决什么问题：[/b]游戏只运行优先级最高的补丁里的 boot。Chef Shared Loader 和 MDL3 都想当这个 boot，所以默认只能有一个工作：Chef 在上，HUDdle、Treasure Radar 等 Chef mod 能用，MDL3 和它的 mod（比如 BF5 击杀反馈的 MDL3 版）不能用；MDL3 在上则相反。
[b]它做什么：[/b]这是一个由 MDL3 启动的小 addon，进游戏约 6 秒后，按 Chef 文档里写明的交接办法把游戏交给真正的 Chef。之后 MDL3 照常运行它的 mod，Chef 运行 Chef 的 mod。不包含也不修改 Chef、HUDdle、MDL3 的任何文件；没装 Chef 或 Chef 已在运行时什么也不做。
[b]0.2.0 新增：[/b]MDL3 会把 Chef 的 mod 也"启动"一遍（给的不是 Chef）。没报错的（Treasure Radar）会被 Chef 当作已经被别的加载器启动而跳过。现在交接前先读游戏的补丁文件，认出做给 Chef 的 addon，把它们从 package.loaded 里摘掉，Chef 就会正常启动它们。
[b]0.2.3 新增：[/b]和 Chef 1.5.x 一起用。Chef 1.5.0 起会把交接来的游戏回调（MDL3 自己的 update、render、shutdown）放在它的卡死看门狗下面，一次调用超过 3 秒就判卡死、整条链被关掉，MDL3 也就停了。现在 Chef 加载期间先把这些回调从游戏的全局表上摘下，加载完放回它自己的回调后面。之前的 0.2.1、0.2.2（没在这里上架过）摘的是 addon 自己的全局，可 MDL3 给每个 addon 一个沙箱，所以 Chef 照样收着 MDL3 的 update 和 shutdown；我 0.2.2 的日志显示了这一点。用 Chef 1.5.x 请用 0.2.3（真机上用 Chef 1.5.1 试过：Chef 不再收下 MDL3 的回调）。
[b]需要：[/b]MDL3；Chef Shared Loader 1.2.0 以上（真机测试过 1.4.1 和 1.5.1，1.5.x 请用 0.2.3）；Arsenal 或 HD2 Mod Manager。
[b]安装：[/b]
1. 照常安装 MDL3、Chef 和你要用的 mod。
2. 把 Chef-Hand-off-for-MDL3-0.2.3.zip 加进 Arsenal / HD2 Mod Manager 并启用。
3. [b]MDL3 的优先级要比 Chef 高[/b]（这和 Chef、HUDdle 的说明相反）。Arsenal 的设置是 First mod highest priority，就把 MDL3 放在 Chef 上面；是 Last mod highest priority，就放在下面。拿不准：把 MDL3 放到你原来放 Chef 的位置，Chef 挪到它旁边。其余 mod 的顺序没关系。
4. Purge，再 Deploy。启动游戏，在标题画面停 10 秒以上，再进一局任务。
[b]怎么知道成功了：[/b]%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log 里有 Chef Shared Loader 1.x.x started，稍后有 update chain ran 600 times ... once a frame；chef_loader.log 里有 started by MDL3 chef_handoff 0.2.3, which handed off to me，没有 running the callbacks；任务中出现 HUDdle，按 F9 出 Chef 的菜单，MDL3 的 mod 照常。
[b]出问题时：[/b]MDL3 的 mod 正常、Chef 的 mod 没有：看 chef_handoff.log。Chef 的 mod 正常、MDL3 的 mod 没有（也没有 chef_handoff.log）：Chef 的优先级还是高的，对调后 Purge 再 Deploy。反馈时请附上 chef_handoff.log、chef_loader.log 和 MDL.log（MDL.log 每次启动会被覆盖，闪退后先拷出来再重开游戏）。
[b]已知问题：[/b]0.1.0 下任务中按 ESC 回飞船闪退过一次，原因没找到，之后没有再出现。只在 MDL3 3.0.0-dev.29（预览版）上测过。Chef 的 mod 在 MDL3 的菜单里会显示错误，实际能正常运行。有一次 MDL3 里所有 mod 的分类都显示“未知”：那次 MDL3 自己读文件的服务在启动时就坏了，比交接早 6 秒，下一次同样的安装就正常了，看起来是 MDL3 自己时有时无的问题。0.2.3 在真机上只试过一次短的。
[b]来源：[/b]代码、文档和问题反馈在 GitHub（MIT 许可）。代码是在 Claude（Anthropic 的 AI）的帮助下写的，由我在真实游戏里测试。
[/spoiler]
```

## 文件（File）

| 栏 | 内容 |
|---|---|
| 文件 | `Chef-Hand-off-for-MDL3-0.2.3.zip`（GitHub 的 Release 页下载；sha256 `e06fd3eac2d5d9ff1d0678fda0ebd8c7d32926b3a3478f4de7bbc8755eb82ea6`） |
| 名称 | `Chef Hand-off for MDL3` |
| 版本 | `0.2.3` |
| 类型 | Main file |

文件说明：

```
Mod manager zip (Arsenal / HD2 Mod Manager). Needs MDL3 and Chef Shared Loader 1.2.0+ (for 1.5.x use 0.2.3). MDL3 must have a higher priority than Chef.
```

## 更新说明（Changelog）

0.2.3（新的这一版；0.2.1、0.2.2 没有上架过）：

```
Works with Chef Shared Loader 1.5.x. Chef 1.5 runs the callbacks it is handed under its hang watchdog and would switch MDL3 off after one call over 3 s; MDL3's callbacks are now taken off the game's global table while Chef loads and put back behind Chef's own (MDL3 runs addons in a sandbox, so the addon's own globals were the wrong place). The log says which table was used, what was on it before and after, and whether MDL3's update then runs once a frame. (Tested in the game with Chef 1.5.1, and in Chef's simulator with Chef 1.4.1 and 1.5.1.)
```

0.2.0（如果已经上架过，这是上一版的说明）：

```
First public release. Chef mods that MDL3 starts without Chef (Treasure Radar) are no longer skipped by Chef: before the hand-off, the addons made for Chef are recognised by reading the patch files and taken off package.loaded.
```

## 发布前检查

0. **已经上架过 0.2.0 的话**：把 0.2.3 作为新版本上传（同一个 mod 页面，新文件），并在页面上置顶一条说明：用 Chef 1.5.x 请用 0.2.3。0.2.0 的文件可以留着给 Chef 1.4.x 用户，也可以归档。（0.2.3 已经在你的真机上跑过一次，这一页按那次的结果改过了。）
1. **AI 标签。** Nexus 要求给 AI 生成的内容打标签。我这里打不开 Nexus，只从搜索摘要看到：有一个 *AI-Generated Content* 标签（摘要里写的范围包括代码），和一个 *AI Assisted* 标签（AI 只有有限参与时用）；没打标签可能被处理。这个 mod 的代码是我写的，所以请在上传页选 *AI-Generated Content*，具体选项以页面上的原文为准。描述末尾的那句 Claude 的说明请保留。
2. **要求（Requirements）栏。** 把 MDL3 的页面加进去；Chef Shared Loader 如果在 Nexus 上也有页面就一起加。我没找到它们的 Nexus 链接，所以描述里 MDL3 没有链接，Chef 的链接指向它的 GitHub Release（它的 README 里写的下载地方）。
   描述里其余的 Nexus 链接：HUDdle（18108）和 BF5 的 MDL3 版（16927）的编号是你给我的；Treasure Radar 的编号 18265 是我从你 Arsenal 里它的文件夹名（`Treasure Radar 18265 0.7.1n …`）取的，我打不开 Nexus，发布前请点一下确认。
3. **图片。** 已经做好 6 张 1920×1080 的英文图解（`promo/nexus-images.html`，用 `node promo/render.js nexus out/nexus` 生成；每张不到 1 MB）。按这个顺序传，第一张当主图：

   | 文件 | 标题（Nexus 图片的 caption） |
   |---|---|
   | `01-hero.png` | Chef Hand-off for MDL3: run Chef mods and MDL3 mods in the same game |
   | `02-the-problem.png` | The problem: the game runs one boot script, so it is Chef or MDL3 |
   | `03-how-the-hand-off-works.png` | How it works: MDL3 keeps the boot, the addon hands the game to Chef after 6 s |
   | `04-give-mdl3-the-higher-priority.png` | Install tip: MDL3 needs the higher priority (both Arsenal settings) |
   | `05-new-in-0.2.0.png` | New in 0.2.0: Treasure Radar and other Chef mods are no longer skipped |
   | `06-how-to-tell-it-works.png` | How to tell it works: the log lines to look for |

   它们是**图解，不是游戏截图**；图里的日志行和数字来自你真机的 `chef_handoff.log`（图上写了"excerpt / real run"）。
   建议再自己截 1～2 张真机图补在后面：同一局任务里 HUDdle 和一个 MDL3 mod（比如 BF5 击杀反馈）同时在起作用，我做不了这个。
   描述里用 `[img]` 只能贴外链图，所以这些图作为页面的图库图片上传即可。
   **AI 标签**：Nexus 的搜索摘要里提到还有一个给"AI 生成的宣传图（比如横幅）"的标签。这些图是我用代码（HTML/CSS 渲染）画的，不是图像生成模型生成的，但设计和文字是 AI 完成的；上传页如果有这类选项，我建议选上，具体以页面原文为准。
4. **分类和标签。** 选最接近"工具 / 加载器"的分类和标签，我不知道 Helldivers 2 版块现有的选项。
5. **权限。** 代码是 MIT，所以最一致的做法是放开：允许别人在署名的前提下使用、修改、再发布。具体选哪项由你决定。
6. **链接里的仓库名。** 描述里的 GitHub 链接用的是现在的仓库名 `HD2-Chef-Handoff-for-MDL3`；以后再改名要同步改。
7. **BBCode。** 我只用了常见的标签（`b i size center list url line spoiler`），并且折叠块里只放了加粗和纯文本，因为 Nexus 的折叠块在里面有字号、列表、引用、代码、居中时容易出错。这些标签我没能在 Nexus 的官方说明里核对，粘贴后请用预览看一眼。
