# Darktime 最小产品逻辑

当前正式产品语言见 [domain-language-v0.md](domain-language-v0.md)。

## 核心判断

Darktime 不是日历、待办、笔记或聊天机器人。

它先解决一个更小的问题：

```text
哪些事情正在占用我的注意力？
哪些只是噪音？
哪些值得成为 Issue？
哪些已经值得作为 Project 持续投入？
我实际有没有在这些 Project 上产生 Output？
```

## 最小闭环

```text
Capture -> Inbox -> Clear -> Issue / Done / Dropped
Issue -> Project
Project -> Output Trace
Attention View -> 看见当前注意力与真实投入
```

## 为什么不是 Rootbox

早期的 `Rootbox / Seed` 是讨论隐喻。

现在把它拆开：

- `Issue` 是被承认值得注意力处理的事项。
- `Project` 是值得持续投入的容器。
- `Attention View` 是显示 Issue + Project + Output Trace 的 UI 聚合视图。

所以不存在一个叫 Rootbox 的业务实体。

## 第一版要验证

- 用户是否愿意快速 Capture。
- Inbox 是否真的降低脑内负担。
- Clear 是否能把 Matter 分成 Done / Dropped / Issue。
- Issue 是否能自然长成 Project。
- Project timeline 是否能让用户看见真实注意力投入。

如果这条链路成立，再继续做 Today、Project Detail、AI observer。
