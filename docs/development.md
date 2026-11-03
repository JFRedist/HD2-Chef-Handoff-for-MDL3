# 开发、测试与发布

给想改代码或自己验证的人。用法见根目录的 [README](../README.md) 和 [`handoff/README.md`](../handoff/README.md)。

## 仓库结构

| 路径 | 内容 |
|---|---|
| `handoff/` | **交接 addon**：`chef_handoff.lua`、`mod.json`、使用说明 |
| `dist/` | 打好的 mod 管理器 zip：`Chef-Hand-off-for-MDL3-0.2.5.zip`（与源码逐字节对应，构建是确定性的）。同一个文件在本仓库的 Releases 页 |
| `docs/status.md` | 真机状态：每个版本在真实游戏里的结果和依据 |
| `docs/development.md` | 本文件：仓库结构、测试、发布 |
| `docs/chef-under-mdl3.md` | 在 MDL3 下运行 Chef 和 HUDdle：问题、交接办法、怎么认出做给 Chef 的 mod、真机结果、Chef 1.5.x、验证、风险 |
| `docs/nexus-page.md` | Nexus Mods 页面的文字：名称、摘要、BBCode 描述（英文，带简体中文折叠块）、文件说明、更新说明、发布前检查 |
| `promo/` | 宣传材料的源文件：`scenes.html`（宣传视频的动画）、`cover.html`（B 站封面）、`nexus-images.html`（Nexus 页面的 6 张图）、`render.js`（渲染）、`bilibili-post.md`（B 站投稿文案）。视频和图片本身不入库 |
| `docs/chef-feasibility.md`、`docs/probe-run-1.md` | 已放弃的研究：BF5 击杀反馈的 Chef 版（结论和探针为什么删掉，见 `chef-feasibility.md` 开头） |
| `CHANGELOG.md`、`LICENSE` | 版本记录；MIT 许可证 |
| `.github/workflows/release.yml`、`release-notes/` | 发布：见下 |
| `tools/` | `hd2patch.py`（资源哈希 MurmurHash64A 和 Lua 补丁文件的读写）、`pack.py`（把 `mod.json` + Lua 打成 Arsenal / HD2 Mod Manager 的 zip）、`inspect_patch.py`（只读地查看/解出补丁文件） |
| `tests/` | 见下 |

MDL3、Chef、HUDdle、BF5 反馈（原版和 MDL3 版）的文件**没有**放进本仓库。

## 开发与测试

```bash
tests/run_all.sh                                       # 快速检查：Python 测试 + Lua 语法 + 交接 addon 在自写假环境里的测试
tests/handoff_sim.sh <Chef-Shared-Loader 仓库路径>     # 主要检查：交接 addon 在真实的 Chef 上，假 MDL3 启动器下
python3 -I tools/pack.py handoff/mod.json dist         # 打包
HUDDLE_LUA=<HUDdle 的 Lua 文件> tests/handoff_sim.sh <Chef 仓库路径>   # 可选：用你自己那份 HUDdle 再跑一遍
```

需要 python3、Pillow（Chef 的构建用）和 lua5.1。2026-11-03 用 0.2.5 在 Chef 1.4.1（提交 `400cc03`）和 1.5.1（标签 `v1.5.1`）上的结果：

- `tests/run_all.sh`：Python 12 个测试通过（1 个因为没有给真实 mod 的补丁文件而跳过），交接 addon 130 项，全过（其中有一个照 0.2.2 日志做的 MDL3 沙箱模型、一个守着新键的全局表、0.2.4 的三个 16 KB 之后的例子、0.2.5 的 400 号以后的补丁和 Rat 的 mod）。
- `tests/handoff_sim.sh`：86 项，在 1.4.1 和 1.5.1 上都全过。七种假 MDL3 启动器（A 在 `init` 里启动 / B 在 `boot` 里启动并先普通 `require` / E 同 B 但只留下 `package.loaded` /
  F 更新链里有一次 3.6 秒的慢调用 / G 有 mod 打开文件时就把自己的 `render`、`shutdown` 放回去 / **H MDL3 的沙箱，照 0.2.2 的真机日志做的，加一次 3.6 秒的慢调用** / C 自己已交接），检查 Chef 报告被谁交接、自己的 boot stub 没运行、Chef 的 mod 启动并绘制、假 MDL3 的回调每帧照常运行且没有被看门狗终止、Chef 没有收下假 MDL3 的回调、更新链每帧只跑一次、游戏的 `init` 恰好一次、`shutdown` 恰好一次。
  再给 `HUDDLE_LUA`（真实的 HUDdle 0.6.11，不在仓库里）跑变体 D，共 90 项，全过。F 是为 1.5.x 加的：0.2.0 在 1.5.1 上过不了它。G 是 0.2.1 之后的猜测（后来证明猜错了），留着检查交接中间不运行别的东西。H 是照 0.2.2 的真机日志做的：0.2.2 在它上面逐行写出和真机一样的日志（`still on the globals ... update, shutdown` 等），真实的 Chef 1.5.1 写出同样的 `(2)`，并在那次慢调用上把 MDL3 判成卡死、关掉；0.2.3 过得了。
- 变异检查：故意改坏交接 addon 的 27 处（0.1.0 的 9 处、0.2.0 新增的 11 处、0.2.1 新增的 7 处），自写测试全部抓到（一个防御性的等价变异除外），模拟器测试抓到影响真实 Chef 行为的那些。这是一次性的手工检查，脚本没有放进仓库。0.2.2 新加的测试拿 0.2.1 跑：守卫模型那一项失败。0.2.3 新加的测试拿 0.2.2 跑：沙箱模型里 Chef 拿到 MDL3 的 `update`、`shutdown`，MDL3 的更新在 Chef 里面跑；去掉替身那一步，守着新键的全局表会吞掉 Chef 的回调，测试都抓到。0.2.4 新加的测试拿 0.2.3 跑：失败 6 项；去掉“前 16 KB 的最后一行一起找”那一步，被 16 KB 那条线切开的例子失败。0.2.5 新加的测试拿 0.2.4 跑：失败 4 项（400 号以后两项、Rat 的占位两项）。
- 补丁写入器：5 个资源哈希向量吻合（含 Chef 公布的 `boot`、`core_1` 和两个真实 mod 的资源 ID）；能把真实 mod 的 Lua 补丁逐字节重建（`HD2_FIXTURE_PATCHES` 给补丁文件路径，用冒号分隔）。打好的 zip 是确定性的。

**Windows 上**（2026-11-02 在 Windows 11 上跑通，结果同上，包括用真实的 HUDdle 0.6.11 跑的变体 D）：用 Git Bash 运行这两个脚本。`python3` 这个名字要找到真正的 Python，不是应用商店的占位程序；Pillow 要装在 Python 自己的 site-packages 里（脚本用 `python3 -I`，不看 `--user` 装的包）。
Chef 的模拟器从 Python 启动 `lua5.1`，Windows 把 `.1` 当成扩展名，找不到 `lua5.1.exe`：在同一个文件夹里放一份不带扩展名的副本 `lua5.1`。
本仓库和 Chef 仓库都要用 LF 检出（`git config core.autocrlf false`，Chef 仓库再加 `git config core.eol lf`，然后重新检出），否则脚本跑不起来，zip 也对不上。

`tests/handoff_sim.sh` 会先把 Chef 仓库**复制**到临时目录再运行 Chef 自带的模拟器（`tools/modsim/modsim.py`）。它运行的是 Chef 仓库里的代码（模拟器、构建脚本、加载器本体），运行前请先读一遍。

**发布。** 版本号在 `handoff/mod.json`。改完后重新打包进 `dist/` 并推送，再给提交打 `vX.Y.Z` 标签并推送（或者在 GitHub 的 Actions 页手动运行 *Release*，填上标签）。
工作流会先用 `tools/pack.py` 重新构建 zip，和 `dist/` 里的逐字节比较，一致才建 Release；说明取自 `release-notes/<标签>.md`。
