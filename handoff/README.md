# Chef Hand-off for MDL3 0.1.0

让 **Chef Shared Loader**（以及只能在它上面运行的 mod，比如 **HUDdle**）和 **MDL3**（以及 BF5 反馈这类 MDL3 mod）在同一个游戏里一起工作。

## 为什么需要它

游戏只运行一个 `boot`：优先级最高的那个补丁里的。Chef 和 MDL3 都想当这个 boot，所以：

- Chef 在上面：只有 Chef 运行，Chef 不会运行别的加载器的 boot（它的文档写明了），MDL3 和它的 mod 不工作。
- MDL3 在上面：只有 MDL3 运行，Chef 和 HUDdle 不工作。

Chef 的文档（"For other loaders"）给其它加载器留了一个交接办法：设一个便条，再 `require` Chef 的核心，Chef 就在当前的游戏里启动。
这个 mod 在 MDL3 那一边做这件事：进游戏 6 秒后把游戏交给 Chef。之后 MDL3 照常运行它的 mod，Chef 运行它的 mod（HUDdle 之类）。
它不改任何别的东西；没装 Chef 或者 Chef 已经在运行时什么也不做。

## 安装

1. 你已经有：MDL3 和它的 mod（BF5 反馈）、Chef Shared Loader（1.2.0 以上）、HUDdle。
2. 把 `dist/Chef-Hand-off-for-MDL3-0.1.0.zip` 加进 Arsenal / HD2 Mod Manager 并启用。
3. **优先级：MDL3 必须在 Chef 上面**（比 Chef 后部署）。其余的顺序没关系。（Chef 和 HUDdle 的说明都要求 Chef 排最后，这里正相反：游戏运行的 boot 必须是 MDL3 的。）
4. **Purge**，再 **Deploy**。
5. 启动游戏，在标题画面停 10 秒以上，再进一局任务。

## 怎么知道成功了

| 看哪里 | 成功的样子 |
|---|---|
| `%APPDATA%\Arrowhead\Helldivers2\chef_handoff.log` | 最后一行是 `Chef Shared Loader 1.4.x started` |
| `chef_loader.log`（同一个文件夹） | 有 `started by MDL3 chef_handoff 0.1.0, which handed off to me`，和 `started mods/rosensterner/minimal_hud` |
| 游戏里 | 任务中出现 HUDdle 的 HUD；按 F9 出 Chef 的菜单；BF5 反馈照常 |

## 日志里的状态

| `chef_handoff.log` 里 | 意思 |
|---|---|
| 文件不存在 | MDL3 没有启动这个 mod（我需要知道 MDL3 怎么登记 mod，见下） |
| `Chef Shared Loader ... started` | 成功 |
| `Chef Shared Loader is not installed` | 游戏里找不到 Chef 的核心：Chef 没装、没部署，或者被禁用了 |
| `Chef Shared Loader is running already` | Chef 已经在运行（MDL3 自己交接了，或者 Chef 排在最上面），本 mod 什么也没做 |
| `the last launch ended during the hand-off` | 上次启动在交接过程中结束（崩溃）。为了不反复崩，这次没有再试。删掉同一文件夹里的 `chef_handoff_state.txt` 可以再试一次 |
| `the hand-off did not start Chef (require false: ...)` | Chef 的核心报错，原因在括号里 |

## 不行的话，发给我

`chef_handoff.log`、`chef_loader.log`，如果有 `chef_handoff_state.txt`，再加一句现象：游戏起不来 / 崩溃 / 进游戏没有 HUDdle / BF5 没反应。
`chef_handoff.log` 开头会列出 MDL3 给 mod 的那些全局表（`CowboyBingusModLoader`、`MDL3`、`HD2Data` ……）里有什么，这能让我对着 MDL3 的真实情况改。

## 可能的副作用

- Chef 启动时（第 6 秒左右，一般在标题画面）会有几十毫秒的卡顿。
- Chef 会把所有带 `HD2-Addon` 头的 mod 都看一遍，已经由 MDL3 启动的它会跳过（靠 `package.loaded` 和 MDL3 登记的列表）。如果 MDL3 没登记，Chef 会把 BF5 反馈再启动一份。
  看 `chef_loader.log` 里有没有 `started mods/test_author/battlefield5_kill_feedback`，有的话告诉我；在 Chef 的 F9 菜单里可以先把它关掉。

## 卸载

在 mod 管理器里取消勾选，Purge 再 Deploy。`chef_handoff.log` 和 `chef_handoff_state.txt` 可以直接删。

## 验证到了哪一步

在 Chef 自带的模拟器里，用三个**我写的假 MDL3 启动器**（代替 MDL3 的 boot）测过：启动器在 init 里启动 mod / 在 boot 里启动 mod（并先用普通 require 试一遍 Chef 的 mod）/ 自己已经交接给 Chef，
三种情况下 Chef 都按预期运行，假 MDL3 的回调每帧照常被调用，游戏自己的 init 没有被重复或跳过；用你的 HUDdle 0.6.11 也试过，能启动。
**没有测过真实的 MDL3**：我没有它。假启动器只是按 BF5 的 MDL3 版代码和 Chef 的文档推出来的样子，真实的 MDL3 怎么启动 mod，要靠你这一次来回答。
详细见 [`docs/chef-under-mdl3.md`](../docs/chef-under-mdl3.md)。
