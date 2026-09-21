---
name: telnetkit-public-api-slice
description: 端到端实现 TelnetKit 公开接口的一个切片，从 docs/public-api.md 中的契约贯穿协议代码、NIO 传输、公开 actor 与证明它的测试。用于在 TelnetKit 中新增或修改公开类型、方法、事件 case、错误 case 或配置字段，或当某个公开符号缺少通过的测试时。
---

# 实现一个公开接口切片

[English](SKILL.md) | 中文

## 概要

一个切片是一项调用方可见的能力，且是完整的：契约、协议处理、传输装配、公开接口、测试与文档。本工作流让各层保持顺序，使切片绝不会以未测试的公开接口落地。它是指导，不是机械填写的检查表；只有当切片确实不触及某一层时才跳过该步骤，并在报告中说明。

## 目录

- [输入与排除项](#输入与排除项)
- [工作流](#工作流)
- [分层顺序与各层归属](#分层顺序与各层归属)
- [规则](#规则)
- [校验](#校验)
- [Dev Note](#dev-note)

## 输入与排除项

必须有一个明确的切片：一个具名公开符号或一个具名事件 case。若请求是「实现这个库」，先从[里程碑](../../../PRD.md#10-里程碑与交付计划)提出一个切片清单，等选定其中一个再动手。

把 `Sources/CLibTelnet/` 排除在编辑之外，包括文档编辑；它的归属方是 [telnetkit-import-c-library](../telnetkit-import-c-library/SKILL.md)。

## 工作流

1. 读 [docs/public-api.md](../../../docs/public-api.md) 获取该符号的契约，读 [docs/architecture.md](../../../docs/architecture.md) 确认拥有它的层，读[根 AGENTS.md](../../../AGENTS.md) 获取常驻约束。读驱动该切片的 PRD 需求与验收标准。
2. 先写契约测试，放在能观测到该行为的最低层。协议行为是在 `Tests/TelnetKitTests/Protocol/` 中「输入字节、输出事件」的测试；需要 socket 的能力是 `Tests/TelnetKitTests/PublicAPI/` 中的测试。
3. 在协议层实现：新增或扩展 `TelnetProtocolCore` 与线缆编码辅助。喂入 C 回调、拷贝其 buffer，并产出 Swift 事件或值。运行协议测试。
4. 装配传输层：只按切片所需扩展 `TelnetChannelHandler` 或 bootstrap，并遵守 EventLoop 所有权规则。重跑协议测试与相关传输测试。
5. 暴露公开接口：把声明加到 `Sources/TelnetKit/Public/`，并带 `///` 注释说明结果、抛出条件、所有权、顺序与取消。
6. 只经 `import TelnetKit` 编写公开 API 测试，打 `TelnetEchoServer`；若是新符号，把它加入[符号清单](../../../docs/public-api.md#symbol-checklist)。
7. 若该切片在 Demo 范围内对调用方可见，按 [Demo 需求](../../../PRD.md#9-demo-项目需求) 更新 Demo。
8. 先跑窄范围检查，再跑完整套件；报告前完整重读 diff，检查是否有跨层违规。

## 分层顺序与各层归属

| 层 | 文件 | 拥有 | 不得包含 |
|---|---|---|---|
| 协议 | `Sources/TelnetKit/Protocol/TelnetProtocolCore.swift` | `telnet_t` 生命周期、选项表、回调、事件映射、选项账本 | NIO 类型、公开声明、async |
| 线缆编码 | `Sources/TelnetKit/Protocol/TelnetWireCoding.swift` | `0xFF` 转义、NVT 行尾、NAWS 与 NEW-ENVIRON 编码 | 协议状态、公开声明 |
| 传输 | `Sources/TelnetKit/Transport/TelnetChannelHandler.swift` | ByteBuffer 进出、出站队列 flush、缓冲上限、关闭传播 | 选项语义、公开声明 |
| 公开 | `Sources/TelnetKit/Public/*.swift` | Actor、事件、选项、错误、配置、文档注释 | `import CLibTelnet`、直接调用 NIO handler |

需要新 Swift 类型的切片先确定它属于哪一层：调用方能命名的类型是公开的；只有传输层使用的类型是内部的，并与它的使用者放在一起。

## 规则

- 公开符号只能与它的测试在同一次变更中落地。没有测试的公开接口不是完成的切片。
- 错误由检测到它的层产生，并以 `TelnetError` 传递。不要把错误翻译两次，也不要新增一个没有测试触达的 case。
- 一个切片只做一件事。需要无关重构的切片先把重构单独落地。
- 当切片修改既有签名时，在同一次变更中更新 [docs/public-api.md](../../../docs/public-api.md)、Demo 与受影响的测试；把 interface 快照当作检查清单。
- 依赖时间的行为使用配置上限加宽松的断言上限。绝不用固定 sleep 断言。
- 协议套件不使用 socket 运行。若某个协议测试需要一个服务端，该行为应归属传输层。

## 校验

让证据与切片匹配，并报告实际运行过的命令及其观测结果：

1. 协议或线缆编码切片跑 `swift test --filter TelnetKitTests.Protocol`。
2. 公开接口切片跑 `swift test --filter TelnetKitTests.PublicAPI`。
3. 报告切片完成之前跑 `swift test`。
4. 任何引入了闭包、continuation 或非 `Sendable` 捕获的切片，跑 `swift build -Xswiftc -strict-concurrency=complete`。
5. 切片修改既有公开签名时，跑 `swift package diagnose-api-breaking-changes baseline.json`。
6. 在 `Sources/TelnetKit/Public/` 中 grep `telnet_`、`TELNET_` 与 `OpaquePointer`，结果为空。
7. 重读 diff，检查公开文件里是否有属于内部层的行，以及内部文件里是否有泄漏 C 指针的行。

## Dev Note

None.
