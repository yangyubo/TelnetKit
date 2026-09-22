# AGENTS.md

[English](AGENTS.md) | 中文

TelnetKit 是一个仅面向 Apple 平台的 Swift Package，为 Swift 调用方提供异步 Telnet 终端会话：连接由 Network.framework（经 NIOTS）托管，协议状态机由 pin 住的 libtelnet 子模块（经 C target）承担，两者都不暴露在公开接口中。

修改 `Sources/` 之前先读 [docs/architecture.md](docs/architecture.md)。公开接口契约是 [docs/public-api.md](docs/public-api.md)；改动任何公开符号时必须在同一次变更里同步更新它。撰写、评审或精简文字时遵循 [.agents/skills/telnetkit-prose-standard/SKILL.md](.agents/skills/telnetkit-prose-standard/SKILL.md)；文档归属与校验遵循 [.agents/skills/telnetkit-doc/SKILL.md](.agents/skills/telnetkit-doc/SKILL.md)。

## 设计状态

`TelnetKit` 库已经存在并通过测试，三个演示程序均已编写；[PRD.md](PRD.md) 是需求来源，上述文档是它的设计契约。本仓库中的陈述分为三类，正文必须标明属于哪一类：

- **已验证。** 在本机实际复现过：115 个测试在 macOS 与 iOS 上全绿；`-strict-concurrency=complete` 无警告；`swift test --sanitize=address` 通过；`TelnetKit` 在五个平台下限均可构建；`leaks --atExit` 在 300 条连接与 10 万事件后报告 0 泄露字节；协议层行覆盖率 92.3%；DocC 构建 target 诊断数为 0；`TelnetKitDemoApp` 可构建 macOS 与 iOS 两个目标并对真实 telnetd 跑通会话。
- **上游事实。** 读自被 pin 的依赖而非我们的代码：例如 libtelnet 0.23 不导出任何选项状态查询函数。
- **设计中。** 尚未编写的代码的计划行为。设计中的陈述必须写成需求，绝不能写成对既有行为的描述；行为落地后删除该标记。

绝不可把设计中的行为说成已验证。当设计与 PRD 冲突时，两者一起修正，或明确报告冲突。

## 仓库结构

```
Package.swift                  swift-tools-version 6.2，五个 Apple 平台
PRD.md                         需求来源：目标、需求、验收标准
libtelnet/                     git 子模块：上游 libtelnet，已 pin，从不写入
Sources/CLibTelnet/            我们的 module map、两个指向子模块的符号链接，以及来源记录
Sources/TelnetKit/Public/      公开类型；调用方唯一可见的符号
Sources/TelnetKit/Protocol/    对 telnet_t 的内部 Swift 封装
Sources/TelnetKit/Transport/   内部 NIOTS handler、bootstrap 与路径事件映射
Sources/TelnetKitClient/       telnetkit-client 命令行客户端
Sources/TelnetEchoServer/      仅 macOS 的本地回显服务端（供 Demo 使用）
Tests/CLibTelnetTests/         内置 libtelnet 套件；测试套件位于 Tests/TelnetKitTests/
Examples/TelnetKitDemoApp/     SwiftUI 演示应用（macOS 与 iOS 目标）
docs/                          架构、公开接口契约、测试方案、文档标准
.agents/skills/                可复用工作流
```

包产物：库 `TelnetKit` 与可执行文件 `telnetkit-client`、`telnetkit-echo-server`。`CLibTelnet` 始终是内部 target，绝不成为 product。

## 命令

```sh
git submodule update --init --recursive   # 克隆后执行一次
swift build                       # 构建全部 target 的 debug 版本
swift test                        # 115 个测试，离线且在 60s 内
swift test --filter TelnetProtocolCoreTests   # 迭代时只跑一个套件
swift run telnetkit-client 127.0.0.1 2323     # 交互式命令行客户端
swift run telnetkit-echo-server               # 本地回显服务端
swift build -Xswiftc -strict-concurrency=complete   # 并发检查
swift build --configuration release               # release 构建与体积检查
swift package describe            # target 与 product 清单
swift package diagnose-api-breaking-changes api-baseline-0.1.0 --products TelnetKit   # 接口基线比对
xcodebuild -list                  # 唯一的 scheme 是 TelnetKit（由 SwiftPM 命名）
swift build --target CLibTelnet --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" --triple arm64-apple-ios18.0-simulator   # 下限检查
```

`swift test` 是本地证据。只报告实际运行过的命令及其观测结果；没有执行的检查不能声称已通过。覆盖以公开符号为准，而不是只看源码行：一个没有测试的公开符号属于失败的工作，不是部分完成的工作。

绝不运行 `git push`，也不询问是否推送；提交在人工发布之前始终留在本地。

## 不可协商的约束

- **仅 Apple 平台。** 部署下限是 macOS 15、iOS 18、watchOS 11、tvOS 18、visionOS 2。Linux、Windows、Android 不在范围内：不得为它们添加平台声明、抽象层或条件分支。不得引入比这些下限更新的 API。
- **Network.framework 是唯一传输层。** 连接跑在 `NIOTSConnectionBootstrap` 与 `NIOTSEventLoopGroup` 上。本包（含测试）中不出现 `NIOPosix`、裸 `socket()`、`select`/`kqueue`。新的传输需求用 Network.framework 的选项解决，而不是引入第二套协议栈。
- **Swift 6 语言模式。** 所有 target 以 Swift 6 模式编译，`StrictConcurrency` 完整检查且零警告。`@unchecked Sendable` 需要注释说明使其安全的那个不变量，并配一个覆盖它的并发测试。
- **libtelnet 子模块只读。** `libtelnet/` 是 `Sources/CLibTelnet/UPSTREAM.md` 所记录 commit 处的上游，其代码、许可证与历史保持完整。绝不向它提交，也绝不在其中写入文件。我们的 module map 与两个指向上游源码的符号链接都位于 `Sources/CLibTelnet/` 之下，因此升级版本只需切换子模块 commit；需要改变行为时改我们的 Swift 代码。
- **`telnet_t` 单线程所有。** 一条连接的所有 `telnet_*` 调用都发生在创建它的 `EventLoop` 上。不得用加锁来弥补跨线程调用；改调用点。
- **回调数据不外逃。** 从 `telnet_event_t` 可达的 buffer、字符串与参数数组只在回调期间有效。在回调内拷贝；绝不保存指针。
- **回调内不得重入。** 在事件回调里调用 `telnet_send*` 会重入正在解析中的状态机。把出站字节入队，等回调返回后再 flush。
- **公开接口不泄漏 C。** `TelnetKit` 不导出任何 `telnet_*` 函数、`TELNET_*` 宏常量、`telnet_t`、`telnet_event_t`、`telnet_telopt_t`，也不导出 `OpaquePointer`。选项码与命令码以 Swift 值出现，数值含义只保存在一个映射文件中。
- **选项状态由我们自己维护。** libtelnet 0.23 不导出选项状态查询。`optionStatus(_:)` 由 Swift 依据观测到的 `WILL`/`WONT`/`DO`/`DONT` 事件推导；绝不读取或猜测 C 内部状态。
- **错误是类型化值。** 每个可能失败的公开调用都是 `throws(TelnetError)`。禁止 `fatalError`、`preconditionFailure`、对来自对端的值强制解包，以及 `try!`。每个 `telnet_error_t` 分支都要显式映射；任何 `default:` 分支都不允许吞掉一个分支。
- **对端输入不可信。** 每条解析路径都有长度上限并被模糊测试覆盖。异常序列产生警告或类型化错误，绝不产生崩溃或无界分配。
- **失败或异常的测试绝不能被消音。** 测试失败、报错、不稳定或看起来不对时，不得删除、跳过、放宽断言或阈值，也不得改成能通过的样子。必须停下来询问人的决定，然后据此修产品，或仅在决定指示下修改测试，并在同一次变更里说明原因。即使失败来自一次有意的行为变更，也同样适用。

## 约定

- Swift 文件内的布局顺序：公开类型、注入到存储属性的依赖、actor 或 class 主体，然后是 `// MARK:` 划分的生命周期、协议处理与销毁。公开入口放在文件顶部。
- `Sources/TelnetKit/Public/` 只放调用方可见的接口；`internal` 实现放在 `Protocol/` 与 `Transport/`。类型在两个目录之间移动即属于公开 API 变更。
- 公开符号带 `///` 文档注释，说明调用方契约：结果、抛出或结束条件、所有权、顺序与取消语义。内部注释只解释不显然的不变量；不叙述控制流。
- 一个术语一个含义。`option`、`negotiation`、`subnegotiation`、`event`、`connection`、`session` 采用 [docs/glossary](docs/public-api.md#glossary) 中的定义；不得为已定义的术语另造同义词。
- 当引入依赖能删掉自有代码与测试时，优先用依赖；把这一选择记进 PRD，而不是写进注释。
- 测试描述公开 API 的可观测行为。协议层测试直接驱动解析层；连接测试用真实 socket 打测试 target 内的回环夹具。废弃行为要与其测试一起变更，并遵循同一条决定规则。
- 文件以恰好一个结尾换行结束。`FIXME` 用于缺陷，`TODO` 用于计划工作，`XXX` 用于必须回看的高风险点；不要留没有理由的裸标记。

## 文档

一个事实一个家，层级见 [docs/AGENTS.md](docs/AGENTS.md)。`AGENTS.md` 承载常驻规则与链接；[docs/architecture.md](docs/architecture.md) 映射组成；[docs/public-api.md](docs/public-api.md) 定义公开契约；[PRD.zh.md](PRD.zh.md) 拥有需求、验收标准与里程碑范围；包 README 服务使用方；[.agents/skills/](.agents/skills/) 存放可复用工作流。生成或复制而来的内容除其归属方外不得手工修改。

**每份文档都是双语的。** 英文文件与其 `.zh.md` 对照版在同一次变更中一起提交，标题、列表、表格、代码、链接目标与物理行数保持一致。英文文件前三行内要给出对照版文件名，中文文件反向链接回英文版。未翻译的文档属于失败的文档，不是待办项。完整机制、翻译规则与校验命令见 [docs/AGENTS.md](docs/AGENTS.md#bilingual-pairs)。

代码变更时同步更新受影响的 README 与公开接口契约。正文用现在时陈述当前行为；历史留在 commit 与 PRD 变更记录里，不写进正文。

## 修改本文件

每条规则自成一体：说明做什么、点出机制、链接其归属文档。只为「有能力的 Swift 工程师很可能违反」的约束新增规则。保持清晰的前提下尽量精简。当新规则所需篇幅超过 [docs/AGENTS.md](docs/AGENTS.md) 中的上限时，把细节移到其归属文档，这里只留一行规则。
