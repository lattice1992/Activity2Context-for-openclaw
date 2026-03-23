# Activity2Context 安装指引（仅 GitHub）

适用场景：不使用 ClawHub，只通过 GitHub 下载并启用。

## 核心原则

- 仓库解压到哪里都可以，不需要放到 OpenClaw 安装目录。
- `-Workspace` 必须是你自己的 OpenClaw 工作区路径。
- 不需要安装 Skill；这是 Runtime + Prompt Injection 模式。

## 1) 下载并解压

1. 打开仓库页面。
2. 点击 `Code -> Download ZIP`。
3. 解压到任意目录（示例：`D:\tools\activity2context`）。

## 2) 安装并启动 Runtime

在 PowerShell 中执行：

```powershell
cd D:\tools\activity2context
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "$PWD"
```

如果你的 OpenClaw 工作区不是当前目录：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "C:\你的\OpenClaw工作区"
```

## 3) 检查运行状态

```powershell
$env:USERPROFILE\.activity2context\activity2context.cmd status
```

看到以下字段为 `true` 即正常：

- `observerRunning`
- `indexerRunning`

## 4) 配置 OpenClaw 注入

```powershell
openclaw config set hooks.internal.enabled true --strict-json
openclaw config set hooks.internal.entries.bootstrap-extra-files.enabled true --strict-json
openclaw config set "hooks.internal.entries.bootstrap-extra-files.paths[0]" "activity2context/memory.md"
```

## 5) 验证生效

1. 确认 `<workspace>\activity2context\memory.md` 存在。
2. 在 OpenClaw 发测试消息。
3. 看到 memory 注入相关信息即表示生效。

## 常见问题

1. 看不到 `memory.md`：
先进行一些真实操作（切应用、打开网页、编辑文件），等待 1-2 分钟后再看。

2. raw behavior 会无限增长吗：
默认不会。启动时会自动保留最近 `5000` 行（`observer.maxBehaviorLines`）。

3. 想停止后台服务：

```powershell
$env:USERPROFILE\.activity2context\activity2context.cmd stop
```
