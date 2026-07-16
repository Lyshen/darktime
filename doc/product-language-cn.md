# Darktime 产品语言

Darktime 是一个本地优先的注意力操作台。它不先做日历、待办、笔记或聊天机器人，而是帮助用户看见：哪些事情正在占用注意力，哪些值得处理，哪些已经展开成持续投入，以及自己到底在哪些事情上真实行动过。

## 核心概念

| 概念 | 定义 | 边界 |
| --- | --- | --- |
| Matter | 被捕捉到的一条原始注意力。 | 还不是任务、计划、项目、习惯或日历事件。 |
| Capture | 把 Matter 放进 Darktime 的动作。 | 不分类、不判断、不规划，只负责卸下认知压力。 |
| Inbox | Matter 的临时缓冲区。 | 让用户延后决定，不是鼓励无限收集。 |
| Clear | 处理 Inbox 的动作。 | 目标是减轻注意力负担，不是制造待办列表。 |
| Issue | 值得处理的事项。 | 不是 todo；可以独立存在，也可以进入 Project。 |
| Project | 已经展开持续投入的事情容器。 | 不是 Issue 的简单升级版；Project 会产生 Issue 和 Action。 |
| Action | Issue 或 Project 上真实发生过的一次推进。 | 不是计划、提醒或待办；它必须已经发生。 |
| Attention View | Issues、Projects、Actions 的 UI 聚合视图。 | 不是新的业务实体。 |

## 流转关系

```text
Capture
  -> Matter
  -> Inbox
  -> Clear
      -> Dropped
      -> Done
      -> Issue
          -> Action
          -> Make Project / Link Repo
              -> Project
                  -> Issue
                  -> Action
```

当前 MVP 已支持手动 Project Issue。GitHub Issue / PR 同步会写入同一套 Issue 模型。

## 关键解释

- `Drop`：不值得继续占用注意力，短期可恢复。
- `Done`：已经结束，不需要继续追踪。
- `Issue`：值得处理，但还不一定形成持续投入。
- `Project`：已经真的展开投入的事情，例如一个本地 git repo。
- `Action`：真实发生的一次推进；当前第一种 Action 是 `local_git / commit`。
- `source`：Action 的实现字段，例如 `manual`、`local_git`、`calendar`，不是一级产品概念。

## 状态语言

Issue：

```text
open  -> 最近进入或更新过
stale -> 超过一段时间没有处理
```

Project：

```text
alive    -> 最近 2 天有 Action
quiet    -> 最近 7 天有 Action
fading   -> 最近 30 天有 Action
inactive -> 超过 30 天没有 Action
empty    -> 还没有 Action
```

这些状态不是评价用户好坏，只是让实际注意力投入变得可见。

## 当前 MVP

已进入：

- Capture / Inbox / Clear。
- Issue 列表、编辑、丢弃、转 Project。
- Project 下的手动 Issue。
- 本地 git repo Project。
- commit 自动导入为 Action。
- Attention Items 和 Timeline。

暂不进入：

- Project detail。
- 手动 Action。
- Today planning。
- AI observer / coach。
- 日历自动排程。

## 实现边界

Swift 层尽量使用当前产品语言：`MatterSnapshot`、`ProjectSnapshot`、`ActionSnapshot`、`AttentionWorkspace`。

SQLite 里仍保留部分历史表名，例如 `roots` 和 `output_traces`。这是本地数据兼容策略，不代表当前产品语言。
