# Darktime Architecture Boundary Notes

## 这份笔记解决什么

物理拆分之后，代码已经不再挤在一个大文件里，但“逻辑是否清晰”是另一件事。

现在真正需要继续判断的是：

- 哪些词应该进入代码模型。
- 哪些词只是产品表达，暂时不应该污染代码。
- Calendar 这种能力到底是核心业务，还是 Capture 体系里的连接来源/去向。
- 下一步怎么拆，才不是越拆越碎。

## 命名不要过早产品化

一个词进入代码之后，会变成系统边界。它不只是名字，还会影响数据库、MCP tool、UI 状态、目录结构、测试和后续迁移成本。

所以命名应该分层：

```text
Brand Name
  Darktime

Domain Concepts
  Capture, Inbox, Matter, Rootbox

Technical Roles
  Store, Repository, Service, Connector, ViewModel

Provider Names
  Apple Calendar, MCP, SQLite

UI Names
  Workspace, Panel, Row, Button
```

### Darktime

`Darktime` 适合用于：

- Swift target 名。
- App 启动入口。
- App bundle / icon / distribution artifacts。

但不适合到处加前缀，例如不需要：

```text
DarktimeMatterStore
DarktimeCapturePanel
DarktimeDashboardModel
```

这些名字会让代码变吵，而且没有增加信息量。

### Matter

`Matter` 是一个危险但有价值的词。

它有价值，是因为它试图表达“进入注意力系统的一件东西”，比 task/note/event 都宽。

它危险，是因为产品概念还没有完全稳定。如果太早让它渗透到所有层，会导致后面想改成 `InboxItem`、`CaptureItem`、`OpenLoop` 时成本很高。

当前建议：

- 可以暂时保留在业务模型层和已有数据库/MCP 接口里。
- 不要继续扩散到 UI 组件、服务、连接器层。
- 后续如果产品语言更清楚，再决定是否把 `Matter` 正式升格为核心 domain term。

更保守的替代命名：

```text
CapturedItem
InboxItem
OpenLoop
AttentionItem
```

其中 `InboxItem` 最朴素，但不够表达长期生命力；`OpenLoop` 更贴近心理负担；`Matter` 更有品牌气质，但抽象度高。

### Rootbox

`Rootbox` 比 `Matter` 更应该谨慎。

它现在更像产品愿景，不一定是 v0 里已经成立的稳定领域对象。

当前建议：

- UI 可以出现 Rootbox。
- 数据状态可以保留 `rootbox`，因为已有流转需要。
- 暂时不要建立复杂的 `Root`、`RootboxService`、`RootRepository`。

## Calendar 的位置

现在 Calendar 不应该再被当作主产品层级。

它更像 Capture 系统的一个 integration：

```text
Source
  从日历读上下文：今天有什么安排、哪里有空档

Sink
  把规划结果写回日历：形成真实时间块

Context Provider
  为 Clear / Planning 提供现实约束
```

所以 Calendar 不应该长期待在主导航的核心左侧，也不应该占据项目顶层名字。

更合理的代码边界是：

```text
Integrations/
  Calendar/
    CalendarConnector.swift
    AppleCalendarConnector.swift
    CalendarModels.swift
```

未来如果接 Google、Outlook、Feishu，也应该在 connector 层磨平差异，而不是让 UI 或 DashboardModel 直接知道每家 API。

## 当前结构的问题

现在已经比之前清楚，但仍然有几个不理想的地方：

1. `DashboardModel` 仍然是一个 presentation model + app coordinator 的混合体。
2. `MatterRepository` 仍然带着 `Matter` 这个未完全稳定的产品词，但它已经被限制在 persistence 边界内。
3. `AppleCalendarService` 已经挂到 `Core/Integrations/Calendar`，但后续还可以抽象成 connector protocol。
4. `DarktimeCommand.swift` 仍然混着 app launch 和 CLI bridge。
5. MCP server 还在 TypeScript 单文件里，后续也会成为类似问题。

## 当前落地结构

当前不硬套 DDD，而是采用更适合 Mac app MVP 的 Feature + Core + SharedUI 结构：

```text
Sources/Darktime/
  App/
  Features/
    AppShell/
    Capture/
    QuickCapture/
    Inbox/
    Rootbox/
    Matters/
    CalendarIntegration/
  Core/
    Persistence/
    Integrations/
  SharedUI/
```

其中：

```text
App
  macOS 生命周期、窗口、菜单、快捷键

Features
  用户能感知的产品功能和主界面 shell

Core/Persistence
  SQLite、repository、本地文件导入、存储快照

Core/Integrations
  Calendar、MCP、未来 Feishu/Google/Outlook 等外部能力

SharedUI
  无业务语义的 SwiftUI 组件和主题
```

### Step 2: 暂缓重命名 Matter

不建议现在立刻把 `Matter` 全改掉。

理由：

- 数据库 schema 已经有 `matters`。
- MCP tool 已经有 `matter_create` 等接口。
- 产品概念还没最终稳定，现在改名可能只是从一个不确定换到另一个不确定。

更好的做法是先隔离它：

```text
Core/Persistence/MatterRepository.swift
Features/Matters/
```

等产品语言成熟后，再决定是否整体迁移。

### Step 3: Calendar 作为 Integration

```text
Core/Integrations/Calendar/AppleCalendarService.swift
Features/CalendarIntegration/
```

这表达 Calendar 是 Darktime 的连接能力和二级界面，而不是产品中心。

### Step 4: 拆 DarktimeCommand

`DarktimeCommand.swift` 后面应该拆成：

```text
Command/
  DarktimeCommand.swift
  CommandOptions.swift
  CommandResponses.swift

Integrations/Calendar/EventKit/
  EventKitCalendarBridge.swift
  EventKitFormatters.swift
```

这样 CLI 只是入口，EventKit 才是 provider 实现。

## 当前最重要的判断

不要为了“看起来架构高级”继续拆。

下一步最值得做的是：

1. 把命名污染控制住。
2. 把 Calendar 放回 integration 位置。
3. 把 DashboardModel 继续瘦身成纯 presentation model。
4. 等 Capture / Inbox / Clear / Rootbox 的产品概念更稳定后，再决定核心 domain term。
