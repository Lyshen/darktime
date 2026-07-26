# Issue 与注意力观察者预期

这份文档记录 Darktime 下一阶段的产品判断。它不引入新的功能实现，只用来约束后续 PR：为什么先抓 Issue、为什么它要服务每天打开使用，以及长期想长成什么样的观察者。

## 文档分层

- `product-language-cn.md` / `product-language-en.md`：总词典，定义 Matter、Issue、Project、Action、Today 等基础概念。
- 本文档：记录 Issue 工作流和注意力观察者的产品预期。
- 后续具体功能文档：只描述单个功能，例如 GitHub Issue 同步、Today Start、Evening Review、Attention Review。

## 当前定位

Darktime 不是传统项目管理软件的缩小版，也不是泛泛聊天的心理陪伴工具。

它更像 AI coding 时代的个人项目管理层：跟着用户观察最近真实投入了哪些 Project、哪些 Issue 值得继续、哪些 Action 已经发生，并帮助用户决定接下来该亲自投入、交给 agent，还是及时停止。

## 为什么先抓 Issue

Issue 是意图变成行动之前的最小承载物。

- Project 没有 Issue，只是一个 repo 或文件夹列表。
- Today 没有 Issue，只是一个空的每日页面。
- Action 没有 Issue，只是 commit 历史。
- Agent 没有 Issue，就缺少可以接住的任务包。

Darktime 的 Issue 不等同于 GitHub Issue。它先是本地的工作意图，可以来自用户手写、GitHub 同步、PR 同步、Capture 提炼、计划建议，未来也可以发布到 GitHub，让其他 agent 或工具接住。

## 每天使用闭环

目标不是让用户维护一套复杂系统，而是让用户每天更容易开始和收住。

早上打开 Today：

- 看到今天建议关注的少量 Issue。
- 可以从已有 Project Issue 中选择。
- 可以快速写一句新 Issue，并加入 Today。
- 未来可以通过一段自然语言或语音，让 Darktime 提取 Issue。

开始工作：

- 从 Today Issue 进入对应 Project。
- 打开 repo、恢复上下文，未来可以生成给 Codex / Claude Code 的启动提示。
- 真实 commit、PR 或其他推进记录成为 Action。

下班 Review：

- 看今天选择了哪些 Issue。
- 看实际哪些 Project / Issue 有 Action。
- 看哪些只是计划但没有推进。
- 得到一段简短日报或观察摘要。

周期 Review：

- 在 Attention 里回看最近一段时间的 Project 行动分布。
- 先看哪些 Project 有 Action，哪些 Project 有 Issue 但没有 Action。
- Review 是解释已有行为数据的动作，不是新的数据库实体。

## GitHub Issue 关系

GitHub Issue 是 Darktime Issue 的一个外部表达，不是唯一来源。

近期应该验证的链路：

- 从 GitHub repo 拉取 open issues 到本地 Project，默认只同步 assigned to me，必要时可改为 created by me 或 all open issues。
- 在 Darktime 创建本地 Issue 后，可以快速发布到 GitHub repo，并默认 assign 给自己。
- GitHub Issue 的闭环动作是 close on GitHub，不是本地 hide 或 drop。
- v0 只保存 GitHub issue number / url / state，不做复杂双向编辑同步。
- 发布默认需要用户明确触发或开启 Project 级别开关，避免把私人想法误推到公开仓库。

这个链路的价值不是“规范化用 GitHub Issue”，而是让 Darktime Issue 能成为人和 agent 都能理解的工作接口。

## 高级感预期

静态展示投入情况还不够。Darktime 真正打动用户的地方应该是：它能基于真实行动痕迹指出投入结构哪里不对。

它应该逐步做到：

- 发现用户同时管了太多 Project。
- 发现某些 Project issue 越来越多，但 Action 很少。
- 发现某些方向定义不清，继续做只会消耗注意力。
- 发现某些 Project 应该冻结、砍掉或极简化。
- 发现某些事情适合交给 agent，而不是用户亲自做。
- 发现日常行为模型的问题，例如无法坚持锻炼不是意志力差，而是触发场景没有建立。

这不是空泛安慰，而是基于 Project、Issue、Action、Today、Capture 的长期观察。

## 决策语言

未来 Review 或 Agent 建议可以围绕这些动作展开：

- `Keep by me`：需要用户亲自投入判断，例如方向、审美、关键取舍。
- `Delegate`：可以交给 agent 的明确任务，例如实现、测试、整理、文档。
- `Clarify`：定义不清，先不要继续做大。
- `Freeze`：暂时移出当前注意力，不再每天占据心智。
- `Stop`：方向或收益明显不对，及时止血。

这些动作比简单的完成 / 未完成更贴近 AI coding 之后的个人管理问题。

## 不做什么

- 不把 Issue 做成沉重的 Jira / Linear。
- 不把 Chat 做成主入口。
- 不要求用户先成为规范项目经理。
- 不把所有 Capture 自动推到 GitHub。
- 不用 gamification 代替真实清晰感。

## 下一阶段验证重点

优先验证 Issue 是否能成为每日使用的燃料：

1. GitHub Issue 能否进入本地 Project。
2. 本地 Issue 能否快速发布到 GitHub。
3. Today 能否让用户快速选择或新增少量 Issue。
4. Commit / PR 等真实推进能否成为 Action。
5. 晚上 Review 能否让用户感到更清楚、更收得住。

如果这个闭环能让用户连续几天主动打开 Darktime，它才有资格继续长出更智能的观察者能力。
