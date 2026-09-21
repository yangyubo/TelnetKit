# 变更日志

[English](CHANGELOG.md) | 中文

TelnetKit 的所有重要变更都记录在此。格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，版本号遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)。

## [Unreleased]

### 新增

- `TelnetKit` 库：经 NIOTS 走 Network.framework 的异步 `TelnetConnection`，协议状态机由内部 `CLibTelnet` target 背后的 pin 住 libtelnet 子模块承担。
- 公开契约：`TelnetEvent`、`TelnetOptions`、`TelnetError`、`TelnetConfiguration`，以及选项、命令、协商与行尾值类型。
- RFC 1143 协商，以及 TTYPE、NAWS、NEW-ENVIRON、MSSP、ZMP，各自对应结构化事件。
- 可选的 swift-log 日志：生命周期 info、协商 debug、协议帧 trace、错误 error；绝不记录载荷字节。
- 连接超时、取消、空闲关闭、`waitForConnectivity`，以及有界的入站与子协商缓冲。
- 测试套件：白盒协议套件、基于回环夹具的黑盒公开接口套件，以及并发、超时、取消、空闲关闭与路径映射的集成覆盖。

### 已知限制

- `TelnetDemo` 与 `TelnetEchoServer` 可执行文件及 SwiftUI 示例尚未交付。
- MCCP2、Telnet over TLS、代理模式与非 Apple 平台不在范围内；见 [README.zh.md](README.zh.md#已知限制)。
