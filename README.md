# Chef Hand-off for MDL3

让 **Chef Shared Loader** 和 **MDL3** 在同一个 Helldivers 2 里一起工作：只能在 Chef 下运行的 mod（[HUDdle](https://www.nexusmods.com/helldivers2/mods/18108)、Treasure Radar、NarrowHUD ……）和只能在 MDL3 下运行的 mod（比如 [BF5 击杀反馈的 MDL3 版](https://www.nexusmods.com/helldivers2/mods/16927)）可以同时用。

Lets **Chef Shared Loader** and **MDL3** work in the same Helldivers 2, so that Chef-only mods (HUDdle, Treasure Radar, NarrowHUD ...) and MDL3-only mods (such as the MDL3 build of BF5 Hit and Kill Feedback) can be used together.

## 原理 / How it works

游戏只运行一个 `boot`（优先级最高的那个），所以 Chef 和 MDL3 默认只能有一个工作。本 mod 由 MDL3 启动，进游戏 6 秒后用 Chef 文档里写明的办法（"For other loaders"）把游戏交给 Chef：MDL3 照常运行它的 mod，Chef 运行 Chef 的 mod。没装 Chef 或 Chef 已经在运行时，它什么也不做。

The game runs only one `boot` (the highest-priority one), so normally only one of Chef and MDL3 works. This mod is started by MDL3 and, 6 seconds into the game, hands the game over to Chef the way Chef's own documentation describes ("For other loaders"). MDL3 keeps running its mods; Chef runs the Chef mods. It does nothing when Chef is not installed or already running.

本仓库没有 Chef、HUDdle、MDL3 的任何代码。 / No code of Chef, HUDdle or MDL3 is in this repository.

## 安装 / Install

1. 已经装好 MDL3、Chef Shared Loader（1.2.0 以上）和要用的 mod。
   You already have MDL3, Chef Shared Loader (1.2.0 or newer) and the mods you want.
2. 从 [Releases](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/releases) 下载 `Chef-Hand-off-for-MDL3-0.2.4.zip`（[`dist/`](dist/) 里是同一个文件），加进 Arsenal / HD2 Mod Manager 并启用。
   Download `Chef-Hand-off-for-MDL3-0.2.4.zip` from Releases (the same file is in [`dist/`](dist/)), add it to Arsenal / HD2 Mod Manager and enable it.
3. **MDL3 的优先级要比 Chef 高**，和 Chef、HUDdle 的说明相反：游戏运行的 boot 必须是 MDL3 的。
   **Give MDL3 a higher priority than Chef**, the opposite of what Chef and HUDdle say: the game has to run MDL3's boot.
4. **本 mod 放在最低优先级**（最先部署）：MDL3 3.0.0-dev.33 只看了前 512 个补丁文件，mod 多时排在后面的它发现不了。
   **Give this mod the lowest priority** (deployed first): MDL3 3.0.0-dev.33 was seen to look at only the first 512 patch files, so with many mods it never finds an addon deployed late.
5. Purge，再 Deploy。启动游戏，在标题画面停 10 秒以上，再进任务。
   Purge, then Deploy. Start the game and stay on the title screen for 10 s or more before a mission.

Arsenal 里“优先级高”是列表的哪一端、怎么确认成功、日志怎么看：见 [`handoff/README.md`](handoff/README.md)（中文）。英文的完整说明在 [`docs/nexus-page.md`](docs/nexus-page.md)。
Which end of Arsenal's list is "higher priority", how to tell that it worked and how to read the logs: see [`handoff/README.md`](handoff/README.md) (Chinese); the full English text is in [`docs/nexus-page.md`](docs/nexus-page.md).

## 出问题时 / Troubleshooting

| 现象 / Symptom | 多半是 / Most likely |
|---|---|
| MDL3 的 mod 正常，Chef 的 mod 没有<br>MDL3 mods work, Chef mods do not | 看 `chef_handoff.log`。没有这个文件，而 `MDL.log` 开头写着 `in 512 archive(s)`：本 mod 排得太靠后，放到最低优先级。<br>Read `chef_handoff.log`. If there is none and `MDL.log` begins with `in 512 archive(s)`, this mod is deployed too late: give it the lowest priority. |
| Chef 的 mod 正常，MDL3 的没有，也没有 `chef_handoff.log`<br>Chef mods work, MDL3 mods do not, and there is no `chef_handoff.log` | Chef 的优先级比 MDL3 高了：对调，Purge 再 Deploy。<br>Chef has the higher priority: swap them, Purge, Deploy. |
| 按 F9 时两个菜单一起出来<br>F9 opens two menus at once | 某个 mod 由 MDL3 运行，自己用了 F9：把 Chef 的菜单键改到别的键，见 [`handoff/README.md`](handoff/README.md)。<br>A mod run by MDL3 took F9 itself: move Chef's menu key to another key (see [`handoff/README.md`](handoff/README.md)). |

反馈问题请在 [Issues](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues) 里提，附上 `%APPDATA%\Arrowhead\Helldivers2\` 里的 `chef_handoff.log`、`chef_loader.log`，和 `%LOCALAPPDATA%\MDL\Helldivers2\Logs\MDL.log`（每次启动都会被覆盖，闪退后先拷出来）。
To report a problem, open an [issue](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues) with `chef_handoff.log` and `chef_loader.log` from `%APPDATA%\Arrowhead\Helldivers2\`, and `%LOCALAPPDATA%\MDL\Helldivers2\Logs\MDL.log` (it is overwritten on every launch: copy it out first after a crash).

## 版本 / Version

**0.2.4**：也认得出 `local chef = ...` 在前 16 KB 之后的 Chef mod（NarrowHUD 1.0.6，[issue #1](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/1)）。0.2.3 起，Chef 1.4.x 和 1.5.x 都能用：MDL3 的回调不交给 Chef 的卡死看门狗。
真机测过：MDL3 3.0.0-dev.29 和 dev.33，Chef 1.4.1 和 1.5.1，HUDdle 0.6.11，NarrowHUD 2.2.0，Treasure Radar 0.7.1n，BF5 击杀反馈 MDL3 版 2.0.1（0.2.4 在 MDL3 dev.33 + Chef 1.5.1 上）。NarrowHUD 1.0.6 本身没有拿到，只在测试里验证过。

**0.2.4** also recognises a Chef mod whose `local chef = ...` comes after its first 16 KB (NarrowHUD 1.0.6, [issue #1](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/1)). From 0.2.3 on it works with Chef 1.4.x and 1.5.x: MDL3's callbacks are kept away from Chef's hang watchdog.
Tested in the real game with MDL3 3.0.0-dev.29 and dev.33, Chef 1.4.1 and 1.5.1, HUDdle 0.6.11, NarrowHUD 2.2.0, Treasure Radar 0.7.1n and the MDL3 build of BF5 Hit and Kill Feedback 2.0.1 (0.2.4 with MDL3 dev.33 and Chef 1.5.1). NarrowHUD 1.0.6 itself was only checked in the tests.

## 文档 / Documents

文档是中文的，Lua 源码的注释是英文的。 / The documents are in Chinese; the Lua source is commented in English.

| 文件 / File | 内容 / Contents |
|---|---|
| [`handoff/README.md`](handoff/README.md) | 使用说明、日志怎么看、可能的副作用 / how to use it, the logs, side effects |
| [`docs/status.md`](docs/status.md) | 真机状态：每个版本在游戏里的结果 / results in the real game, version by version |
| [`docs/chef-under-mdl3.md`](docs/chef-under-mdl3.md) | 原理、怎么认出 Chef 的 mod、每次真机运行的细节、还没确认的 / how it works, how Chef mods are recognised, every real run in detail, open questions |
| [`docs/development.md`](docs/development.md) | 仓库结构、测试（包括 Windows）、发布 / repository layout, tests (Windows too), releases |
| [`docs/nexus-page.md`](docs/nexus-page.md) | Nexus Mods 页面的文字（英文） / the Nexus Mods page text (English) |
| [`docs/chef-feasibility.md`](docs/chef-feasibility.md) | 已放弃的研究：BF5 击杀反馈的 Chef 版 / abandoned research: a Chef build of BF5 Hit and Kill Feedback |
| [`CHANGELOG.md`](CHANGELOG.md) | 版本记录 / changelog |

## 贡献者 / Contributors

| | |
|---|---|
| [JFRedist](https://github.com/JFRedist) | 项目发起和方向；全部真机测试（安装、运行、取日志），发现并报告了 Treasure Radar 不运行、ESC 回飞船闪退、MDL3 里分类全是“未知”等问题。<br>Started and steers the project; did all real-game testing, and found Treasure Radar not running, the crash on ESC back to the ship and MDL3 showing every category as "unknown". |
| [FworksHN](https://github.com/FworksHN) | [issue #1](https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3/issues/1)：查出了 NarrowHUD 不运行的原因（16 KB）。<br>Found why NarrowHUD did not run (the 16 KB limit). |
| Claude（Anthropic，Claude Code） | 代码、测试、文档 / code, tests, documents |

## 致谢 / Credits

- **Chef Shared Loader**（Th3chef）：交接办法是它的文档公开写明的（*"Everything here is free to copy into your loader as it is"*）。 / The hand-off is the one its documentation publishes for other loaders.
- **HUDdle**（rosensterner，部分改编自 luka189 的 NarrowHUD / partly adapted from luka189's NarrowHUD）、**BF5 Hit and Kill Feedback**（[16832](https://www.nexusmods.com/helldivers2/mods/16832)、MDL3 版 / MDL3 build [16927](https://www.nexusmods.com/helldivers2/mods/16927)）、**MDL3**：这个仓库围绕的东西是它们的作者做的。 / Their authors made what this repository is about.

## 许可 / License

本仓库自己的代码和文档用 [MIT 许可](LICENSE)。MDL3、Chef、HUDdle、BF5 反馈各有自己的许可，它们的文件不在这个仓库里；文档里引用的 Chef 文档片段归 Chef 的作者。git 历史里 `2f5d79b` 及更早的提交含有一张从 BF5 反馈 MDL3 版提取的敌人分级表，权利属于那个 mod 的作者，不在 MIT 授权里（当前的文件里没有这张表）。

This repository's own code and documents are under the [MIT license](LICENSE). MDL3, Chef, HUDdle and BF5 Feedback have their own licenses, and none of their files are here; the quoted parts of Chef's documentation belong to Chef's author. Commits `2f5d79b` and earlier contain an enemy tier table taken from the MDL3 build of BF5 Feedback, which belongs to that mod's author and is not covered by the MIT license (no current file has it).
