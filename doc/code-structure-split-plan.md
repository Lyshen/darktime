# Darktime Code Structure Split Plan

## 目标

这次拆分的目标不是重写功能，而是把已经变大的 MVP 代码按职责拆开，让后续继续打磨 Capture、Inbox、Clear、Rootbox 时不再挤进一个大文件里。

本分支优先做结构整理：

- 不改变现有产品行为。
- 不重写 SQLite schema。
- 不改 MCP tool 的对外协议。
- 每一步拆分后都能通过 `npm run build:all`。

## 当前问题

目前项目能跑，但结构已经开始变重：

```text
Sources/CalendarBridge/CalendarAppUI.swift    约 1900 行
Sources/CalendarBridge/CalendarBridge.swift   约 680 行
Sources/CalendarBridge/DarktimeStorage.swift  约 600 行
src/mcp-server.ts                             约 970 行
```

其中最明显的问题是 `CalendarAppUI.swift` 同时包含：

- App 启动和菜单
- Window / Quick Capture Panel 管理
- DashboardModel 状态模型
- 主界面布局
- Capture / Inbox / Rootbox / Calendar 页面
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
Sources/CalendarBridge/
  CalendarBridge.swift
  Info.plist

  App/
    DarktimeApp.swift
    CalendarAppDelegate.swift
    ApplicationMenu.swift
    AppWindows.swift

  Models/
    DashboardModel.swift
    WorkspaceSection.swift

  UI/
    DarktimeDashboard.swift

    Theme/
      DTColor.swift
      Formatters.swift

    Components/
      Pane.swift
      WorkspaceTopBar.swift
      WorkspaceTitle.swift
      EmptyStateLine.swift
      SignalDot.swift
      Tags.swift

    Sidebar/
      WorkspaceRail.swift
      RailItemButton.swift
      SidebarResizeHandle.swift

    Workspaces/
      CaptureWorkspace.swift
      InboxWorkspace.swift
      RootboxWorkspace.swift
      MatterWorkspace.swift
      CalendarWorkspace.swift

    Matters/
      MatterList.swift
      MatterRow.swift
      MatterActionBars.swift

    QuickCapture/
      QuickCapturePanel.swift
      QuickCaptureTextInput.swift
      QuickCaptureWindow.swift

    Calendar/
      SourcesPanel.swift
      StatusPanel.swift
      AgentsPanel.swift
      CalendarRows.swift

  Storage/
    DarktimeStorage.swift
    StorageModels.swift
```

## 文件职责

### App

`DarktimeApp.swift`

- 保留 `launchCalendarAppUI()`。
- 只负责启动 AppKit app。

`CalendarAppDelegate.swift`

- 管理 app 生命周期。
- 持有主窗口、quick capture panel、DashboardModel。
- 处理全局快捷键。

`ApplicationMenu.swift`

- 配置 macOS 菜单项。
- 包含 Quick Capture、Calendar、Quit 等菜单动作入口。

`AppWindows.swift`

- 创建主窗口和 quick capture panel。
- 放置窗口透明、尺寸、层级、焦点等 AppKit 细节。

### Models

`DashboardModel.swift`

- UI 状态和数据刷新逻辑。
- Matter capture / move / refresh。
- Calendar authorization 状态读取。

`WorkspaceSection.swift`

- Capture / Inbox / Rootbox / Calendar 等主导航枚举。

### UI

`DarktimeDashboard.swift`

- 只保留主界面组合关系。
- 不放具体 workspace 的大段实现。

`UI/Workspaces`

- 每个主页面一个文件。
- Capture、Inbox、Rootbox、Matter、Calendar 分离。

`UI/QuickCapture`

- Quick Capture 浮窗的 SwiftUI 面板、原生输入框、窗口类分离。
- 这是后续继续打磨手感最频繁的区域，需要单独维护。

`UI/Sidebar`

- 左侧导航栏、item、拖拽宽度控件。

`UI/Matters`

- Matter 列表、Matter 行、Clear/Rootbox action bar。

`UI/Calendar`

- 现有 Apple Calendar dashboard 相关面板先作为子功能保留。
- Sources、Status、Agents、Calendar rows 归到这里。

`UI/Theme`

- 颜色、时间格式化、状态颜色等视觉基础设施。

`UI/Components`

- 可复用的小组件，避免散落在页面文件底部。

### Storage

`DarktimeStorage.swift`

- 暂时保留 SQLite 操作主体。
- 本次只建议先把 snapshot struct 移到 `StorageModels.swift`。

`StorageModels.swift`

- `MCPSessionSnapshot`
- `ActionLogSnapshot`
- `MatterSnapshot`
- `MatterLogSnapshot`

## 暂不优先拆的部分

`CalendarBridge.swift`

- 这是 Apple Calendar CLI / EventKit bridge。
- 当前虽然偏长，但它的职责还算集中。
- 等 Mac App UI 拆完后，再考虑拆成：

```text
Bridge/
  CalendarBridge.swift
  BridgeOptions.swift
  BridgeResponses.swift
  EventKitCalendarService.swift
  EventKitFormatters.swift
```

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

- 从 `CalendarAppUI.swift` 拆出 App、Models、UI、QuickCapture、Workspaces、Components。
- 不修改 UI 行为。
- 不改数据库。
- 不改 MCP。
- 每移动一组文件后运行 build。

### Step 2: Storage Models 拆分

- 把 snapshot structs 移到 `Storage/StorageModels.swift`。
- 保持 `DarktimeStorage` API 不变。

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
- Capture / Inbox / Rootbox / Calendar 页面各自独立。
- 主 Dashboard 文件只负责组合布局。
- 构建通过。
- 产品行为保持不变。

