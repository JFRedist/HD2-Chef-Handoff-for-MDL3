# Nexus Mods 页面文字（Chef Hand-off for MDL3 0.2.5）

上传页的每一栏分别复制下面的代码块。正文是 BBCode（Nexus 的描述框用的格式），英文为主，简体中文放在页尾的折叠块里。细节、已知问题和完整的版本记录都在 GitHub，页面上只放用户要用的。
发布前先看最后的"发布前检查"：有几项只能你在上传页上选。

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

Helldivers 2 runs only one [b]boot[/b] script, the highest-priority one, so normally either [b]Chef Shared Loader[/b] or [b]MDL3[/b] works, not both. This tiny addon is started by MDL3 and, about 6 seconds into the game, hands the game over to Chef the way Chef's own documentation describes for other loaders. MDL3 keeps running its mods (for example the MDL3 build of BF5 Hit and Kill Feedback); Chef runs its mods (HUDdle, Treasure Radar, NarrowHUD ...).
[list]
[*]Lua only. Nothing of Chef, HUDdle or MDL3 is included or changed.
[*]Does nothing if Chef is not installed or is already running.
[*]Writes chef_handoff.log and chef_handoff_state.txt to %APPDATA%\Arrowhead\Helldivers2.
[/list]

[size=4][b]Requirements[/b][/size]
[list]
[*][b]MDL3[/b] and the MDL3 mods you like, for example [url=https://www.nexusmods.com/helldivers2/mods/16927]BF5 Hit and Kill Feedback (MDL3 build)[/url]
[*][b]Chef Shared Loader 1.2.0 or newer[/b] ([url=https://github.com/Th3chef/Chef-Shared-Loader/releases/latest]download[/url]) and the Chef mods you like, for example [url=https://www.nexusmods.com/helldivers2/mods/18108]HUDdle[/url], [url=https://www.nexusmods.com/helldivers2/mods/18265]Treasure Radar[/url] or [url=https://www.nexusmods.com/helldivers2/mods/17882]NarrowHUD[/url]
[*]Arsenal or HD2 Mod Manager
[/list]

[size=4][b]Installation[/b][/size]
[list=1]
[*]Add [b]Chef-Hand-off-for-MDL3-0.2.5.zip[/b] to your mod manager and enable it.
[*][b]Give MDL3 a higher priority than Chef[/b], the opposite of what Chef and HUDdle say: the game has to run MDL3's boot. In Arsenal, with [i]First mod highest priority[/i] put MDL3 above Chef; with [i]Last mod highest priority[/i], below. If you use Rat's Shared Loader (HD2 Transmog), keep it below MDL3 as well.
[*][b]Give this mod the lowest priority[/b] (deployed first). MDL3 3.0.0-dev.33 was seen to look at only the first 512 patch files, so with many mods it never finds an addon deployed late.
[*]Purge, then Deploy. Wait about 10 seconds on the title screen before you start a mission.
[/list]
It works when [i]chef_handoff.log[/i] says [i]Chef Shared Loader 1.x.x started[/i] and [i]chef_loader.log[/i] (same folder) says [i]started by MDL3 chef_handoff 0.2.5[/i].

[size=4][b]Troubleshooting[/b][/size]
[list]
[*][b]MDL3 mods work, Chef mods do not:[/b] read chef_handoff.log. If there is none and MDL.log begins with "in 512 archive(s)", give this mod the lowest priority.
[*][b]Chef mods work, MDL3 mods do not, and there is no chef_handoff.log:[/b] Chef has the higher priority. Swap them, Purge, Deploy.
[*][b]F9 opens two menus at once:[/b] a mod that MDL3 runs (such as First Person Camera by Webbox) took F9, Chef's menu key. Move Chef's key: press F9, go to Chef Shared Loader > Open this menu, press Right, then the new key.
[*][b]A mod shows in Chef's menu only as "Run by MDL3 chef_handoff", or MDL3's menu shows a Chef mod as failed:[/b] that is normal. The first one is run by MDL3, the second by Chef.
[*]Please report problems on [url=https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues]GitHub[/url] with chef_handoff.log, chef_loader.log and MDL.log. MDL.log is overwritten on every launch: copy it before you restart the game.
[/list]

[size=4][b]Version 0.2.5[/b][/size]
Works with Rat's Shared Loader below MDL3: Chef starts it after the hand-off, and it starts HD2 Transmog (with 0.2.4 it skipped Transmog). Every Chef mod is found with more than 400 patch files. Since 0.2.4 it recognises Chef mods whose "local chef = ..." line comes after their first 16 KB (NarrowHUD 1.0.6); since 0.2.3 it works with Chef 1.4.x and 1.5.x: MDL3's callbacks are kept away from Chef's hang watchdog, which would otherwise switch MDL3 off after one call over 3 seconds.
Tested in the game with MDL3 3.0.0-dev.29 and dev.33, Chef 1.4.1 and 1.5.1, HUDdle 0.6.11, NarrowHUD 2.2.0, Treasure Radar 0.7.1n and BF5 Hit and Kill Feedback (MDL3 build) 2.0.1.

[size=4][b]Credits[/b][/size]
[list]
[*][b]Chef Shared Loader[/b] by Th3chef. The hand-off is the one in its documentation ("Everything here is free to copy into your loader as it is").
[*][b]HUDdle[/b], [b]Treasure Radar[/b], [b]NarrowHUD[/b], [b]MDL3[/b] and [b]BF5 Hit and Kill Feedback[/b] by their authors. None of their files are included.
[*]Source code, documentation and the full history: [url=https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3]GitHub[/url] (MIT license). The code was written with the help of Claude (Anthropic's AI) and tested in the real game by me.
[/list]

[spoiler][b]简体中文[/b]
[b]它做什么：[/b]游戏只运行优先级最高的那个 boot，所以 Chef Shared Loader 和 MDL3 默认只能有一个工作。这个由 MDL3 启动的小 addon 在进游戏约 6 秒后，按 Chef 文档写明的办法把游戏交给 Chef：MDL3 照常运行它的 mod（比如 BF5 击杀反馈的 MDL3 版），Chef 运行 Chef 的 mod（HUDdle、Treasure Radar、NarrowHUD ……）。只有 Lua，不包含也不修改 Chef、HUDdle、MDL3 的任何文件；没装 Chef 或 Chef 已在运行时什么也不做。
[b]需要：[/b]MDL3；Chef Shared Loader 1.2.0 以上；Arsenal 或 HD2 Mod Manager。
[b]安装：[/b]
1. 把 Chef-Hand-off-for-MDL3-0.2.5.zip 加进 mod 管理器并启用。
2. MDL3 的优先级要比 Chef 高（和 Chef、HUDdle 的说明相反）。Arsenal 的设置是 First mod highest priority，就把 MDL3 放在 Chef 上面；是 Last mod highest priority，就放在下面。用 Rat's Shared Loader（HD2 Transmog）的话，Rat 也放在 MDL3 下面。
3. 本 mod 放在最低优先级（最先部署）：MDL3 3.0.0-dev.33 只看了前 512 个补丁文件，mod 多时排在后面的它发现不了。
4. Purge，再 Deploy。在标题画面停 10 秒左右再进任务。
成功的样子：%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log 里有 Chef Shared Loader 1.x.x started，chef_loader.log 里有 started by MDL3 chef_handoff 0.2.5。
[b]出问题时：[/b]MDL3 的 mod 正常、Chef 的没有：看 chef_handoff.log；没有这个文件而 MDL.log 开头是 in 512 archive(s)，就把本 mod 放到最低优先级。Chef 的 mod 正常、MDL3 的没有、也没有 chef_handoff.log：Chef 的优先级比 MDL3 高了，对调后 Purge 再 Deploy。按 F9 两个菜单一起出来：某个由 MDL3 运行的 mod（比如 First Person Camera）占了 F9，把 Chef 的菜单键改掉（F9 > Chef Shared Loader > Open this menu，按右方向键再按新键）。Chef 菜单里某个 mod 只有一行 Run by MDL3 chef_handoff，或者 MDL3 的菜单里 Chef 的 mod 显示失败：都正常。反馈请到 GitHub，附上 chef_handoff.log、chef_loader.log 和 MDL.log（MDL.log 每次启动会被覆盖，先拷出来）。
[b]0.2.5：[/b]Rat's Shared Loader 放在 MDL3 下面时，交接后由 Chef 拉起来，它启动 HD2 Transmog（0.2.4 下会跳过）；补丁文件超过 400 个时也能找全 Chef 的 mod。0.2.4 起认得出 local chef = ... 在前 16 KB 之后的 Chef mod（NarrowHUD 1.0.6）；0.2.3 起 Chef 1.4.x 和 1.5.x 都能用：MDL3 的回调不交给 Chef 的卡死看门狗。真机测过 MDL3 3.0.0-dev.29 和 dev.33、Chef 1.4.1 和 1.5.1。
[b]来源：[/b]代码、文档和完整的版本记录在 GitHub（MIT 许可）。代码是在 Claude（Anthropic 的 AI）的帮助下写的，由我在真实游戏里测试。
[/spoiler]
```

## 文件（File）

| 栏 | 内容 |
|---|---|
| 文件 | `Chef-Hand-off-for-MDL3-0.2.5.zip`（GitHub 的 Release 页下载；sha256 `9511b35df18fe1ae8e4cc0f5f4f62000ede11f5f76216a438385ea2a2357a896`） |
| 名称 | `Chef Hand-off for MDL3` |
| 版本 | `0.2.5` |
| 类型 | Main file |

文件说明：

```
Mod manager zip (Arsenal / HD2 Mod Manager). Needs MDL3 and Chef Shared Loader 1.2.0+. Give MDL3 a higher priority than Chef (and than Rat's Shared Loader, if you use it), and this mod the lowest priority.
```

## 更新说明（Changelog）

按页面上已经有的版本，贴需要的那几条。

0.2.5：

```
Works with Rat's Shared Loader below MDL3: Chef starts it after the hand-off, and it now starts HD2 Transmog (0.2.4 left require's placeholder from MDL3's failed start of Transmog in package.loaded, and Rat skipped it). Reads every patch file when there are more than 400 (0.2.4 stopped at patch_400). Not yet tested in the game.
```

0.2.4：

```
Also recognises Chef mods whose "local chef = ..." line comes after their first 16 KB and that have no HD2-Requires header (NarrowHUD 1.0.6); Chef skipped them before. New install advice: give this mod the lowest priority (MDL3 3.0.0-dev.33 was seen to look at only the first 512 patch files). Tested in the game with MDL3 3.0.0-dev.33 and Chef 1.5.1.
```

0.2.3：

```
Works with Chef Shared Loader 1.4.x and 1.5.x: MDL3's callbacks are taken off the game's global table while Chef loads and put back behind Chef's own, so Chef's hang watchdog cannot switch MDL3 off after one call over 3 s.
```

0.2.0：

```
First public release. Chef mods that MDL3 starts without Chef (Treasure Radar) are no longer skipped by Chef: before the hand-off, the addons made for Chef are recognised by reading the patch files and taken off package.loaded.
```

## 发布前检查

0. **已经上架过旧版本的话**：把 0.2.5 作为新版本上传到同一个 mod 页面，旧文件可以归档。
1. **AI 标签。** Nexus 要求给 AI 生成的内容打标签；这个 mod 的代码是 AI 写的，请选 *AI-Generated Content*（以上传页的原文为准）。描述末尾那句 Claude 的说明请保留。
2. **要求（Requirements）栏。** 把 MDL3 加进去；Chef Shared Loader 如果在 Nexus 上有页面也加上。描述里 Chef 的链接指向它的 GitHub Release。Treasure Radar 的编号 18265 是从你 Arsenal 里的文件夹名取的，发布前请点一下确认。
3. **图片。** `promo/nexus-images.html` 里有 6 张 1920×1080 的英文图解（`node promo/render.js nexus out/nexus` 生成），按顺序上传，第一张当主图：

   | 文件 | 标题（caption） |
   |---|---|
   | `01-hero.png` | Chef Hand-off for MDL3: run Chef mods and MDL3 mods in the same game |
   | `02-the-problem.png` | The problem: the game runs one boot script, so it is Chef or MDL3 |
   | `03-how-the-hand-off-works.png` | How it works: MDL3 keeps the boot, the addon hands the game to Chef after 6 s |
   | `04-give-mdl3-the-higher-priority.png` | Install tip: MDL3 needs the higher priority (both Arsenal settings) |
   | `05-new-in-0.2.0.png` | New in 0.2.0: Treasure Radar and other Chef mods are no longer skipped |
   | `06-how-to-tell-it-works.png` | How to tell it works: the log lines to look for |

   这些是图解，不是游戏截图（图里的日志来自你的真机运行）。能再补 1～2 张真机截图更好：同一局里 HUDdle 和一个 MDL3 mod 同时在起作用。图是用代码画的，不是图像生成模型生成的；上传页如果有“AI 生成的宣传图”这类标签，建议选上。
4. **分类、标签和权限。** 分类选最接近“工具 / 加载器”的；代码是 MIT，权限最一致的做法是允许署名后使用、修改、再发布，由你决定。
5. **BBCode。** 只用了常见的标签（`b i size center list url line spoiler`），折叠块里只有加粗和纯文本。粘贴后请用预览看一眼。
