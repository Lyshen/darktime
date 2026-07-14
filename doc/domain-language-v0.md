# Darktime 产品语言 v0

这份文档定义当前 MVP 的核心单词、数据含义和流转。

目标是把 Darktime 从 `Rootbox / Seed` 这类隐喻词，收敛到更容易理解和实现的产品语言。

## 一句话

Darktime 是一个本地优先的注意力操作台。

它帮助用户把脑子里的事情先捕捉下来，再判断哪些只是噪音，哪些应该成为 Issue，哪些已经值得作为 Project 持续投入，并用 Output Trace 看见真实投入。

## 核心概念

### Matter

Matter 是刚被捕捉进来的原始内容。

它只表示：

```text
有一件事正在占用我的注意力。
```

Matter 还不是任务、项目、习惯、计划或日历事件。

### Capture

Capture 是把 Matter 放进 Darktime 的动作。

第一版来源包括：

- Mac app 输入。
- Quick Capture。
- Shortcut / iCloud 文件导入。
- 本机 MCP 写入。

Capture 阶段不要求用户分类。

### Inbox

Inbox 是 Matter 的临时缓冲区。

新 Matter 默认进入 Inbox。Inbox 的作用是降低记录压力，而不是要求用户立刻做决定。

### Clear

Clear 是处理 Inbox 的动作。

用户在 Clear 里决定一个 Matter 的去向：

```text
Drop  -> 不值得继续占用注意力，可恢复一小段时间
Done  -> 已经结束，不需要继续追踪
Issue -> 值得注意力处理，但还不一定是持续项目
```

Clear 的目标是减少注意力噪音，不是把所有东西都变成待办。

### Issue

Issue 是经过 Clear 后，被用户承认值得注意力处理的 Matter。

它的含义是：

```text
这件事需要被处理、推进、解释，或继续观察。
```

Issue 不一定是软件开发里的 GitHub Issue，也不一定是“问题”。它是 Darktime 的基础事项单位。

Issue 不是 todo。它在 MVP 里可以被编辑、丢弃，或在用户已经看到持续投入可能性时转成 Project；它不提供 Done 动作。

### Project

Project 是值得持续投入的容器。

一个 Project 通常有更长生命周期，可能包含多个 Issue，也可能已经有外部输出痕迹。

当前 MVP 支持的 Project 来源：

```text
本地 git repo -> Project
Issue + link repo -> Project
```

Project 的重点不是“项目管理功能完整”，而是回答：

```text
我是否真的在这个方向上持续产出？
```

### Output Trace

Output Trace 是真实发生过的产出证据。

当前 MVP 的第一种 trace 是：

```text
local_git / commit
```

以后可以扩展：

```text
manual log
calendar event
document edit
GitHub issue / PR
```

### Attention View

Attention View 是 UI 聚合视图，不是一个新的业务实体。

它显示：

```text
active Issues + Projects + output timeline
```

换句话说，Attention View 是用户当前注意力模型的可视化入口。

## 当前流转

```text
Capture
  -> Matter(status: inbox)
  -> Inbox
  -> Clear
      -> Dropped
      -> Done
      -> Issue
          -> Edit / Drop
          -> Make Project / Link Repo
              -> Project
                  -> Output Trace
```

Attention View 读取的是：

```text
Issues(status: issue)
Projects(local repo projects)
Output Traces(project activity)
```

## 状态语言

### Issue

```text
open  -> 最近进入或更新过
stale -> 超过一段时间没有处理
```

### Project

```text
alive    -> 最近 2 天有 output
quiet    -> 最近 7 天有 output
fading   -> 最近 30 天有 output
inactive -> 超过 30 天没有 output
empty    -> 还没有 output trace
```

这些状态不是评价用户好坏，只是让实际注意力投入变得可见。

## 暂不实现

这些概念已经进入产品讨论，但不属于本次 PR：

- Today planning。
- Project detail。
- Issue 拆解。
- Issue 归属 Project。
- 手动 Output Log。
- AI observer / coach。
- 日历自动排程。

## 代码和存储边界

当前 Swift 层使用产品语言：

```text
MatterSnapshot
ProjectSnapshot
OutputTraceSnapshot.projectId
AttentionWorkspace
```

SQLite 里仍保留部分历史表名，例如 `roots` 和 `output_traces.root_id`。

这是本地数据兼容策略，不再代表产品语言。后续如果需要，可以单独做一次数据库 schema migration。
