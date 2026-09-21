---
name: telnetkit-doc
description: 创建、重构、评审或校验 TelnetKit 的 Markdown 文档，覆盖 AGENTS.md、架构、公开接口、PRD、README 与 skill 各层级，包括字数上限、链接可解析性与「设计中/已验证」的区分。用于新增或修订 TelnetKit 文档、文档质量评审、归属决策，或检查链接与字数上限是否仍然成立。
---

# TelnetKit 文档

[English](SKILL.md) | 中文

## 概要

TelnetKit 文档遵循一个事实一个家，并标明每个事实是设计中还是已验证。本工作流把文档放进它的层级、按该层级的规则写作并校验。句级判断与契约覆盖用 [telnetkit-prose-standard](../telnetkit-prose-standard/SKILL.md)；本 skill 负责归属、结构、字数与检查。

## 目录

- [输入与排除项](#输入与排除项)
- [工作流](#工作流)
- [层级与归属决策](#层级与归属决策)
- [文档结构](#文档结构)
- [规则](#规则)
- [校验](#校验)
- [Dev Note](#dev-note)

## 输入与排除项

必须有明确范围：一个文档路径、一个目录，或一次具名变更。若范围是「文档」，先列出已存在的文档并让用户选一个，而不是重写整个语料。

把 `Sources/CLibTelnet/libtelnet.c`、`Sources/CLibTelnet/include/libtelnet.h` 与 `Sources/CLibTelnet/UPSTREAM.md` 排除在文字编辑之外：源码是上游副本，而 `UPSTREAM.md` 记录的是事实而非文字。

## 工作流

1. 读[根 AGENTS.md](../../../AGENTS.md)、[docs/AGENTS.md](../../../docs/AGENTS.md) 与目标文档。读文档所声称内容对应的代码、测试或依赖。
2. 判定文档的职责：常驻规则、设计地图、调用方契约、需求、使用方契约，或工作流。[层级表](../../../docs/AGENTS.md#层级分类一个事实一个家) 规定该职责的归属位置。
3. 为新增的陈述判定「设计中」还是「已验证」。读自上游的陈述是上游事实；通过运行命令复现的陈述是已验证；其余都是设计中，并按[根 AGENTS.md](../../../AGENTS.md#design-status) 的要求标注。
4. 按下面的结构、用该层级自己的口吻起草：常驻规则是一至三行加一个链接；设计地图是有序地图而不是 API 目录；调用方契约要写出每个成员的结果与失败。
5. 把属于其他层级的事实移到其归属方，只留一个链接。重复的规则要删除，而不是换个说法。
6. 用[字数上限](../../../docs/AGENTS.md#字数上限)衡量文档，并按下沉—精简—上调的顺序处理。
7. 执行校验步骤，然后完整重读一次 diff 检查正确性，再重读一次检查篇幅。

## 层级与归属决策

| 决策 | 归属方 | 常见错误 |
|---|---|---|
| 「不要对来自对端的数据强制解包」 | 根 `AGENTS.md` | 把理由和示例写进常驻规则，而不是链接架构文档 |
| 「handler 在回调内拷贝」 | `docs/architecture.md` | 在 `AGENTS.md` 与 `public-api.md` 中重复它 |
| 「库支持 macOS 15 与 iOS 18」 | `docs/architecture.md`（平台支持一节） | 在 README 与平台下限规则里重复平台矩阵 |
| 「`send(text:)` 在关闭后抛 `.notConnected`」 | `docs/public-api.md` | 只留在 PRD 里，而调用方不会去那里看 |
| 「FR-CONN-03 要求连接超时可配置」 | `PRD.md` | 在架构文档里复述需求编号 |
| 「五条命令连上本地回显服务端」 | `README.md` | 把贡献者流程写进 README |
| 「如何 vendoring 或升级 libtelnet」 | `.agents/skills/` | 把流程写成 `architecture.md` 的一节 |

只有现有层级无法承担某职责时才新建文档。优先扩展已有文档，而不是新增文件。

## 文档结构

参考文档以一段说明其主题与范围的话开头，超过四节时加 `## Table of Contents`，然后按从定位到细节的顺序排列各节。`README.md` 是唯一的教程：开头写明库做什么与可运行的快速开始，设计与需求细节用链接外置。

skill 文档带 `name` 与 `description` 的 YAML frontmatter、`## Summary`、`## Table of Contents`、工作流、决策规则、`## Validation` 一节，以及结尾的 `## Dev Note`——除非确实存在未决问题，否则写 `None.`。工作流与规则要分开：步骤说明做什么，规则说明受什么约束。

## 规则

- 每段一个物理行，使 diff 显示改动的句子而不是被重排的整块。
- 链接事实的归属方而不是复述它。同一条规则出现第二次陈述，就是那份拷贝的缺陷。
- 字节级结论要在写证明它的测试的同一段里给出字节与对应的 Swift 值。
- 数字要有单位与所有者：`inboundBufferLimit` 中的 `65_536` 字节，`connectTimeout` 中的 `10 s`。
- 不要在标题上标注状态。状态在[设计状态规则](../../../AGENTS.md#design-status)与 PRD 里程碑表中。
- 代码围栏要带语言标记；`swift` 围栏必须是合法 Swift，`text` 围栏用于组成示意图。
- 每个相对链接都要解析到本仓库内的文件；上游文件用 URL 引用。
- 中文对照版在同一次变更中更新，保持相同的标题序列、表格与代码结构以及物理行数；[PRD.md](../../../PRD.md) 按反向规则配对 `PRD.en.md`。

## 校验

按适用范围执行，并逐条报告观测结果：

1. 链接可解析：对改动文件中的每个相对 Markdown 链接，`test -e "$(dirname <file>)/<target-path>"` 成功。指向目录或锚点的链接按失败报告，因为这里只检查文件。
2. 字数上限：`wc -w <file>` 在 [docs/AGENTS.md](../../../docs/AGENTS.md#字数上限) 的上限之内，`AGENTS.md`、`docs/AGENTS.md`、`docs/architecture.md`、`docs/public-api.md` 需保留 5% 余量。
3. 标题唯一：同一文件中没有两个标题产生相同锚点。
4. 陈述类别：改动文件中的每条现在时行为声明都属于已验证、上游事实或明确的设计中；三者之外的要报告。
5. 重复：把每条新规则的特征短语在整个仓库中 grep 一遍，确认它作为规则只出现一次，别处都是链接。
6. 双语配对：两侧都存在，逐行的结构行类型一致，且 `wc -l` 报出的两侧行数相同。
7. `Sources/CLibTelnet/` 内没有任何手工编辑。

## Dev Note

None.
