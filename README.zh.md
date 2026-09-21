# TelnetKit

基于 SwiftNIO 与 vendored libtelnet 构建的 Swift 异步 Telnet 终端会话库。

TelnetKit 为每条连接提供一个 `async` 对象：建立连接后消费已解析的事件流并发送文本；socket 由 SwiftNIO 托管，RFC 1143 选项状态机不暴露在公开接口之外。

[English](README.md)

## 状态

本包已完成设计，尚未实现。需求来源是 [PRD.md](PRD.md)，设计契约是 [docs/architecture.md](docs/architecture.md) 与 [docs/public-api.md](docs/public-api.md)。当前请勿依赖本包。

## 环境要求

| 项 | 要求 |
|---|---|
| 平台 | macOS 15 或更高版本、iOS 18 或更高版本 |
| 工具链 | Swift 6.2 或更高版本；本包以 Swift 6 语言模式构建 |
| 依赖 | [swift-nio](https://github.com/apple/swift-nio) 2.103.0+、[swift-log](https://github.com/apple/swift-log) 1.6.0+ |

## 安装

在 `Package.swift` 中加入本包：

```swift
dependencies: [
    .package(url: "https://github.com/<owner>/TelnetKit.git", from: "0.1.0"),
],
targets: [
    .target(name: "YourTarget", dependencies: ["TelnetKit"]),
]
```

## 快速开始

先启动本地回显服务端，再启动演示客户端：

```sh
swift run TelnetEchoServer          # 监听 127.0.0.1:2323
swift run TelnetDemo --host 127.0.0.1 --port 2323
```

演示程序会建立连接、打印收到的每一个事件、发送一条命令并关闭连接。

## 使用库

```swift
import TelnetKit

let connection = try await TelnetConnection.connect(
    host: "127.0.0.1",
    port: 2323,
    options: .standardClient,
    configuration: .init(connectTimeout: .seconds(5))
)

Task {
    for await event in connection.events {
        switch event {
        case .data(let buffer):
            print(buffer.text ?? "", terminator: "")
        case .negotiation(let action, let option, let remote):
            print(remote ? "remote" : "local", action, option.displayName)
        case .terminalTypeRequested:
            try? await connection.replyTerminalType("xterm-256color")
        default:
            print(event)
        }
    }
}

try await connection.send(text: "hello telnet")
try await connection.sendWindowSize(columns: 120, rows: 40)
await connection.close()
```

`connect` 抛出具体的 `TelnetError`：解析失败为 `.invalidHost`，此外还有 `.connectionRefused`、`.connectTimeout`、`.cancelled`。关闭之后，所有发送与协商调用抛出 `.notConnected`，事件流随之结束。

## 能力范围

| 能力 | 说明 |
|---|---|
| 连接 | TCP 连接与地址解析、可配置超时、取消传播、幂等关闭 |
| 解析 | 剥离协商字节并还原转义的 `0xFF`；`.data` 只承载应用数据 |
| 选项 | `WILL`/`WONT`/`DO`/`DONT` 与 RFC 1143 Q-method 应答，由声明的选项集驱动 |
| 终端 | 终端类型、窗口尺寸、NEW-ENVIRON、MSSP、ZMP |
| 文本 | UTF-8 文本发送，支持 `CR LF`、`CR NUL`、`LF` 或不转换，并按 NVT 规则转义 |

## 已知限制

- 不做终端模拟。TelnetKit 只交付字节与协议事件；屏幕模型、光标处理与颜色渲染由调用方负责。
- 未内置 MCCP2 压缩：收到 COMPRESS2 请求时以 `wont` 拒绝。Apple SDK 自带 zlib，所以这是范围取舍而非依赖缺失；启用前必须先设计解压上限与压缩态契约。
- 首版未实现 TLS，配置中仅预留字段。
- 仅支持 macOS 与 iOS，没有 Linux、Windows、tvOS 或 watchOS 平台声明。
- iOS 上是前台会话：应用进入后台会被系统挂起，连接随之中断；回到前台后由应用自行重连。
- SSH、RLogin 与 BBS 文件传输协议不在范围内。

## 安全

Telnet 是明文协议：凭据与会话内容不经加密传输，链路中间人可以读取或篡改。请在可信网络中使用；在发送任何机密之前，请等待支持 TLS 的版本。iOS 上同样如此，而移动网络远比有线局域网不可信。

库把对端输入视为不可信：每条解析路径都有长度上限，异常序列产生警告或类型化错误而非崩溃，日志输出绝不包含业务数据或对端提供的值。

## 文档

- [PRD.md](PRD.md)：目标、需求、验收标准、测试清单、Demo 范围、里程碑、风险。
- [docs/architecture.md](docs/architecture.md)：分层、并发模型、事件流、扩展点。
- [docs/public-api.md](docs/public-api.md)：每个公开符号的调用方契约。
- [AGENTS.md](AGENTS.md)：贡献者常驻规则。
- 每份文档都是中英双语配对：本 README 与 [README.md](README.md) 配对，[PRD.md](PRD.md) 与 [PRD.en.md](PRD.en.md) 配对。

## 许可

TelnetKit 使用 MIT 许可。`Sources/CLibTelnet/` 中 vendored 的 libtelnet 源码属于公有领域，参见 [Sources/CLibTelnet/UPSTREAM.md](Sources/CLibTelnet/UPSTREAM.md) 与 `NOTICE`。
