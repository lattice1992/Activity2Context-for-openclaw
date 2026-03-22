# Activity2Context 安装指引（仅用 GitHub）

适用人群：不使用 ClawHub，只通过 GitHub 下载并在本机启用。

## 核心原则

- 仓库解压到哪里都可以（不是必须放在 OpenClaw 安装目录）。
- `-Workspace` 必须填写你正在使用的 OpenClaw 工作区路径。
- 只要 `Workspace` 对，OpenClaw 就能读取 `activity2context/memory.md`。

## 步骤 1：下载并解压

1. 打开仓库页面，点击 `Code -> Download ZIP`
2. 解压到任意目录（示例：`D:\tools\activity2context`）

## 步骤 2：安装并启动 Runtime

在 PowerShell 中执行：

```powershell
cd D:\tools\activity2context
powershell -ExecutionPolicy Bypass -File .\install\windows\install.ps1 -Workspace "D:\AIproject"
```

说明：
- `D:\tools\activity2context` 是你解压仓库的位置
- `D:\AIproject` 是你的 OpenClaw 工作区（按你自己的实际路径替换）

## 步骤 3：确认运行状态

```powershell
$env:USERPROFILE\.activity2context\activity2context.cmd status
```

看到以下字段为 `true` 即正常：
- `observerRunning`
- `indexerRunning`

## 步骤 4：给 OpenClaw 配置 memory 注入

```powershell
openclaw config set hooks.internal.enabled true --strict-json
openclaw config set hooks.internal.entries.bootstrap-extra-files.enabled true --strict-json
openclaw config set "hooks.internal.entries.bootstrap-extra-files.paths[0]" "activity2context/memory.md"
```

## 步骤 5：验证是否生效

1. 在工作区确认文件存在：`D:\AIproject\activity2context\memory.md`
2. 打开 OpenClaw 发一条测试消息
3. 看到与 memory 注入相关的信息，即表示生效

## 常见问题

1. 为什么没有 `memory.md`？
等待 1-2 分钟，并进行一些操作（切应用、打开网页、编辑文件），再检查。

2. 必须放到 OpenClaw 安装目录吗？
不需要。关键是 `-Workspace` 必须是当前 OpenClaw 工作区。

3. 想停止后台服务怎么办？

```powershell
$env:USERPROFILE\.activity2context\activity2context.cmd stop
```

