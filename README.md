# Activity2Context for OpenClaw

English version: `README.en.md`

想象一个 Agent 能“看你所看，知你所做”。

当你要高效指挥它时，只需要说目标，不再每轮重复喂背景。

## 它解决了什么问题

- 背景断层：你明明刚改过文件、看过网页，Agent 却不知道。
- 沟通成本高：每次都要重复“我刚刚在做什么”。
- Token 浪费：把原始行为日志直接塞给模型，噪音高、成本高。

## 它怎么工作

Activity2Context 是一个 Runtime Hook，不是 Skill。

它的工作流是：

1. Capture：持续采集本机行为（浏览器、文档、应用）。
2. Aggregate：把原始行为流压缩成结构化实体。
3. Inject：在每次对话前，把 `activity2context/memory.md` 注入到 OpenClaw system prompt。

## 采集范围（当前）

- Browser：页面标题、URL、停留时长、最近活跃时间。
- Document：文件路径、编辑次数、最近活跃时间。
- App：应用名、窗口标题、聚焦时长、最近活跃时间。

输出文件：

- 原始行为流：`<workspace>/.openclaw/activity2context_behavior.md`
- 注入记忆文件：`<workspace>/activity2context/memory.md`

## 为什么它不会无限膨胀

- 原始日志支持上限：`observer.maxBehaviorLines`（默认 `5000`）。
- 启动时自动裁剪到最近 N 行（默认 5000）。
- 记忆文件是聚合结果，不是全量原始日志。

## 常见担心

### 1) 会不会大幅增加 Token 消耗？

不会显著增加。注入的是聚合后的 `memory.md`，不是全量 raw log。
默认只保留有限实体（Web/Doc/App），且按最近活跃度筛选。

### 2) 会不会有隐私风险？

默认数据都在本地生成和存储，不主动上传。
但如果你使用云模型，注入到 prompt 的 `memory.md` 内容会随请求发给模型提供方。
如果是高敏感场景，建议本地模型或降低采集范围。

### 3) 会不会影响机器性能？

设计为轻量轮询，默认 2 秒采样，聚合按周期执行。
并且 raw 文件有上限裁剪，避免无限增长导致 I/O 退化。

### 4) 内置浏览器（如 Steam）能抓到具体 URL 吗？

不保证。当前 URL 抓取主要针对标准浏览器控件。
内置浏览器通常只能稳定记录到 App 层级，不一定能拿到精确 URL。


## 快速开始（Windows）

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "D:\AIproject"
```

常用命令：

```powershell
$env:USERPROFILE\.activity2context\activity2context.cmd status
$env:USERPROFILE\.activity2context\activity2context.cmd start
$env:USERPROFILE\.activity2context\activity2context.cmd stop
$env:USERPROFILE\.activity2context\activity2context.cmd index
```

零开发背景可直接看：

- `WORKSHOP_QUICKSTART.zh-CN.md`
- `INSTALL_GITHUB_ONLY.zh-CN.md`

## 快速开始（macOS）

在仓库根目录执行：

```bash
bash ./install/macos/install.sh --workspace "$PWD"
```

常用命令：

```bash
~/.activity2context/activity2context status
~/.activity2context/activity2context start
~/.activity2context/activity2context stop
~/.activity2context/activity2context index
```

macOS 需要授权：

- Accessibility（前台应用与窗口检测）
- Automation（读取 Chrome/Edge/Brave/Safari URL）
- Python 3（`/usr/bin/python3`）

## OpenClaw 接入（核心）

只需要保证 `memory.md` 会被注入，不需要 Skill。

```bash
openclaw config set hooks.internal.enabled true --strict-json
openclaw config set hooks.internal.entries.bootstrap-extra-files.enabled true --strict-json
openclaw config set "hooks.internal.entries.bootstrap-extra-files.paths[0]" "activity2context/memory.md"
```

更多见：`integrations/openclaw/README.md`

## 配置

配置文件：

- `~/.activity2context/config.json`

模板：

- `config/activity2context.example.json`
- `config/activity2context.macos.example.json`

关键参数：

- `observer.pollSeconds`
- `observer.browserThreshold`
- `observer.browserUpdateInterval`
- `observer.appThreshold`
- `observer.appUpdateInterval`
- `observer.maxBehaviorLines`（默认 5000）
- `indexer.intervalSeconds`
- `indexer.minDurationSeconds`
- `indexer.maxAgeMinutes`
- `indexer.maxTotal`
- `indexer.maxWeb`
- `indexer.maxDoc`
- `indexer.maxApp`

## 卸载

Windows：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\uninstall.ps1
```

macOS：

```bash
bash ./install/macos/uninstall.sh
```

保留数据仅移除运行时：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\uninstall.ps1 -KeepData
```

```bash
bash ./install/macos/uninstall.sh --keep-data
```
