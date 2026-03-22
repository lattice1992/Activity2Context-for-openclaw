# Activity2Context 工作坊快速上手（Windows，零开发背景）

目标：10 分钟内让 OpenClaw 自动带上用户活动上下文。

## 1. 下载

1. 打开 GitHub 仓库首页
2. 点 `Code` -> `Download ZIP`
3. 解压到一个本地目录（例如：`D:\Activity2Context`）

## 2. 一键安装

1. 进入解压后的目录
2. 双击 `easy-install-windows.bat`
3. 安装完成后，会自动启动后台运行

## 3. 检查是否在运行

1. 双击 `easy-status-windows.bat`
2. 看到 `observerRunning: true` 和 `indexerRunning: true` 就是正常

## 4. 验证 memory 文件

1. 双击 `easy-open-memory-windows.bat`
2. 如果文件里有 `ID: Web_...` / `ID: Doc_...` / `ID: App_...`，说明采集成功

## 5. 接入 OpenClaw

1. 在 ClawHub 安装 Skill：`activity2context-for-openclaw`
2. 在 OpenClaw 工作区中，确保注入路径是：
   - `activity2context/memory.md`
3. 发一条测试消息，观察是否出现 memory 注入信息

## 常见问题

- 看不到 `memory.md`：
  - 先活动一下电脑（切应用、打开网页、编辑文件）并等待 1-2 分钟
  - 再点 `easy-open-memory-windows.bat`

- 状态不是 running：
  - 重新双击 `easy-install-windows.bat`
  - 再双击 `easy-status-windows.bat`

- 想停止后台运行：
  - 双击 `easy-stop-windows.bat`

