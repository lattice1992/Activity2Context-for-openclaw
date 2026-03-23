# Activity2Context 工作坊快速上手（Windows，零开发背景）

目标：10 分钟内让 OpenClaw 自动带上用户活动上下文。

## 1. 下载

1. 打开 GitHub 仓库首页
2. 点击 `Code -> Download ZIP`
3. 解压到本地目录（例如 `D:\Activity2Context`）

## 2. 一键安装

1. 进入解压目录
2. 双击 `easy-install-windows.bat`
3. 安装后会自动启动后台 Runtime

## 3. 检查运行状态

1. 双击 `easy-status-windows.bat`
2. 看到 `observerRunning: true` 和 `indexerRunning: true` 即正常

## 4. 验证 memory 文件

1. 双击 `easy-open-memory-windows.bat`
2. 出现 `ID: Web_... / Doc_... / App_...` 即表示采集成功

## 5. 接入 OpenClaw（不需要 Skill）

在 OpenClaw 中启用并配置注入路径：

```powershell
openclaw config set hooks.internal.enabled true --strict-json
openclaw config set hooks.internal.entries.bootstrap-extra-files.enabled true --strict-json
openclaw config set "hooks.internal.entries.bootstrap-extra-files.paths[0]" "activity2context/memory.md"
```

然后重启 OpenClaw，发送一条测试消息验证是否注入成功。

## 常见问题

- 看不到 `memory.md`：
  - 先进行一些真实操作（切应用、打开网页、编辑文件），等待 1-2 分钟
  - 再次打开 `easy-open-memory-windows.bat`

- 状态不是 running：
  - 重新执行 `easy-install-windows.bat`
  - 再执行 `easy-status-windows.bat`

- 想停止后台：
  - 双击 `easy-stop-windows.bat`

