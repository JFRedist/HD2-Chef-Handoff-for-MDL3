# B 站投稿：Chef Hand-off for MDL3 宣传视频

视频本身（`Chef-Hand-off-for-MDL3-promo.mp4`）、字幕（`.srt`）和封面（`.png`）是生成出来的，不在仓库里（`out/` 被 git 忽略）；
它们由 `promo/` 里的 `scenes.html`（动画）、`cover.html`（封面）和 `render.js`（渲染）生成，改了文字重新渲染就行：

```bash
node promo/render.js video out/Chef-Hand-off-for-MDL3-promo.mp4     # 约 99 秒，1920×1080，30 帧；需要 node + playwright + ffmpeg + 中文字体
node promo/render.js srt out/Chef-Hand-off-for-MDL3-promo.srt
node promo/render.js cover out/Chef-Hand-off-for-MDL3-cover.png
```

## 这个视频是什么，不是什么

- 是**动画讲解**：问题 → 办法 → 0.2.0 的修复 → 安装 → 怎么确认 → 实测环境和已知问题 → 片尾，约 1 分 39 秒，中文字幕烧在画面里（片尾那一屏的字已经在画面上，所以那一句只在口播稿里）。
- 画面里的日志、版本号都是你真机上跑出来的（`chef_handoff.log` 的 `patch files read: 91 (4 addons, 2 made for Chef, 0 read errors) in 5 ms` 等）。
- **没有游戏录像，也没有配音**（做视频的这台机器录不了游戏，也没有能用的中文语音合成）。下面有补上的办法。
- 音轨是静音的，B 站的上传编辑器里可以直接加背景音乐（用它自带的曲库，不用担心版权）。

## 标题（二选一，B 站标题最多 80 字）

```
【绝地潜兵2】Chef 和 MDL3 终于能一起用了！HUDdle + BF5 击杀反馈同时开｜Chef Hand-off for MDL3
```
```
绝地潜兵2｜HUDdle 和 BF5 击杀反馈只能二选一？Chef Hand-off 让它们一起跑
```
备选：`【绝地潜兵2 MOD】一个小 mod 让 Chef 加载器和 MDL3 共存：HUDdle、Treasure Radar 不用再二选一`

## 简介

```
Chef Hand-off for MDL3 0.2.0：让 Chef Shared Loader 和 MDL3 在《绝地潜兵 2》里一起工作。

【解决什么问题】
游戏只运行一个 boot 脚本，Chef 和 MDL3 都想当它，默认只能二选一：Chef 在上，HUDdle、Treasure Radar 能用，MDL3 和它的 mod（比如 BF5 击杀反馈的 MDL3 版）不能用；MDL3 在上则相反。

【它做什么】
一个由 MDL3 启动的小 addon，进游戏约 6 秒后，按 Chef 文档里写明的办法把游戏交给真正的 Chef。之后 MDL3 照常运行它的 mod，Chef 运行 Chef 的 mod。不包含、不修改 Chef / HUDdle / MDL3 的任何文件，纯 Lua。0.2.0 还修了 Treasure Radar 被 Chef 跳过的问题。

【安装】
1. 照常装好 MDL3、Chef Shared Loader（1.2.0 以上）和要用的 mod
2. 把 zip 加进 Arsenal / HD2 Mod Manager 并启用
3. MDL3 的优先级要比 Chef 高（和 Chef、HUDdle 的说明相反）：Arsenal 的设置是 First mod highest priority，就把 MDL3 放在 Chef 上面；是 Last mod highest priority，就放在下面
4. Purge → Deploy，启动游戏，在标题画面等 10 秒再进任务

【下载 / 源码】
Nexus Mods：（上架后把链接补在这里）
GitHub：https://github.com/JFRedist/HD2-Chef-Handoff-for-MDL3 （Releases 页下载 zip，MIT 开源）

【实测环境】MDL3 3.0.0-dev.29 · Chef Shared Loader 1.4.1 · HUDdle 0.6.11 · Treasure Radar 0.7.1n · BF5 击杀反馈（MDL3 版）2.0.1
【已知问题】只在 MDL3 预览版上测过；0.1.0 时任务中按 ESC 回飞船闪退过一次，原因没找到，之后没再出现。

【感谢】Chef Shared Loader（Th3chef）、HUDdle（rosensterner）、MDL3 和 BF5 击杀反馈的作者。
【声明】本视频是程序渲染的动画讲解，没有游戏录像。mod 的代码是在 Claude（Anthropic 的 AI）协助下编写的，作者在真实游戏里测试。
```

## 标签（最多 10 个）

`绝地潜兵2` `Helldivers2` `MOD` `游戏MOD` `HUDdle` `Chef Shared Loader` `MDL3` `教程` `开源` `游戏工具`

## 分区、类型、封面

- 类型：**自制**。
- 分区：游戏区里最接近的子区，并在投稿页关联游戏"绝地潜兵2"。我这里打不开 B 站，没法核对它现在的分区列表。
- 封面：`Chef-Hand-off-for-MDL3-cover.png`（1920×1200，16:10；B 站推荐 1146×717，上传时它会自己缩放）。

## 置顶评论

```
只记一句：MDL3 的优先级要比 Chef 高（和 Chef、HUDdle 的说明相反）。
出问题请带上 %APPDATA%\Arrowhead\Helldivers2 里的 chef_handoff.log、chef_loader.log，和 MDL3 的 MDL.log（MDL.log 每次启动会被覆盖，闪退后先拷出来再重开游戏）。
```

## 投稿前

0. **字幕文件（.srt）只是口播稿的时间轴**：字幕已经烧在画面里了，别再把它当 CC 字幕传一遍，否则会重影。要用 B 站的 CC 字幕，需要重新渲染一版不带字幕的（改 `promo/scenes.html`，让 `#sub` 不显示）。
1. **声明**：B 站投稿页有"创作声明"之类的选项（包括 AI 生成内容）。我打不开 B 站，没法核对它现在的规则；请按实际情况选：画面是程序渲染的动画，不是 AI 生成的图像，但文案和 mod 代码有 AI 协助。简介末尾已经写明。
2. **补游戏画面（建议）**：录 10～20 秒真机画面，一局任务里 HUDdle 和 BF5 击杀反馈同时在起作用，插在 1:19.8 的位置（字幕"进任务：HUDdle、Treasure Radar 在跑…"那一句），比任何动画都有说服力。
3. **配音（可选）**：照下面的口播稿念一遍，音量别盖过背景音乐；不配音也行，字幕已经在画面里。
4. **Nexus 链接**：上架后把链接补进简介。视频最后一屏只写了"下载和源码见简介"，没有写死链接。
5. 视频里没有用任何游戏素材或 Logo，只在文字里提到游戏名。

## 口播稿（和字幕同一份，时间对应视频）

| 时间 | 口播（也是字幕） |
|---|---|
| 0:06.6 – 0:11.0 | HUDdle 这类 Chef 的 mod，和 MDL3 的 mod， 是不是只能二选一？ |
| 0:11.2 – 0:16.8 | 游戏只运行一个 boot 脚本。 Chef 在上，MDL3 和 BF5 击杀反馈就不工作 |
| 0:17.2 – 0:23.6 | MDL3 在上，HUDdle 又起不来 |
| 0:24.5 – 0:29.8 | Chef Hand-off 是一个由 MDL3 启动的小 addon |
| 0:30.2 – 0:35.6 | 进游戏 6 秒后，它按 Chef 文档里写明的办法， 把游戏交给真正的 Chef |
| 0:36.0 – 0:39.8 | 之后两边各跑各的，互不干扰 |
| 0:40.5 – 0:45.8 | MDL3 会把 Chef 的 mod 也“启动”一遍， 只是给它们的不是 Chef |
| 0:46.2 – 0:50.8 | 没报错的 Treasure Radar， 会被 Chef 当成已经启动，直接跳过 |
| 0:51.2 – 0:55.8 | 0.2.0 交接前先读补丁文件，认出做给 Chef 的 addon， 让 Chef 正常启动它们 |
| 0:56.5 – 0:59.8 | 安装：加进 Arsenal 并启用 |
| 1:00.2 – 1:07.6 | 关键：MDL3 的优先级要比 Chef 高 这和 Chef、HUDdle 的说明正好相反 |
| 1:08.0 – 1:13.6 | Purge、Deploy，启动游戏， 在标题画面等 10 秒 |
| 1:14.4 – 1:19.4 | chef_handoff.log 里出现 Chef Shared Loader 1.4.1 started 就成功了 |
| 1:19.8 – 1:23.8 | 进任务：HUDdle、Treasure Radar 在跑， BF5 击杀反馈照常 |
| 1:24.4 – 1:28.0 | 实测环境：MDL3 3.0.0-dev.29，Chef 1.4.1 |
| 1:28.2 – 1:31.8 | 只在 MDL3 预览版上测过。0.1.0 时按 ESC 回飞船 闪退过一次，原因未明，之后没再出现 |
| 1:32.4 – 1:38.4 | MIT 开源，下载和源码见简介 Chef Hand-off for MDL3 |
