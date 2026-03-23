# Activity2Context for OpenClaw

English version: `README.md`

想象一个 Agent 能“看你所看，知你所做”。  
当你要高效指挥时，只需要说目标，不再每轮重复反哺背景。

## 它解决了什么问题

- 背景断层：你刚改过文件、看过页面，Agent 却不知道。
- 重复沟通：每次都要补一句“我刚刚在做什么”。
- Token 浪费：原始行为日志噪音高，直接喂模型成本高。

## 它怎么工作

Activity2Context 是 Runtime Hook，不是 Skill。

流程：

1. Capture：持续采集本机行为（浏览器、文档、应用）。
2. Aggregate：将原始行为流压缩为结构化实体。
3. Inject：每次对话前把 `activity2context/memory.md` 注入 OpenClaw system prompt。

## 当前采集范围

- Browser：页面标题、URL、停留时长、最后活跃时间。
- Document：文件路径、编辑次数、最后活跃时间。
- App：应用名、窗口标题、聚焦时长、最后活跃时间。

输出文件：

- 原始行为流：`<workspace>/.openclaw/activity2context_behavior.md`
- 注入记忆：`<workspace>/activity2context/memory.md`

## 为什么不会无限增长

- 原始日志有上限：`observer.maxBehaviorLines`（默认 5000）。
- 启动时自动裁剪到最近 N 行。
- 注入的是聚合后的 `memory.md`，不是全量 raw log。

## 快速开始（Windows）

在仓库根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "$PWD"
```

如果你的 OpenClaw 工作区不等于当前目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "C:\你的\OpenClaw工作区"
```

常用命令：

```powershell
$env:USERPROFILE\.activity2context\activity2context.cmd status
$env:USERPROFILE\.activity2context\activity2context.cmd start
$env:USERPROFILE\.activity2context\activity2context.cmd stop
$env:USERPROFILE\.activity2context\activity2context.cmd index
```

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

macOS 权限要求：

- Accessibility（前台应用和窗口检测）
- Automation（读取 Chrome/Edge/Brave/Safari URL）
- Python 3（`/usr/bin/python3`）

## OpenClaw 接入（核心）

只需要注入 `memory.md`，不需要 Skill。

```bash
openclaw config set hooks.internal.enabled true --strict-json
openclaw config set hooks.internal.entries.bootstrap-extra-files.enabled true --strict-json
openclaw config set "hooks.internal.entries.bootstrap-extra-files.paths[0]" "activity2context/memory.md"
```

更多说明见：`integrations/openclaw/README.md`

## 常见担心

### 1) 会不会增加很多 Token 消耗？

通常不会。注入的是聚合结果 `memory.md`，不是全量 raw log。  
实体数量和时间窗口都有限制。

### 2) 隐私是否安全？

默认所有采集与存储都在本地。  
但如果你使用云模型，注入到 prompt 的内容会发送给模型提供方。  
高敏感场景建议使用本地模型或收紧采集范围。

### 3) 性能会受影响吗？

运行机制是轻量轮询 + 周期聚合。  
并有日志上限裁剪，避免无上限 I/O 增长。

### 4) 像 Steam 这种内置浏览器能抓到精确 URL 吗？

不保证。当前 URL 抓取主要面向标准浏览器控件。  
内置浏览器通常只能稳定记录到 App 层级。

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
