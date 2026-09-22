# TelnetKitDemoApp

[English](README.md) | 中文

面向 macOS 15+ 与 iOS 18+ 的 SwiftUI 应用，驱动 `TelnetKit`：[PRD.md](../../PRD.zh.md#9-demo-项目需求) 要求的可交互 Demo，也是调用方如何使用每个公开接口的参考。

它以独立 Xcode 工程的形式放在 `Examples/`，因此这里没有任何包内 target，`swift test` 也永远不会构建 SwiftUI。应用以调用方的方式使用库：一个本地 Swift Package 引用加 `import TelnetKit`。

## 运行

先初始化一次 libtelnet 子模块，再从仓库根目录启动本地回显服务端：

```sh
git submodule update --init --recursive
swift run telnetkit-echo-server
```

打开 `TelnetKitDemoApp.xcodeproj`，选择 scheme 后运行：

| Scheme | 运行目标 |
|---|---|
| `TelnetKitDemoApp` | 本机 Mac，macOS 15 或更高 |
| `TelnetKitDemoApp-iOS` | iOS 18 或更高的模拟器 |

两个 target 共用 `TelnetKitDemoApp/` 下的源码。iOS 模拟器能访问 Mac 的回环地址，因此默认的 `127.0.0.1:2323` 无需修改即可使用。

## 可以试什么

1. 点 **Connect**。状态栏显示 `remoteAddress` 与 `localAddress`，选项表随协商到达由 `optionStatus(_:)` 逐步填充。真实 telnetd 在 TERMINAL-TYPE 被应答前不会打印登录提示，因此 Demo 会立即应答 `TERMINAL-TYPE SEND` 与 `NEW-ENVIRON SEND`；**Protocol** 标签页为两者各提供一个开关，把它交回手动按钮。两个 **Preset** 按钮分别用 `TelnetOptions.standardClient` 与 `TelnetOptions.serverRequesting(_:)` 填充选项勾选。
2. 输入一行后回车。Demo 会补上结束该行的换行符，因为 `send(text:lineEnding:)` 只转换字符串里已有的换行、不会自行添加；选择器可选 CR LF、CR NUL 或 LF，**send(text:)** 按钮走 `send(text:)` 的默认值，十六进制字段驱动 `send(_:)` 与 `sendRaw(_:)`。
3. 缩放窗口。对端应答 `do windowSize` 之后，每次尺寸变化都通过 `sendWindowSize(columns:rows:)` 上报，回显服务端会打印 `NAWS <columns>x<rows>`。
4. 打开 **Protocol** 标签页，操作 `negotiate(_:option:)`、`requestOption(_:)`、`subnegotiate(option:payload:)`、`send(command:)`、`replyTerminalType(_:)`、`sendEnvironment(_:scope:)` 以及手动 `sendWindowSize(columns:rows:)`；填入未建模的选项码即可经 `TelnetOption(rawValue:)` 覆盖选择器。
5. 按任一 **Error injection** 按钮：每个按钮都会走到真实的 `TelnetError` 路径；**Public values** 会渲染全部错误、警告与错误码 case，包括这个构建无法触发的三个。
6. 打开 **Inject a swift-log Logger**、切换日志级别，在 **Log** 标签页观察库产生的日志记录。

`swift run telnetkit-echo-server --inject all` 会让对端在协商之后发送畸形交换，**Events** 标签页因此也能显示 `.warning` 与 `.protocolError` 行。

## 工程文件

`TelnetKitDemoApp.xcodeproj` 由 `project.yml` 生成并已提交，因此打开或构建应用都不需要额外工具。要改变结构，请修改 `project.yml` 并在本目录重新生成：

```sh
xcodegen generate
```

## 验收

**已在本机验证。** 两个 scheme 都在 Xcode 27 工具链下零警告构建：`-scheme TelnetKitDemoApp -destination 'generic/platform=macOS'`，以及 `-scheme TelnetKitDemoApp-iOS -destination 'platform=iOS Simulator,name=iPhone 17'`。对真实 telnetd 的会话走到了密码提示并进入 shell，缩放窗口使 `telnetkit-echo-server` 打印 `NAWS 105x32`，`TelnetKitDemoApp-iOS` scheme 在模拟器里跑通回环服务端，库在 iOS 18 模拟器上 115 个测试全绿。

## 文档

- [PRD.zh.md](../../PRD.zh.md#9-demo-项目需求) 负责 Demo 必须覆盖的接口与验收标准。
- [docs/public-api.zh.md](../../docs/public-api.zh.md) 是本应用所演练的调用方契约。
- [README.zh.md](../../README.zh.md) 覆盖库的安装与使用。
