# TelnetKit 公开接口

[English](public-api.md) | 中文

本文是 `TelnetKit` 库产物的调用方契约，定义每一个公开类型、方法与 case，并且是契约的存档依据：当代码与本文冲突时，其中一方是缺陷，变更必须同时修正两者。库、两个可执行文件与 [`Examples/TelnetKitDemoApp/`](../Examples/TelnetKitDemoApp/README.zh.md) 下的 SwiftUI Demo 应用均已实现；需求与验收标准见 [PRD.zh.md](../PRD.zh.md)，内部设计见 [architecture.md](architecture.md)。

## 公开接口规则

这些规则是机械可查的。违反其中一条的变更会被评审拒绝，[公开接口 skill](../.agents/skills/telnetkit-public-api-slice/SKILL.md) 会在报告切片完成前逐条检查。

| 规则 | 检查方式 |
|---|---|
| `public` 中不出现任何 C 类型、函数或宏 | 在公开源码中 grep `telnet_`、`TELNET_`、`OpaquePointer`、`Unsafe` |
| 每个公开声明都有 `///` 注释说明调用方契约 | 阅读生成的 interface |
| 每个可能失败的公开方法是 `async throws(TelnetError)` | 阅读生成的 interface |
| 每个公开类型都是 `Sendable` | 以完整并发检查构建 |
| 公开类型位于 `Sources/TelnetKit/Public/` | 比对文件路径与声明位置 |
| 每个公开符号都有自动化测试 | 用[符号清单](#符号清单)比对公开 API 套件 |

## 术语表

这些术语在本仓库中只有一个含义。不要为其中任何一个另造同义词。

- **选项（option）**——由 8 位码标识的 Telnet 能力，例如 `echo`（码 1）。选项是被协商的，不是被配置的。
- **协商（negotiation）**——四个交换动词 `will`、`wont`、`do`、`dont` 之一，针对某个选项、某个方向发送。
- **子协商（subnegotiation）**——在 `IAC SB` 与 `IAC SE` 之间交换的、与选项相关的载荷，例如 `windowSize` 的窗口尺寸。
- **命令（command）**——不属于选项的单个 Telnet 控制字节，例如 `noOperation` 或 `areYouThere`。
- **事件（event）**——投递给调用方的一个已解析事实：数据、协商、子协商、命令，或派生的便捷 case。
- **连接（connection）**——一个 TCP 会话，含一个远端端点与一个协议状态机。
- **会话（session）**——调用方对一条连接的使用。库拥有的是连接，不是会话。
- **NVT**——RFC 854 定义的网络虚拟终端约定：换行用 CR LF，字面量 `0xFF` 字节用两个 `0xFF` 承载。

## 生命周期契约

**已验证。** `TelnetConnection.connect(host:port:options:configuration:)` 返回一条已连接、可开始协商的会话。连接在关闭前一直可用，而关闭只可能是四种情形之一：调用方调用 `close()`、远端关闭、发生致命协议错误，或配置的超时到期。

事件流按线序投递事件，并在任意关闭路径上恰好结束一次。从不消费事件流的调用方同样能观测到关闭：出站调用抛出 `.notConnected`，`isConnected` 变为 false。事件流是单消费者的；第二个消费者什么都收不到，而不是收到一份拷贝。

`close()` 是幂等的。关闭后调用任何发送或协商方法都抛出 `.notConnected`；再次调用 `close()` 成功且不做任何事。

取消会传播。在 `connect` 或某个发送方法内部取消任务时，若该被取消的操作拥有连接，则关闭连接，并由被取消的调用抛出 `.cancelled`。被取消的 `connect` 不留下打开的 socket，也不留下任何残留。

## 连接

```swift
public actor TelnetConnection {
    public static func connect(
        host: String,
        port: Int = 23,
        options: TelnetOptions = .standardClient,
        configuration: TelnetConfiguration = .init()
    ) async throws(TelnetError) -> TelnetConnection

    public nonisolated var events: AsyncStream<TelnetEvent> { get }

    public var isConnected: Bool { get }
    public var remoteAddress: String? { get }
    public var localAddress: String? { get }
    public func optionStatus(_ option: TelnetOption) -> TelnetOptionStatus
}
```

| 成员 | 契约 |
|---|---|
| `connect(host:port:options:configuration:)` | 解析 `host`，在 `configuration.connectTimeout` 内建立 TCP 连接，按 `options` 发送初始协商，并返回连接。解析失败抛 `.invalidHost`，对端拒绝抛 `.connectionRefused`，达到配置上限抛 `.connectTimeout`，`options` 非法抛 `.invalidConfiguration`，调用任务被取消抛 `.cancelled`。 |
| `events` | 单消费者事件流。标记为 `nonisolated`，因此调用方可以在任意 actor 调用之前或之后开始消费。关闭时结束。按线序产出。 |
| `isConnected` | 从 `connect` 成功起为 true，直到关闭路径开始。之后为 false，包括致命错误之后。 |
| `remoteAddress` | 对端的 `host:port`，连接完成前为 nil。 |
| `localAddress` | 本地 socket 的 `host:port`，否则为 nil。 |
| `optionStatus(_:)` | 某个选项在账本中的条目：两个方向各自是否已启用、是否有未决请求。由观测到的协商推导，绝不来自 C 状态。从未被提及的选项返回全 false。 |

## 发送

```swift
extension TelnetConnection {
    public func send(_ bytes: [UInt8]) async throws(TelnetError)
    public func send(text: String) async throws(TelnetError)
    public func send(text: String, lineEnding: TelnetLineEnding) async throws(TelnetError)
    public func sendRaw(_ bytes: [UInt8]) async throws(TelnetError)
    public func send(command: TelnetCommand) async throws(TelnetError)
}
```

| 成员 | 契约 |
|---|---|
| `send(_:)` | 发送应用字节。按 NVT 把每个 `0xFF` 翻倍为 `0xFF 0xFF`。不改变 CR 与 LF。 |
| `send(text:)` | 把 `text` 编码为 UTF-8，按 `configuration.newlinePolicy` 与 `TelnetLineEnding.crlf` 改写它已有的换行，然后转义。它绝不补行尾：`send(text: "hi")` 写出 `68 69`，`send(text: "hi\n")` 写出 `68 69 0D 0A`。 |
| `send(text:lineEnding:)` | 同上，但用显式指定的行尾替代配置的默认值。想结束一行的调用方要把换行写进 `text`。 |
| `sendRaw(_:)` | 发送字节，不做转义也不做行尾转换。用于承载已经编码好的 Telnet 字节流；若字节中含裸 `IAC`，可能破坏会话。 |
| `send(command:)` | 以 `IAC <command>` 发送一个 Telnet 命令。 |

每个发送方法在字节写入 socket 后完成；写失败抛 `.transportFailed`，连接已关闭抛 `.notConnected`，任务被取消抛 `.cancelled`。并发调用按 actor 接收顺序串行，且任何调用都不会把半个帧与另一个调用交错。

## 协商与选项

```swift
extension TelnetConnection {
    @discardableResult
    public func negotiate(_ action: TelnetNegotiation, option: TelnetOption) async throws(TelnetError) -> Bool
    public func requestOption(_ option: TelnetOption) async throws(TelnetError)
    public func subnegotiate(option: TelnetOption, payload: [UInt8]) async throws(TelnetError)
    public func replyTerminalType(_ type: String) async throws(TelnetError)
    public func sendEnvironment(_ values: [EnvironmentVariable], scope: EnvironmentScope) async throws(TelnetError)
    public func sendWindowSize(columns: Int, rows: Int) async throws(TelnetError)
}
```

| 成员 | 契约 |
|---|---|
| `negotiate(_:option:)` | 为某个选项发送一个协商动词。当 libtelnet 因 RFC 1143 状态判定其冗余而抑制发送时返回 false，字节已入队时返回 true。返回时更新账本。 |
| `requestOption(_:)` | 本端提供该选项时发 `will`，希望从对端获得时发 `do`，依据 `options` 选择。选项不在两个列表中的任何一个时抛 `.invalidConfiguration`，因为对端会应答一个调用方并未声明的请求。 |
| `subnegotiate(option:payload:)` | 发送 `IAC SB <option> <payload> IAC SE`，并对载荷中的 `0xFF` 转义。载荷超过配置上限时抛 `.subnegotiationTooLarge`。 |
| `replyTerminalType(_:)` | 响应未决的终端类型请求，发送 `IAC SB TERMINAL-TYPE IS <type> IAC SE`。仅在 `.terminalTypeRequested` 事件之后有效，否则抛 `.invalidConfiguration`。 |
| `sendEnvironment(_:scope:)` | 用给定 scope 发送 NEW-ENVIRON 列表，并转义名称与值中的转义字节。编码后的列表超出配置上限时抛 `.subnegotiationTooLarge`。 |
| `sendWindowSize(columns:rows:)` | 以四个大端字节发送 NAWS，并转义 RFC 1073 要求的 `0xFF` 字节。尺寸超出 0...65535 时以 `.invalidConfiguration` 拒绝。 |

## 选项配置

```swift
public struct TelnetOptions: Sendable {
    public struct LocalOption: Sendable, Hashable {
        public var option: TelnetOption
        public var enabledByDefault: Bool
        public init(_ option: TelnetOption, enabledByDefault: Bool = true)
    }
    public struct RemoteOption: Sendable, Hashable {
        public var option: TelnetOption
        public var requestOnConnect: Bool
        public init(_ option: TelnetOption, requestOnConnect: Bool = true)
    }

    public var local: [LocalOption]
    public var remote: [RemoteOption]
    public var isValid: Bool

    public init(local: [LocalOption] = [], remote: [RemoteOption] = [])

    public static var standardClient: TelnetOptions { get }
    public static func serverRequesting(_ options: [TelnetOption]) -> TelnetOptions
}
```

`local` 列出本端以 `will` 提供的选项，`remote` 列出本端以 `do` 向对端索取的选项。连接期协商按声明顺序为每个条目发送一个动词，遵循 `enabledByDefault` 与 `requestOnConnect`。同时出现在两个列表中的选项会双向协商，这既合法也常见：多数对端都会双向协商 `echo` 与 `suppressGoAhead`。

`isValid` 对协议拒绝的组合为 false，目前是 `local` 中同时出现 `binary` 与 `lineMode`。`connect` 会抛出 `.invalidConfiguration`，而不是协商一个非法组合。

`standardClient` 是本端提供 `binary`、`suppressGoAhead`、`terminalType`、`windowSize`，并向对端索取 `suppressGoAhead`、`echo`。`serverRequesting(_:)` 构造服务端调用方需要的那组对端选项。

## 事件

```swift
public enum TelnetEvent: Sendable {
    case data(ByteBuffer)
    case negotiation(TelnetNegotiation, option: TelnetOption, remote: Bool)
    case subnegotiation(option: TelnetOption, payload: [UInt8])
    case command(TelnetCommand)
    case terminalTypeRequested
    case terminalType(String)
    case environmentRequested(EnvironmentScope)
    case environment(EnvironmentScope, [EnvironmentVariable])
    case localEchoChanged(enabled: Bool)
    case mssp([String: String])
    case zmp([String])
    case compressionEnabled(Bool)
    case pathChanged(viable: Bool, expensive: Bool, constrained: Bool)
    case betterPathAvailable
    case betterPathUnavailable
    case viabilityChanged(isViable: Bool)
    case waitingForConnectivity(error: String?, description: String)
    case warning(TelnetWarning)
    case protocolError(TelnetProtocolError)
}

extension TelnetEvent {
    public var bytes: [UInt8]?
    public var text: String?
}
```

| Case | 产生时机 |
|---|---|
| `.data` | 对端发来应用字节，此时协商字节与 NVT 转义已被剥离 |
| `.negotiation(_:option:remote:)` | 收到 `will`、`wont`、`do` 或 `dont`；对端发出时 `remote` 为 true |
| `.subnegotiation(option:payload:)` | 收到一个 `IAC SB ... IAC SE` 块；`payload` 不含选项码，且已还原转义的 `0xFF` |
| `.command(_:)` | 收到控制命令，例如 `areYouThere` 或 `goAhead` |
| `.terminalTypeRequested` | 对端发送 `TERMINAL-TYPE SEND`；用 `replyTerminalType(_:)` 应答，或忽略以不发送任何内容 |
| `.terminalType(_:)` | 对端发送带名称的 `TERMINAL-TYPE IS` |
| `.environmentRequested(_:)` | 对端以 `SEND` 索取环境变量；用 `sendEnvironment(_:scope:)` 应答 |
| `.environment(_:_:)` | 对端发送 ENVIRON 或 NEW-ENVIRON 列表 |
| `.localEchoChanged(enabled:)` | 对端的 `will echo` 或 `wont echo` 改变了本端是否应回显用户输入 |
| `.mssp(_:)` | 对端发送 MSSP 状态列表，已解码为字典 |
| `.zmp(_:)` | 对端发送 ZMP 命令；首元素是命令名 |
| `.compressionEnabled(_:)` | COMPRESS 或 COMPRESS2 协商改变了压缩状态。首版不链接 zlib，也绝不接受压缩流，因此该 case 不会出现：所有 COMPRESS2 协商都以 `wont` 应答，字节流保持未压缩 |
| `.pathChanged(viable:expensive:constrained:)` | Network.framework 报告了该连接的新路径；三个标志取自 `NWPath`，并以 Swift 值拷贝出来 |
| `.betterPathAvailable` | 系统发现了更优路径，通常是蜂窝承载时出现了 Wi‑Fi |
| `.betterPathUnavailable` | 该更优路径消失 |
| `.waitingForConnectivity(error:description:)` | 因 `waitForConnectivity` 开启，连接尝试被挂起等待可用路由。连接未关闭，`connect` 也尚未返回 |
| `.viabilityChanged(isViable:)` | 路径变为可用或不可用。不可用不会关闭连接，只表示在恢复前无法收发 |
| `.warning(_:)` | 可恢复的协议问题：截断的序列、意外的字节、截断的子协商，或事件被丢弃 |
| `.protocolError(_:)` | 致命的状态机失败；该事件之后连接关闭 |

`.bytes` 返回 `.data` 事件的载荷，其余 case 返回 nil。`.text` 把该载荷按 UTF-8 解码并替换非法序列，除 `.data` 外所有 case 返回 nil。

## 配套值类型

```swift
public struct TelnetOption: RawRepresentable, Sendable, Hashable, CaseIterable {
    public let rawValue: UInt8
    public init(rawValue: UInt8)
    public var displayName: String { get }
    public static var allCases: [TelnetOption] { get }

    public static let binary: TelnetOption
    public static let echo: TelnetOption
    public static let suppressGoAhead: TelnetOption
    public static let status: TelnetOption
    public static let timingMark: TelnetOption
    public static let terminalType: TelnetOption
    public static let endOfRecord: TelnetOption
    public static let windowSize: TelnetOption
    public static let terminalSpeed: TelnetOption
    public static let remoteFlowControl: TelnetOption
    public static let lineMode: TelnetOption
    public static let environment: TelnetOption
    public static let newEnvironment: TelnetOption
    public static let mssp: TelnetOption
    public static let compress: TelnetOption
    public static let compress2: TelnetOption
    public static let zmp: TelnetOption
    public static let extendedOptionsList: TelnetOption
}

public struct TelnetOptionStatus: Sendable, Hashable {
    public var locallyEnabled: Bool
    public var remotelyEnabled: Bool
    public var localRequested: Bool
    public var remoteRequested: Bool
}

public enum TelnetNegotiation: Sendable, Hashable { case will, wont, `do`, dont }

public enum TelnetCommand: UInt8, Sendable, Hashable {
    case endOfFile = 236, suspend = 237, abort = 238, endOfRecord = 239
    case subnegotiationEnd = 240, noOperation = 241, dataMark = 242, brk = 243
    case interruptProcess = 244, abortOutput = 245, areYouThere = 246
    case eraseCharacter = 247, eraseLine = 248, goAhead = 249, subnegotiation = 250
    case will = 251, wont = 252, do_ = 253, dont = 254
}

public enum TelnetLineEnding: Sendable, Hashable { case crlf, crNul, lf, none }
public enum EnvironmentScope: Sendable, Hashable { case variable, userVariable }
public struct EnvironmentVariable: Sendable, Hashable {
    public var name: String
    public var value: String?
    public var scope: EnvironmentScope
}
```

选项数值码即 RFC 分配值：`binary` 0、`echo` 1、`suppressGoAhead` 3、`status` 5、`timingMark` 6、`terminalType` 24、`endOfRecord` 25、`windowSize` 31、`terminalSpeed` 32、`remoteFlowControl` 33、`lineMode` 34、`environment` 36、`newEnvironment` 39、`mssp` 70、`compress` 85、`compress2` 86、`zmp` 93、`extendedOptionsList` 255。其他任何码都可通过 `init(rawValue:)` 构造，并渲染为 `option(<code>)`。

`TelnetCommand` 中存在 `will`、`wont`、`do`、`dont`，是因为命令字节与协商动词共用同一种线编码；调用方匹配协商用的是 `.negotiation(_:option:remote:)` 事件，`.command(.will)` 永不出现。

## 配置

```swift
public struct TelnetConfiguration: Sendable {
    public var connectTimeout: Duration
    public var idleTimeout: Duration?
    public var inboundBufferLimit: Int
    public var subnegotiationLimit: Int
    public var eventBufferPolicy: TelnetEventBufferPolicy
    public var newlinePolicy: TelnetNewlinePolicy
    public var waitForConnectivity: Bool
    public var logger: Logger?

    public init(
        connectTimeout: Duration = .seconds(10),
        idleTimeout: Duration? = nil,
        inboundBufferLimit: Int = 65_536,
        subnegotiationLimit: Int = 8_192,
        eventBufferPolicy: TelnetEventBufferPolicy = .bounded(1024),
        newlinePolicy: TelnetNewlinePolicy = .nvt,
        waitForConnectivity: Bool = true,
        logger: Logger? = nil
    )
}

public enum TelnetEventBufferPolicy: Sendable {
    case bounded(Int)
    case unbounded
    case dropOldest(Int)
}

public enum TelnetNewlinePolicy: Sendable { case nvt, raw }
```

| 成员 | 契约 |
|---|---|
| `connectTimeout` | 地址解析加 TCP 连接的总上限。 |
| `idleTimeout` | 为 nil 时禁用空闲关闭。设置后，在该时长内既无入站也无出站流量的连接会关闭并结束事件流。 |
| `inboundBufferLimit` | 入站缓冲字节上限；超过时发出致命 `.protocolError` 并关闭。 |
| `subnegotiationLimit` | 子协商载荷上限；超过时抛出 `.subnegotiationTooLarge`。 |
| `eventBufferPolicy` | `.bounded` 在写满时发出 `.warning` 并结束事件流，`.unbounded` 永不丢弃，`.dropOldest` 丢弃最旧的排队事件并发出 `.warning(.eventBufferOverflowDropped(count:))`。 |
| `newlinePolicy` | `.nvt` 对文本发送与收到的数据做 CR、LF 转换；`.raw` 原样透传。`binary` 协商启用期间会覆盖两者为 raw。 |
| `logger` | 可选的 `swift-log` logger。为 nil 时不记录任何日志。任何级别都不记录载荷内容。 |
| `waitForConnectivity` | 为 true 时，无可用路由的连接尝试被挂起而不是立即失败，路由出现后继续建立（FR-PATH-01）。挂起期间 `connect` 尚未返回，`.waitingForConnectivity` 报告该状态。 |

这些默认值就是调用方什么都不传时得到的结果，且每个默认值都有配置测试断言。`inboundBufferLimit` 与 `subnegotiationLimit` 是字节数，`eventBufferPolicy` 计数的是事件，`waitForConnectivity` 是布尔开关。

## 错误

```swift
public enum TelnetError: Error, Sendable, Equatable {
    case invalidHost(String)
    case connectionRefused(host: String, port: Int)
    case connectTimeout(Duration)
    case notConnected
    case alreadyClosed
    case transportFailed(TelnetTransportFailure)
    case protocolViolation(TelnetProtocolError)
    case bufferOverflow(limit: Int)
    case subnegotiationTooLarge(option: TelnetOption, limit: Int)
    case unsupportedFeature(String)
    case invalidConfiguration(String)
    case cancelled
}

public struct TelnetTransportFailure: Error, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case dns, posix(code: Int32), tls, channelClosed, writeTimeout, other }
    public var kind: Kind
    public var message: String
    public var isRetryable: Bool

    public init(kind: Kind, message: String, isRetryable: Bool)
}

public enum TelnetWarning: Error, Sendable, Equatable {
    case truncatedSequence([UInt8])
    case unexpectedByte(UInt8, context: String)
    case subnegotiationTruncated(option: TelnetOption)
    case eventBufferOverflowDropped(count: Int)
    case compressionUnavailable
}

public enum TelnetProtocolError: Error, Sendable, Equatable {
    case stateMachineFailure(code: TelnetErrorCode, message: String)
    case invalidSubnegotiation(option: TelnetOption)
    case outOfMemory
}

public enum TelnetErrorCode: Sendable, Equatable { case badValue, outOfMemory, overflow, protocol, compression }
```

每个 libtelnet `telnet_error_t` 值一对一映射：`TELNET_EBADVAL` 对应 `.badValue`，`TELNET_ENOMEM` 对应 `.outOfMemory`，`TELNET_EOVERFLOW` 对应 `.overflow`，`TELNET_EPROTOCOL` 对应 `.protocol`，`TELNET_ECOMPRESS` 对应 `.compression`。`TELNET_EOK` 表示成功，不产生错误。

`.notConnected` 表示在关闭之后发起了调用；`.alreadyClosed` 表示 `close()` 与一个已经开始的关闭过程发生竞争，而调用方要求区分该情形。`.dns`、表示连接被拒或超时的 `.posix` 码，以及底层 `NWError` 属于暂时性（如 `.waitingForConnectivity`）时的 `.other`，`isRetryable` 为 true；`.tls`、`.channelClosed`、`.writeTimeout` 为 false，因为在条件不变时重试只会重复同一失败。

## 日志

**已验证。** 当 `configuration.logger` 非 nil 时，库以 `info` 记录连接生命周期，以 `debug` 记录协商与状态变更，以 `trace` 记录协议帧。任何级别都不记录载荷字节、对端发来的选项值或环境变量值。默认静默：未配置 logger 的连接不产生任何日志记录。

## 符号清单

下列每个符号在引入它的切片完成之前，都需要 `Tests/TelnetKitTests/PublicAPI/` 中的一个自动化测试。

| 类型 | 符号 |
|---|---|
| `TelnetConnection` | `connect`、`events`、`isConnected`、`remoteAddress`、`localAddress`、`optionStatus`、`send(_:)`、`send(text:)`、`send(text:lineEnding:)`、`sendRaw(_:)`、`send(command:)`、`negotiate(_:option:)`、`requestOption(_:)`、`subnegotiate(option:payload:)`、`replyTerminalType(_:)`、`sendEnvironment(_:scope:)`、`sendWindowSize(columns:rows:)`、`close()` |
| `TelnetEvent` | 全部 19 个 case，加上 `bytes` 与 `text`；未链接 zlib 的构建中 `compressionEnabled` 没有触发点 |
| `TelnetOptions` | `init(local:remote:)`、`LocalOption`、`RemoteOption`、`local`、`remote`、`isValid`、`standardClient`、`serverRequesting(_:)` |
| `TelnetOption` | `init(rawValue:)`、`rawValue`、`displayName`、`allCases`，以及全部 18 个常量 |
| `TelnetOptionStatus` | 全部四个属性 |
| `TelnetNegotiation` | 全部四个 case |
| `TelnetCommand` | 全部 19 个 case |
| `TelnetLineEnding` | 全部四个 case |
| `EnvironmentScope`、`EnvironmentVariable` | 全部 case 与属性 |
| `TelnetConfiguration` | `init` 的每个默认值，以及全部八个属性 |
| `TelnetEventBufferPolicy`、`TelnetNewlinePolicy` | 全部 case |
| `TelnetError` | 全部 12 个 case；`.alreadyClosed`、`.bufferOverflow` 与 `.unsupportedFeature` 仅作为值触达，因为 `close()` 幂等、入站超限以 `.protocolError` 呈现、且 v0.2 的 zlib 路径不在范围内 |
| `TelnetTransportFailure`、`TelnetTransportFailure.Kind` | `init(kind:message:isRetryable:)`、全部属性与 case |
| `TelnetWarning` | 全部五个 case；`compressionUnavailable` 为 v0.2 的 zlib 支持预留，在未链接 zlib 的构建中没有触发点 |
| `TelnetProtocolError`、`TelnetErrorCode` | 全部 case |
