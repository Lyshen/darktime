# Darktime Code Structure Split Plan

## 目标

这次拆分的目标不是重写功能，而是把已经变大的 MVP 代码按职责拆开，让后续继续打磨 Capture、Inbox、Clear、Attention 时不再挤进一个大文件里。

本分支优先做结构整理：

- 不改变现有产品行为。
- 不重写 SQLite schema。
- 不改 MCP tool 的对外协议。
- 每一步拆分后都能通过 `npm run build:all`。

## 当前问题

目前项目能跑，但结构已经开始变重：

```text
Sources/Darktime/CalendarAppUI.swift              约 1900 行，拆分前
Sources/Darktime/App/DarktimeCommand.swift        约 680 行
Sources/Darktime/Core/Persistence/LocalDatabase.swift 约 550 行
src/mcp-server.ts                                 约 970 行
```

其中最明显的问题是 `CalendarAppUI.swift` 同时包含：

- App 启动和菜单
- Window / Quick Capture Panel 管理
- DashboardModel 状态模型
- 主界面布局
- Capture / Inbox / Attention / Calendar 页面
- Quick Capture 输入框
- 通用 UI 组件
- 颜色、日期格式化等工具函数

这会让小改动也变得不透明，后续 UI 打磨和产品逻辑都会互相干扰。

## 拆分原则

1. 先做物理拆分，暂不做架构重写。
2. SwiftPM 同一个 target 下可以直接识别子目录里的 Swift 文件，因此不需要改 Package 结构。
3. 文件按产品概念和技术职责命名，而不是按历史功能名堆叠。
4. View、Model、Window 管理、Storage、Bridge、MCP Server 分层清楚。
5. 保留 MVP 简洁性，先不引入复杂模块系统或依赖注入框架。

## 目标目录

```text
Sources/Darktime/
  Info.plist

  App/
    DarktimeCommand.swift
    DarktimeApp.swift
    DarktimeAppDelegate.swift
    ApplicationMenu.swift

  Features/
    AppShell/
      DarktimeDashboard.swift
      DashboardModel.swift
      WorkspaceSection.swift
      WorkspaceRail.swift
      SidebarResizeHandle.swift

    Capture/
      CaptureWorkspace.swift

    QuickCapture/
      QuickCapturePanel.swift
      QuickCaptureTextInput.swift
      QuickCaptureWindow.swift

    Inbox/
      InboxWorkspace.swift

    Attention/
      AttentionWorkspace.swift

    Matters/
      MatterWorkspace.swift
      MatterList.swift
      MatterActionBars.swift

    CalendarIntegration/
      CalendarWorkspace.swift
      CalendarPanels.swift
      CalendarRows.swift

  Core/
    Persistence/
      LocalDatabase.swift
      MatterRepository.swift
      StorageModels.swift

    Integrations/
      Calendar/
        AppleCalendarService.swift
      MCP/
        MCPCommandProvider.swift

  SharedUI/
    Components/
      Pane.swift
      WorkspaceTopBar.swift
      WorkspaceTitle.swift
      InfoComponents.swift

    Theme/
      Theme.swift
```

## 文件职责

### App

`DarktimeApp.swift`

- 保留 `launchDarktimeAppUI()`。
- 只负责启动 AppKit app。

`DarktimeAppDelegate.swift`

- 管理 app 生命周期。
- 持有主窗口、quick capture panel、DashboardModel。
- 处理全局快捷键。

`ApplicationMenu.swift`

- 配置 macOS 菜单项。
- 包含 Quick Capture、Calendar、Quit 等菜单动作入口。

### Features

`Features/AppShell`

- 主界面 shell，包含 Dashboard、左侧栏、主导航枚举和 DashboardModel。
- 这不是业务领域层，而是 app 的主操作台。

`Features/Capture`

- 主窗口里的 Capture 工作区。

`Features/QuickCapture`

- 全局快捷 capture 浮窗。
- 这是用户高频入口，所以单独成为 feature。

`Features/Inbox` / `Features/Attention` / `Features/Matters`

- Inbox 和 Attention 页面。
- Matters 里放这些页面共享的列表和动作条。

`Features/CalendarIntegration`

- Calendar 不是产品主轴，而是一个 integration 的用户界面。
- 它保留为二级功能，而不是顶层产品目录。

### Core

`Core/Persistence`

- SQLite、本地导入、repository 和存储快照模型。
- `LocalDatabase` 是底层数据库 facade。
- `MatterRepository` 是面向产品动作的持久化接口。

`Core/Integrations`

`MCPCommandProvider.swift`

- 封装本机 MCP server 启动命令生成。
- 让 UI model 不直接理解 app bundle 和 repo build 路径。

`AppleCalendarService.swift`

- 封装 Apple Calendar 权限和日历列表读取。
- 让 DashboardModel 不直接依赖 EventKit 细节。

### SharedUI

`SharedUI/Components`

- 无业务含义的通用 UI 小组件。

`SharedUI/Theme`

- 颜色、日期格式化、状态颜色等视觉基础设施。

## 暂不优先拆的部分

`App/DarktimeCommand.swift`

- 这是 Apple Calendar CLI / EventKit bridge。
- 当前虽然偏长，但它的职责还算集中。
- 等 Mac App UI 拆完后，再考虑拆成：

```text
Bridge/
  DarktimeCommand.swift
  BridgeOptions.swift
  BridgeResponses.swift
  EventKitCalendarService.swift
  EventKitFormatters.swift
```

## 物理拆分之后仍然不清晰的原因

物理拆分解决的是“文件太大”的问题，但不会自动解决“系统边界”的问题。

当前不清晰主要来自三个历史原因：

1. 顶层模块曾经叫 `CalendarBridge`，但产品已经从日历桥接变成 Darktime。这个名字会误导读代码的人，以为 Calendar 是主产品。
2. `DashboardModel` 仍然承担太多职责：UI state、Matter 操作、Calendar authorization、MCP command、Storage refresh 都在一起。
3. Apple Calendar、MCP、本地 Inbox、Attention 是不同领域能力，但目前还没有形成清楚的 domain/service 边界。

所以拆完文件后，下一步不是继续把文件切得更碎，而是把逻辑层次整理出来：

```text
App Shell
  macOS lifecycle, windows, menu, global shortcut

Product State
  selected workspace, current matters, quick capture draft

Domain
  Matter, Inbox, Attention, Capture

Services
  Local storage
  Apple Calendar
  MCP integration

UI
  Dashboard
  Workspaces
  Quick Capture
  Components
```

后续最重要的重构方向：

- `DashboardModel` 已经通过 `MatterRepository`、`AppleCalendarService`、`MCPCommandProvider` 隔离了底层能力。
- 下一步如果继续瘦身，应该抽 use case，而不是继续把 UI 文件切碎。
- 让 UI 只依赖产品状态和动作，不直接理解 SQLite、EventKit、MCP 的细节。

`src/mcp-server.ts`

- 现在也偏长，但它是另一条链路。
- 建议第二轮拆，目标可以是：

```text
src/
  mcp-server.ts
  bridge.ts
  logging.ts
  storage.ts
  tools/
    calendar-tools.ts
    matter-tools.ts
```

## 拆分步骤

### Step 1: Mac App UI 物理拆分

- 从 `CalendarAppUI.swift` 拆出 App、Features、Core、SharedUI。
- 不修改 UI 行为。
- 不改数据库。
- 不改 MCP。
- 每移动一组文件后运行 build。

### Step 2: Persistence 拆分

- 把 snapshot structs 移到 `Core/Persistence/StorageModels.swift`。
- 把 SQLite facade 改名为 `LocalDatabase`。
- 用 `MatterRepository` 对 UI model 暴露持久化动作。

### Step 3: 观察是否需要改访问级别

拆分后，当前大量 `private` 声明会需要调整成 target 内可见。

处理原则：

- 只移除必要的 `private`。
- 不主动改成 `public`。
- 能保持 `private` 的 helper 继续留在同文件内。

### Step 4: 构建验证

每轮拆分至少验证：

```bash
npm run build:all
```

如果改到打包脚本或 app bundle，再验证：

```bash
npm run build:dmg
```

## 本分支的完成标准

- `CalendarAppUI.swift` 不再是主容器文件，最好缩小到 0 或只剩极少兼容入口。
- Quick Capture 相关代码进入独立目录。
- Capture / Inbox / Attention / Calendar 页面各自独立。
- 主 Dashboard 文件只负责组合布局。
- 构建通过。
- 产品行为保持不变。
