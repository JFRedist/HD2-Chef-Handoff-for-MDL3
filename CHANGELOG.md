# 更新记录

## 仓库

### 2026-11-02
- 仓库说明改为以 **Chef Hand-off for MDL3** 为中心：README 重写（真机状态、安装、出问题时、贡献者、致谢），`handoff/README.md` 和 `docs/chef-under-mdl3.md` 补上三次真机结果，
  Chef 版 BF5 的研究（`probe/`、`docs/chef-feasibility.md`、`docs/probe-run-1.md`）标为已放弃的历史记录，新增本文件。
- 贡献者里加上 JFRedist（项目发起和方向、全部真机测试）。
- 加 MIT 许可证（`LICENSE`）。探针里内嵌的敌人分级表是从 BF5 反馈的 MDL3 版提取的，不在授权范围内（README 的"许可"里写明）。
- `docs/chef-under-mdl3.md` 写清了怎么认出"做给 Chef"的 addon（规则、读法、会漏掉什么）。
- **删除探针**（BFV Chef Probe）和只为它存在的测试、工具（`tests/test_probe.lua`、`probe_harness.lua`、`chef_sim.sh`，`tools/extract_tiers.py`、`modsim_extend.py`）：
  它内嵌的敌人分级表是别人的数据，不能放在 MIT 下。`dist/` 里只剩交接 addon 的 zip；调研文档保留，去掉了分级表的内容。
- 发布：`.github/workflows/release.yml`（推 `v*` 标签或手动运行时，核对 `dist/` 的 zip 与源码一致，再建 Release）和 `release-notes/`。第一个 Release 是 v0.2.0。
- 新增 `docs/nexus-page.md`：上架 Nexus Mods 的页面文字。
- 交接 addon 0.2.1：和 Chef 1.5.x 兼容（见下）。`tests/handoff_sim.sh` 加了变体 F，检查不再写死 Chef 的版本号；在 Chef 1.4.1 和 1.5.1 上都跑过。
- 新增 `promo/`：宣传视频（中文字幕的动画讲解，约 99 秒）的源文件、封面和 B 站投稿文案。视频由 `promo/render.js` 生成，不入库。
- `promo/nexus-images.html`：Nexus 页面用的 6 张英文图解（主图、问题、交接过程、优先级、0.2.0 的变化、怎么确认）。

## Chef Hand-off for MDL3

### 0.2.1 — 2026-11-02
- **和 Chef 1.5.x 一起用。** Chef 被交接时会收下当时游戏里的回调（`init`、`update`、`render`、`shutdown`，MDL3 和它的 mod 串起来的链），在自己的回调之后运行。Chef 1.5.0 起这些回调在它的卡死看门狗下面：一次调用超过 3 秒就判卡死，整条链被关掉（`switched off boot:... for this session: it hung`），MDL3 也就停了。
  0.2.1 不再把这些回调交给 Chef：交接前先从全局里摘下，Chef 加载完再放回它自己的回调后面（Chef 的先，MDL3 的链后）；Chef 没起来时原样放回。Chef 不再拥有、计时或终止它们。
- `chef_handoff.log` 多记：交接前后的调试钩子状态；MDL3 的某次调用超过 0.5 秒 CPU 时间时的一行。
- 测试：自写测试 80 项；`tests/handoff_sim.sh` 新增变体 F（对方更新链里一次 3.6 秒的调用），检查改成不写死 Chef 的版本号，在 Chef 1.4.1 和 1.5.1 上都全过（58 项，加真实的 HUDdle 62 项）。0.2.0 在 1.5.1 上过不了 F，这就是复现。
- **真机上和 Chef 1.5.x 一起用还没有确认**（只在 Chef 自带的模拟器里用真实的 1.5.1 验证过）；真实的 MDL3 为什么会有超过 3 秒的调用，没有 1.5.x 的日志，不知道。

### 0.2.0 — 2026-11-02
- 交接前读游戏的补丁文件，找出做给 Chef 的 addon，把它们从 `package.loaded`（以及加载器的 `modules` 表）里摘掉，让 Chef 启动它们。
  修的是 Treasure Radar：MDL3 "启动"过它而且没报错，Chef 因此当作别的加载器已经启动而跳过（真机日志里的 `already started by another loader (started)`）。
- 读不了补丁文件时，用内置的两个名字（Treasure Radar、HUDdle）。
- 交接 addon 自己不会被当作 Chef 的 addon 摘掉。
- 测试：自写测试 64 项；`tests/handoff_sim.sh` 加了一个像 Treasure Radar 的替身，和一个只留下 `package.loaded` 的变体 E（真实 MDL3 的样子）。
- 真机：作者的试玩报告说 Treasure Radar 起来了，ESC 回飞船没有闪退，BF5 反馈正常。`chef_handoff.log` 证实补丁扫描在真机上起作用（读了 91 个补丁文件，5 毫秒，认出 Treasure Radar 和 HUDdle 是做给 Chef 的）。

### 0.1.0 — 2026-11-01
- 第一版：游戏运行 6 秒后，用 Chef 文档里"给其它加载器"写明的办法（便条 `ChefSharedLoaderHandoff` + `require` Chef 的核心）把游戏交给 Chef。
  Chef 没装、已经在运行、上次启动在交接中结束时什么也不做；日志写在 `chef_handoff.log`。
- 真机（MDL3 3.0.0-dev.29，Chef 1.4.1）：交接成功，HUDdle 正常；任务中按 ESC 回飞船闪退过一次（原因没找到）；Treasure Radar 被 Chef 跳过。

## BFV Chef Probe（已停用，2026-11-02 从仓库删除；最后一版在提交 `2f5d79b`）

### 0.2.0 — 2026-11-01
- 死亡状态（进入时刻）、每个游戏对象、准星单位与游戏对象的对应。只在模拟器里验证过。

### 0.1.0 — 2026-11-01
- 第一版，只读探针；真机跑了一局，结果见 `docs/probe-run-1.md`。
