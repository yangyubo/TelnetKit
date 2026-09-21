# TelnetKit 架构

[English](architecture.md) | 中文

修改 `Sources/` 下任何内容之前先读本文。本文是设计契约：本包尚未实现，除特别标注外下文每一条陈述都是**设计中**，状态由[设计状态规则](../AGENTS.md#design-status)承载而非写在本文里。需求与验收标准见 [PRD.md](../PRD.md)；调用方可见的签名见 [public-api.md](public-api.md)。

## 组成

TelnetKit 把协议解析与连接管理分离，因此测试可以分别驱动两者而无需另一个。

```text
TelnetConnection (actor, Public)            caller-facing session
  AsyncStream<TelnetEvent>                  event delivery, including path events
        |
TelnetProtocolCore (internal)               owns telnet_t, maps events
  option table, option status ledger        Swift-side state libtelnet does not export
        |
TelnetChannelHandler (internal)             ChannelDuplexHandler
  ByteBuffer in / IOData out                copies callback buffers, queues outbound bytes
        |
NIOTSConnectionBootstrap + NIOTSEventLoopGroup
  waits for a route, reports path changes   Network.framework owns the connection
        |
Network.framework                            path, proxy, VPN, power
        |
CLibTelnet (C target)                       vendored libtelnet 0.23, parsing only
```

一条连接恰好拥有一个 `TelnetProtocolCore`、一个 handler、一个 channel 与一个 `NIOTSEventLoop`。连接之间不共享状态，因此两个会话无法看到彼此的字节。

## 平台与传输层决策

**设计中。** 库从同一份源码为 macOS 15、iOS 18、watchOS 11、tvOS 18 与 visionOS 2 交付，且经 NIOTS 使用 Network.framework 是唯一传输层。非 Apple 平台不做承诺，也不为它们保留抽象或条件编译。

决策记录：

| 决策 | 选择 | 理由 |
|---|---|---|
| 传输层 | `NIOTSEventLoopGroup` 上的 `NIOTSConnectionBootstrap` | Network.framework 是 Apple 官方支持的传输层，连接管理、代理与 VPN 接入、路径监测与能耗行为都由它提供，无需逐项自己实现 |
| 不保留 POSIX 路径 | 不依赖 `NIOPosix` | 第二种传输层会让需要在五个平台上证明的不变量（背压、取消、路径上报）翻倍，却不给调用方增加任何被要求的能力 |
| 不做 TLS | 不支持 Telnet over TLS/SSL：既不做 `telnets`/992，也不做 START-TLS，也不实现 TELNET ENCRYPT 与 AUTHENTICATION 选项 | 该标准已废弃、提供它的设备极少，Apple 与 Homebrew 的 telnet 都不实现，上游 libtelnet 两个选项都未实现；保密应交给 VPN 或跳板机，而不是本库 |
| 可执行产物 | 仅 macOS | `TelnetEchoServer` 与 CLI Demo 需要进程与回环监听，watchOS、tvOS、visionOS 不提供这些语义 |

测试归属按同样口径拆分：协议层与公开接口套件在五个平台都跑；会绑定回环监听的集成套件只在 macOS 与 iOS 模拟器上跑。

## 并发模型

**设计中。** 协议状态机是单线程的，设计以所有权而非加锁来保证这一点。

| 规则 | 理由 |
|---|---|
| `telnet_t` 在拥有该 channel 的 EventLoop 上创建、使用与释放 | libtelnet 没有内部同步；加锁会让两个线程在同时触发回调的解析器内部串行化 |
| `TelnetProtocolCore` 不暴露任何可以在其 EventLoop 之外调用的方法 | 无前置条件的接口会招来只在负载下才暴露的跨线程调用 |
| `TelnetConnection` 是 `actor`，公开方法为 `async` | 调用方获得 `Sendable` 访问而无需了解 EventLoop；actor 把工作跳转到拥有它的 EventLoop |
| 事件投递使用有界 `AsyncStream` | 背压由调用方掌控；被丢弃的事件会被报告而非静默丢失 |
| 事件回调内拷贝后立即返回 | `telnet_event_t` 的载荷指针在回调返回时失效 |
| 回调期间收集的出站字节在回调返回后再 flush | 在回调里调用 `telnet_send*` 会重入解析中的解析器 |

每条连接的事件顺序是：解析入站字节、按线序发出事件、flush 排队的出站字节、完成写 promise。观察 `events` 的调用方在每条连接上看到相同顺序，且 `.data` 事件绝不会越过使其成立的协商事件。

`NIOTSEventLoop` 底层是串行 `DispatchQueue`，因此「所有 `telnet_*` 调用都在同一线程」这一约束与 NIO 的 POSIX EventLoop 同样成立；差别在于调度走 Dispatch QoS 而非 `pthreads` + `kqueue`。

## 事件流

入站：Network.framework 通过 NIOTS channel 交付一个 `ByteBuffer`，`TelnetChannelHandler.channelRead` 收到它；handler 把字节交给 `TelnetProtocolCore.feed`，后者调用 `telnet_recv`；libtelnet 每产生一个协议事件就调用一次 C 事件回调；回调拷贝载荷字节并向队列追加一个 Swift `TelnetEvent`；`telnet_recv` 返回后，handler 把排队的事件 yield 给 `AsyncStream` continuation。

出站：诸如 `send(text:)` 的公开调用进入 actor 并跳转到 EventLoop；handler 经 `telnet_send` 或 `telnet_send_text` 编码；libtelnet 以 `TELNET_EV_SEND` 报告编码后的字节，回调把它们追加到出站队列；handler 把该队列写为 `IOData` 并完成 promise；写完成时公开调用返回，写失败时抛出 `TelnetError.transportFailed`。NIOTS 的 outbound 类型是 `IOData`（inbound 是 `ByteBuffer`），handler 因此是 `ChannelDuplexHandler` 且 `OutboundOut = IOData`。

路径事件走另一条独立通道：SwiftNIO 的 `NIOTSNetworkEvents`（`PathChanged`、`BetterPathAvailable`、`BetterPathUnavailable`、`ViabilityUpdate`、`WaitingForConnectivity`）由 `TelnetNetworkEventMapping` 读取并映射为 `TelnetEvent` 的路径 case。这类事件**不触达协议状态机**：它们不调用 `telnet_recv`，也不改变选项账本。

协商是一个三步交换，三步都可观测：

1. 连接期协商按 `TelnetOptions` 发送初始的 `WILL`/`DO` 集合。
2. 每收到一个 `WILL`/`WONT`/`DO`/`DONT` 都产生一条 `.negotiation` 事件并更新 Swift 侧选项账本。
3. libtelnet 按 RFC 1143 Q-method 规则应答，应答以出站字节的形式出现。

第 3 步属于 libtelnet；第 1、2 步属于我们。选项账本存在的原因是 libtelnet 0.23 不导出任何协商状态查询，因此 `optionStatus(_:)` 由 core 已经看到的事件推导得出。

## C 接缝

**已验证。** 当 `include/module.modulemap` 声明 `module CLibTelnet { header "libtelnet.h" export * }` 时，`Sources/CLibTelnet/libtelnet.c` 与 `include/libtelnet.h` 作为 SwiftPM C target 编译无警告。Swift 直接导入这些函数。

接缝刻意收窄。`TelnetProtocolCore` 是本包中唯一导入 `CLibTelnet` 的文件；其他文件都在 Swift 类型中工作。libtelnet 有三项能力是宏，因此对 Swift 不可见，由 core 补齐：`telnet_finish_sb` 用 `telnet_iac(handle, TELNET_SE)`，`telnet_finish_newenviron` 与 `telnet_finish_zmp` 用同一个调用。

来源、复制与上游升级流程由 `Sources/CLibTelnet/UPSTREAM.md` 与[引入 skill](../.agents/skills/telnetkit-import-c-library/SKILL.md) 负责。

## 选项与命令建模

**设计中。** 线码到 Swift 值的转换只发生在一个映射文件里：`Sources/TelnetKit/Public/TelnetOption.swift` 与 `TelnetCommand.swift`，别处不转换。

`TelnetOption` 是包裹 `UInt8` 并带静态常量的 `RawRepresentable` struct，而不是 enum：Telnet 分配了 250 多个选项码，libtelnet 接受其中任意一个，若用 enum 就需要一个无界的关联值 case，并且会破坏 `CaseIterable` 遍历。没有常量的码仍可表示，`displayName` 把它渲染成 `option(<code>)`。

`TelnetCommand` 是封闭 enum，因为 RFC 854 及其后续把命令集固定在 20 个值上，而无法识别的命令字节属于协议违规，而不是新命令。

`TelnetNegotiation` 用 Swift 拼写（`will`、`wont`、`do`、`dont`）为四个协商动词命名，因此没有任何宏常量进入公开接口。数值映射与它们同文件，且只保留 core 使用的单向转换。

## 事件模型

**设计中。** `TelnetEvent` 是封闭 enum，每个 libtelnet 事件对应一个 case，另有三个由 core 派生的结构化 case：`localEchoChanged`、`terminalType(_:)`、`environment(_:_:)`，以及来自 `NIOTSNetworkEvents` 的路径 case。只需要字节与文本的调用方匹配两个 case；需要协议细节的调用方匹配全部。

字节载荷以 `NIOCore.ByteBuffer` 传递，因为它就是 NIOTS 入站已经产出的类型，投递时无需额外拷贝。便捷访问器提供字节与 UTF-8 文本，因此调用方读取输出时不必了解 NIO。

C 用 `event.type` 做的 union 判别在 core 中收敛为一个 `switch`。由于 libtelnet 的 union 会把 `type` 清零并把首字段复用为别名，core 读取别名后的字段，且绝不读取当前事件类型未选择的成员。有两个事件 `TELNET_EV_WARNING` 与 `TELNET_EV_ERROR` 携带 file、function 与 line，它们被映射为 `TelnetWarning` 与 `TelnetProtocolError`，其中的 C 字符串被拷贝成 Swift 字符串。

## 错误模型

**设计中。** 失败是值，绝不用崩溃表达。`TelnetError` 覆盖连接建立、传输、协议与配置四类失败；每个 libtelnet `telnet_error_t` 分支恰好映射到一个 `TelnetError` 分支，且映射是穷尽的，没有 `default` 分支。

可恢复与致命严格分开。`.warning` 事件之后连接仍可用；`.protocolError` 会关闭连接、结束事件流，并使后续调用抛出 `.notConnected`。把致命情形映射成警告会让调用方卡在无法推进的解析器里，把警告映射成致命则会因一段异常序列丢掉整个会话。

Network.framework 的错误集合（`NWError`）在 `TelnetNetworkEventMapping` 中映射为 `TelnetTransportFailure.Kind`，因此公开接口不出现 `NWError` 或 `nw_*` 类型。

## 资源上限

**设计中。** 每个受对端控制的值都有上限，且上限的所有者在 `TelnetConfiguration` 中。

| 约束对象 | 默认值 | 所有者 | 失败表现 |
|---|---|---|---|
| 未产生数据事件的入站字节 | 64 KiB | `inboundBufferLimit` | `.bufferOverflow`，连接关闭 |
| 子协商载荷 | 8 KiB | `subnegotiationLimit` | `.subnegotiationTooLarge` |
| 单次 `inflate` 的输出字节（v0.2；首版不链接 zlib） | 16 MiB | `maxInflatedBytes` | `.bufferOverflow`，连接关闭 |
| 等待消费的排队事件 | 1024 | `eventBufferPolicy` | 取决于策略：`.warning` 带丢弃计数，或结束事件流 |
| 连接握手 | 10 s | `connectTimeout` | `.connectTimeout` |
| 无路由时的等待 | 开启 | `waitForConnectivity` | 不失败：挂起并发出 `.waitingForConnectivity` |
| 空闲连接 | 无 | `idleTimeout` | 连接关闭 |

## 扩展点

**设计中。** 新能力挂在五个位置之一，选择哪一个就决定了它的测试放在哪里。

| 目标 | 位置 | 后果 |
|---|---|---|
| 支持另一个 Telnet 选项 | 在 `TelnetOption.swift` 加常量并在 core 里处理该 case；不新增公开类型 | 公开接口不变 |
| 增加结构化事件 | 增加 `TelnetEvent` case、core 中的 `switch` 分支，以及协议套件中的一个测试 | 公开接口变宽；public-api.md 同变更更新 |
| 改变连接行为，例如等待路由或链路迁移 | `TelnetConnectionBootstrap` 上的 NIOTS 选项（`NIOTSChannelOptions.waitForActivity`、`multipathServiceType`） | 公开接口按需变宽；连接测试覆盖该路径 |
| 增加便捷操作，例如上报窗口尺寸 | 在 `TelnetConnection` 上加一个组合既有 core 调用的方法 | core 不变；public-api.md 与其测试一起更新 |
| 改变输出文本处理 | `TelnetWireCoding` | 由协议套件中的行尾与转义测试覆盖 |

任何扩展点都不改变解析层：`telnet_recv` 与事件回调始终是从字节到事件的唯一路径。

## 测试架构

测试与分层一一对应，每一层都可以在没有上一层的情况下被驱动。

| 套件 | 被测层 | 夹具 |
|---|---|---|
| `Tests/TelnetKitTests/Protocol/` | 经 `@testable import` 测试 `TelnetProtocolCore` | 输入字节数组，输出 `[TelnetEvent]`；不使用 socket |
| `Tests/TelnetKitTests/PublicAPI/` | 仅经 `import TelnetKit` 测试 `TelnetConnection` | 回环地址上的 `TelnetEchoServer` |
| `Tests/TelnetKitTests/Integration/` | 连接行为：超时、取消、关闭、并发、路径事件 | `NIOTSListenerBootstrap` 起的本地夹具，以及注入的 `NIOTSNetworkEvents` |

协议套件是 RFC 行为的正确性关卡；公开 API 套件是契约关卡，它覆盖 [public-api.md](public-api.md#symbol-checklist) 中列出的每一个公开符号。集成套件负责时序：依赖超时的测试使用较短的配置上限与宽松的断言上限，绝不使用固定 sleep。

平台归属：协议层与公开接口套件在五个平台都跑；绑定回环监听的集成套件只在 macOS 与 iOS 模拟器上跑，因为 watchOS、tvOS 与 visionOS 没有进程与回环服务端语义。演示可执行文件是手工路径与夹具，不能替代任何套件。
