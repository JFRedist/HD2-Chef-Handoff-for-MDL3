# 更新记录

## 仓库

### 2026-11-02
- 仓库说明改为以 **Chef Hand-off for MDL3** 为中心：README 重写（真机状态、安装、出问题时、贡献者、致谢），`handoff/README.md` 和 `docs/chef-under-mdl3.md` 补上三次真机结果，
  Chef 版 BF5 的研究（`probe/`、`docs/chef-feasibility.md`、`docs/probe-run-1.md`）标为已放弃的历史记录，新增本文件。
- 贡献者里加上 JFRedist（项目发起和方向、全部真机测试）。

## Chef Hand-off for MDL3

### 0.2.0 — 2026-11-02
- 交接前读游戏的补丁文件，找出做给 Chef 的 addon，把它们从 `package.loaded`（以及加载器的 `modules` 表）里摘掉，让 Chef 启动它们。
  修的是 Treasure Radar：MDL3 "启动"过它而且没报错，Chef 因此当作别的加载器已经启动而跳过（真机日志里的 `already started by another loader (started)`）。
- 读不了补丁文件时，用内置的两个名字（Treasure Radar、HUDdle）。
- 交接 addon 自己不会被当作 Chef 的 addon 摘掉。
- 测试：自写测试 64 项；`tests/handoff_sim.sh` 加了一个像 Treasure Radar 的替身，和一个只留下 `package.loaded` 的变体 E（真实 MDL3 的样子）。
- 真机（作者的试玩报告，没有传日志）：ESC 回飞船没有闪退，BF5 反馈正常。**Treasure Radar 的真机确认还没有。**

### 0.1.0 — 2026-11-01
- 第一版：游戏运行 6 秒后，用 Chef 文档里"给其它加载器"写明的办法（便条 `ChefSharedLoaderHandoff` + `require` Chef 的核心）把游戏交给 Chef。
  Chef 没装、已经在运行、上次启动在交接中结束时什么也不做；日志写在 `chef_handoff.log`。
- 真机（MDL3 3.0.0-dev.29，Chef 1.4.1）：交接成功，HUDdle 正常；任务中按 ESC 回飞船闪退过一次（原因没找到）；Treasure Radar 被 Chef 跳过。

## BFV Chef Probe（已停用）

### 0.2.0 — 2026-11-01
- 死亡状态（进入时刻）、每个游戏对象、准星单位与游戏对象的对应。只在模拟器里验证过。

### 0.1.0 — 2026-11-01
- 第一版，只读探针；真机跑了一局，结果见 `docs/probe-run-1.md`。
