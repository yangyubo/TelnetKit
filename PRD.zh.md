# TelnetKit 产品需求文档（PRD）

[English](PRD.md) | 中文

| 项目 | 内容 |
| --- | --- |
| 产品名称 | TelnetKit |
| 版本 | v0.1（首版需求） |
| 文档状态 | 待评审 |
| 撰写日期 | 2026-09-21 |
| 目标仓库 | `TelnetKit`（Swift Package，目录 `/Users/yang/workspace/CodinnCode/CoreSSH/TelnetKit`） |
| 上游依赖 | [apple/swift-nio](https://github.com/apple/swift-nio)、[seanmiddleditch/libtelnet](https://github.com/seanmiddleditch/libtelnet) |
| 交付形态 | Swift Package（library product `TelnetKit` + 测试 + Demo 可执行产物）；支持 macOS 15+ 与 iOS 18+ |

---

## 1. 背景与目标

### 1.1 背景

Telnet 协议（RFC 854/855 及其大量选项扩展）仍是 BBS、网络设备、嵌入式设备、工业终端等场景的通用交互通道。Swift 生态目前缺少一个「现代、安全并发、开箱即用」的 Telnet 客户端库：

- `libtelnet` 是成熟的 C 实现，覆盖 RFC 854/855/1091/1143/1408/1572，支持 Q-method（RFC 1143）选项协商、ZMP、MCCP2、MSSP、NEW-ENVIRON，但它只做**协议状态机**，不管理 TCP，且是**回调式 API + 大量宏/常量/裸指针**，用起来非常"非 Swift"。
- 手写连接层（无论是直接用 Network.framework 还是裸 socket）同样要自己重写一遍 RFC 1143 状态机，工程量大且易错。

TelnetKit 的定位：**用 Swift 6 并发模型与 SwiftNIO 把 libtelnet 封装成一个类型安全、可测试、零 C 泄漏的异步 Telnet 终端能力库，同时覆盖 macOS 15+ 与 iOS 18+ 两个平台。**

### 1.2 产品目标

| 编号 | 目标 | 度量方式 |
| --- | --- | --- |
| G1 | 提供 Swift 原生异步 Telnet 接口 | 调用方全程使用 `async/await` 与 `AsyncSequence`，无需任何回调闭包 |
| G2 | 连接生命周期由库托管 | 连接、超时、优雅关闭、背压、取消传播、网络路径变化全部由 `TelnetConnection` 负责 |
| G3 | 完全隔离 C 实现细节 | 公开接口零 `OpaquePointer`、零 `UInt8` 命令码宏、零 `telnet_*` 符号 |
| G4 | 协议正确性与可验证性 | 协商、子协商、TTYPE/NEW-ENVIRON/NAWS 等公开行为均有测试用例覆盖 |
| G5 | 可交付的示例工程 | Demo 覆盖全部公开接口，可直接连真实 Telnet 服务并交互 |
| G6 | 以 Apple 平台最优方案为唯一技术路线 | 传输层用 NIOTS（Network.framework），不引入 POSIX/BSD socket 路径，不为其他平台保留分支 |

### 1.3 非目标（Out of Scope）

- ❌ 终端模拟器（VT100/xterm 屏幕模型、光标、行编辑、颜色渲染）——Demo 只做**最小可交互**演示，不做完整 TERM。
- ❌ SSH / RLogin / Mosh 协议。
- ❌ BBS 业务逻辑（ANSI 图、文件传输协议 ZMODEM 等）。
- ❌ MCCP2 压缩（`HAVE_ZLIB`）。Apple 三个 SDK 都自带 zlib（我已验证 macOS/iOS/iPadOS 均可 `-lz` 链接），所以关闭不是依赖问题，而是取舍：目标用户（开发者、运维人员、极客）不依赖它；而一旦接受压缩流，inflate 会引入解压炸弹、压缩态事件流与失败模式三项未设计的契约。首版对其一律 `wont`，v0.2 按 §6.3 的启用条件评估。
- ❌ 代理模式（`TELNET_FLAG_PROXY`）。它把 libtelnet 变成一根透明管道：关闭 RFC 1143 应答，把每个 `WILL`/`WONT`/`DO`/`DONT` 上报给应用自行转发，唯一的额外能力是自动识别 COMPRESS2。这是中间人（客户端 ↔ 代理 ↔ 服务端）与调试工具的形态：转发方不能对选项站队。本库恰恰相反——它是端点，价值就在于代理模式会关掉的那三样：RFC 1143 自动应答、选项表与 `optionStatus(_:)`；而 COMPRESS2 这项额外能力受 zlib 控制，首版未开启。需要透明转发时，请直接以代理模式使用上游 libtelnet；v0.2 若要重新评估，须先满足 §6.3 为压缩设定的同类前置条件。
- ❌ Telnet 服务端框架（`NIOTSListenerBootstrap` 侧产品化）；Demo 交付的回显服务端不计入产品接口。
- ❌ 文本层面编码转换以外的东西：`send(text:)` 默认按 UTF-8 编码，编码策略可配置但不做字符集自动探测。
- ❌ Telnet over TLS/SSL（`telnets`/992、START-TLS、TELNET ENCRYPT 与 AUTHENTICATION 选项）。设备与服务端极少，标准已废弃，Apple 与 Homebrew 的 telnet 都不支持；上游 libtelnet 也未实现 ENCRYPT/AUTHENTICATION。需要保密时由部署方使用 VPN 或跳板机，本库只承载明文 Telnet，并在文档中显著标注这一事实。
- ❌ 非 Apple 平台支持（Linux、Windows、Android 明确不做，也不为它们保留抽象或条件编译）。
- ❌ POSIX/BSD socket 传输路径（`NIOPosix`、裸 `socket()`、`select`/`kqueue`）；传输层只有 Network.framework 一条路。
- ❌ 服务端/监听侧（`NIOTSListenerBootstrap`）产品化；Demo 交付的回显服务端不计入产品接口。

---

## 2. 目标用户与使用场景

### 2.1 用户画像

1. **应用开发者**：需要在 macOS 或 iOS App 中内嵌一个 Telnet 会话（设备调试台、串口转 Telnet 网关客户端、老系统对接）。
2. **运维人员**：写 CLI 工具批量连接网络设备与服务器，跑命令、采集输出、做自动化巡检。
3. **极客与协议研究者**：需要观察或注入 Telnet 协商，验证对端实现是否符合 RFC 1143，或把老设备接到自己的工具链上。

### 2.2 核心用户故事

| ID | 用户故事 | 优先级 |
| --- | --- | --- |
| US-1 | 作为开发者，我可以用一行 `try await TelnetConnection.connect(host:port:)` 建立连接并拿到会话对象 | P0 |
| US-2 | 作为开发者，我可以用 `for await event in conn.events` 消费服务端数据与协商事件，不需要注册回调 | P0 |
| US-3 | 作为开发者，我可以用 `send(text:)` 发送文本，库自动把它已有的 CR/LF（NVT）行尾转换掉并转义 `0xFF` | P0 |
| US-4 | 作为开发者，我可以声明本端支持的选项（`will`/`wont`/`do`/`dont`），库自动完成 RFC 1143 协商而不产生协商回环 | P0 |
| US-5 | 作为开发者，服务端请求 `TTYPE` 时我能自动/手动回应终端类型；请求 `NAWS` 时自动上报窗口尺寸 | P1 |
| US-6 | 作为开发者，连接异常（DNS 失败、超时、对端断开、缓冲区溢出）会以类型化错误抛出，我可以用 `switch` 精确处理 | P0 |
| US-7 | 作为开发者，我可以随时 `await conn.close()`，且未消费的事件不会导致任务泄漏或崩溃 | P0 |
| US-8 | 作为开发者，我可以用 `withTimeout`/`Task` 取消一个连接建立过程，取消会传递到 socket | P0 |
| US-9 | 作为开发者，我可以通过 `.telnet` SwiftUI 视图或参考 Demo 代码，10 分钟内跑通一个可交互客户端 | P1 |
| US-10 | 作为维护者，我能在 CI 上跑完协议单测 + 回环集成测试，且测试不依赖外部网络 | P0 |

---

## 3. 已核实的上游事实（写作依据）

以下事实在撰写本文档前已实际核实（2026-09-21，本机 Xcode 27.0 / Swift 6.4 / macOS 27.0）：

| 项 | 结论 |
| --- | --- |
| 工具链 | `Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)`，SDK 为 MacOSX27.0 |
| swift-nio 最新发布 | **2.103.0**（2026-09-17） |
| libtelnet 仓库结构 | 仅有 `libtelnet.c`、`libtelnet.h`、`CMakeLists.txt`、autotools 文件、`test/`、`doc/`、`util/` |
| libtelnet 是否有 Package.swift | **没有**（`develop` 与 `master` 分支均无）。必须由我们在 Swift Package 内 vendor C 源文件 + `module.modulemap`（已与需求方确认采用此方案） |
| libtelnet 公开面 | `telnet_init/free/recv/iac/negotiate/send/send_text/begin_sb/subnegotiation/begin_compress2/printf/raw_printf/begin_newenviron/newenviron_value/ttype_send/ttype_is/send_zmp/send_zmpv/send_vzmpv/begin_zmp/zmp_arg`，以及 `telnet_finish_sb`、`telnet_finish_newenviron`、`telnet_finish_zmp` 三个**宏**（Swift 不可见，必须用自己的实现补齐） |
| libtelnet 无选项状态查询 | 头文件**不导出**任何查询协商结果的函数。因此 `optionStatus(_:)` 必须由本库在 Swift 侧依据观测到的协商事件自行维护账本，不能读 C 结构体内部状态 |
| libtelnet 不实现安全选项 | 头文件只定义 `TELNET_TELOPT_AUTHENTICATION`(37) 与 `TELNET_TELOPT_ENCRYPT`(38) 两个选项号；`libtelnet.c` 中二者的实现代码为零（`grep -c` = 0），也没有任何 TLS/START-TLS 相关符号。因此「Telnet 协议层加密/认证」在上游永远不会有，加密只能由外部传输层提供 |
| libtelnet 事件模型 | `telnet_event_handler_t(telnet_t*, telnet_event_t*, void *user_data)`，`telnet_event_t` 是 union，事件类型 15 种 |
| libtelnet 压缩 | 由 `HAVE_ZLIB` 编译开关控制，默认关闭 |
| 传输层 | NIOTS（`swift-nio-transport-services` 1.x）把 Network.framework 的 EventLoop、Channel 与 Bootstrap 接入 SwiftNIO；要求 swift-nio ≥ 2.83.0，支持 macOS 10.14+/iOS 12+/tvOS 12+/watchOS 6+，我们的部署下限远高于它 |
| Apple 自带 telnet | 源码在 `apple-oss-distributions/remote_cmds`。`telnet(1)` 与 `telnetd(8)` 手册页全文无 TLS/SSL/certificate 字样；Xcode 工程的预定义宏只有 `AUTHENTICATION`、`KRB5`、`SKEY`、`IPSEC`、`INET6` 等，**从未定义 `ENCRYPTION`**（`grep -c ENCRYPTION project.pbxproj` = 0），即 TELNET ENCRYPT 选项（RFC 2946）整段被编掉，`-x` 手册页描述的「默认已开启加密」与实现不符。结论：Apple 自带 telnet 能认证（Kerberos V5/S/Key），从不加密、从不支持 TLS |
| Homebrew telnet | `brew install telnet` 装的是 **netkit-telnet 308**，用法为 `telnet [-4] [-6] [-8] [-E] [-K] [-L] [-N] [-S tos] [-X atype] …`，同样没有任何 TLS/SSL 选项 |
| Telnet over TLS 的标准状态 | 两份 IETF 草案都没成为 RFC：[draft-altman-telnet-starttls](https://datatracker.ietf.org/doc/draft-altman-telnet-starttls/)（个人提交，IESG 状态 **Dead**，Expired）与 [draft-ietf-tn3270e-telnet-tls](https://datatracker.ietf.org/doc/draft-ietf-tn3270e-telnet-tls/)（tn3270e 工作组，2002 年 Expired，Intended status 为 None）。IANA 的 `telnets 992/tcp` 无 RFC 引用、无联系人。带 TLS 的实现只有 OpenSSL 系的 `telnet-ssl`/`telnetd-ssl`（Debian 仍在维护），FreeBSD/Apple 这条线从未合并 |
| libtelnet 许可证 | 公有领域（public domain dedication，见 `COPYING`） |

**原型验证结果（已实跑，非推测）**：

1. `clang -c libtelnet.c -I include -Wall` → **0 warning / 0 error**，导出 23 个 `_telnet*` 符号。
2. 把 `libtelnet.c/.h` 放进 `Sources/CLibTelnet/`（内含 `module.modulemap`）后 `swift build` 成功，`swift test`（Swift Testing）通过。
3. Swift 侧通过 `telnet_init` 注册闭包回调 + `Unmanaged` user_data，喂入 `FF FB 01`（IAC WILL ECHO）与 `FF FA 18 01 FF F0`（IAC SB TTYPE SEND IAC SE）后，仅收到纯数据 `hello\r\n` —— 协商字节被正确吞掉，**协议解析链路可用**。
4. `telnet_send_text` 发送 `"hi\n"` 产生的出站字节为 `FF FD 01 68 69 0D 0A`：即先补 `IAC DO ECHO`（因为对端已 WILL ECHO），再发送经 NVT 转换的文本，`0x0D 0x0A` 正确 —— **出站编码与协商应答链路可用**。
5. 传输层方案已在官方文档层面核实：NIOTS（`swift-nio-transport-services` 1.x）把 Network.framework 的 EventLoop、Channel、Bootstrap 接入 SwiftNIO，官方声明「普通 NIO 应用只需更换 EventLoopGroup 与 Bootstrap」，并要求 swift-nio ≥ 2.83.0；支持范围为 macOS 10.14+、iOS 12+、tvOS 12+、watchOS 6+。`NIOAsyncChannel` 等异步 API 在 swift-nio 2.x 中为正式 API，参考 [swiftonserver 客户端教程](https://swiftonserver.com/building-swiftnio-clients/)。

> 环境提示：本机沙箱下 SwiftPM 编译 manifest 需要 `sandbox-exec` 权限，验证时使用了放宽的沙箱模式；常规开发不受影响。

---

## 4. 总体架构

### 4.1 包结构（单包 + libtelnet 子模块 + Apple 平台唯一传输层）

```
TelnetKit/
├── Package.swift                       # macOS 15 / iOS 18 / watchOS 11 / tvOS 18 / visionOS 2
├── .gitmodules                         # libtelnet 子模块的 URL
├── libtelnet/                          # [子模块] 上游源码、COPYING 与历史原样保留
│   └── include/module.modulemap        # 纳入版本控制：module CLibTelnet { umbrella header "libtelnet.h" export * }
├── PRD.md
├── README.md
├── LICENSE                             # 本库许可（libtelnet 为 public domain，需在 NOTICE 注明）
├── NOTICE
├── Sources/
│   ├── CLibTelnet/                     # C target：一个纳入版本控制的映射、两个符号链接与来源记录
│   │   ├── libtelnet.c                 # 符号链接 -> ../../libtelnet/libtelnet.c
│   │   ├── include/
│   │   │   ├── libtelnet.h             # 符号链接 -> ../../../libtelnet/libtelnet.h
│   │   │   └── module.modulemap        # 我们的文件，纳入版本控制
│   │   ├── UPSTREAM.md
│   │   └── UPSTREAM.zh.md
│   ├── TelnetKit/                      # [Swift] 唯一公开产品
│   │   ├── Public/                     # 公开类型（全部 Sendable 且无 C 类型）
│   │   │   ├── TelnetConnection.swift
│   │   │   ├── TelnetOptions.swift
│   │   │   ├── TelnetEvent.swift
│   │   │   ├── TelnetCommand.swift
│   │   │   ├── TelnetOption.swift
│   │   │   ├── TelnetError.swift
│   │   │   └── TelnetLogger.swift
│   │   ├── Protocol/                   # 对 libtelnet 的 Swift 化封装（internal）
│   │   │   ├── TelnetProtocolCore.swift
│   │   │   └── TelnetWireCoding.swift
│   ├── Transport/                  # NIOTS/Network.framework 集成（internal）
│   │   ├── TelnetChannelHandler.swift
│   │   ├── TelnetConnectionBootstrap.swift
│   │   └── TelnetNetworkEventMapping.swift
│   ├── TelnetKitClient/                # [可执行，仅 macOS] telnetkit-client 命令行客户端
│   │   └── main.swift
│   └── TelnetEchoServer/               # [可执行，仅 macOS] 本地回环服务端（Demo + 手工对端）
│       └── main.swift
├── Tests/
│   └── TelnetKitTests/
│       ├── PublicAPI/                  # 黑盒：只 import TelnetKit
│       ├── Protocol/                   # 白盒：@testable import，逐事件断言
│       └── Integration/                # 回环集成：真实连接 + NIOTS
└── Examples/
    └── TelnetKitDemoApp/               # SwiftUI Demo（Xcode 工程；macOS 与 iOS 目标）
```

### 4.2 分层与职责

```
┌──────────────────────────────────────────────────────────────┐
│ Public API  TelnetConnection(actor) / TelnetEvent / Options   │  ← 用户只碰这一层
├──────────────────────────────────────────────────────────────┤
│ Protocol    TelnetProtocolCore：封装 telnet_t 生命周期、       │
│             事件回调 → Swift enum、选项表、NVT 编码            │
├──────────────────────────────────────────────────────────────┤
│ Transport   TelnetChannelHandler：ChannelDuplexHandler，       │
│             把 ByteBuffer(入) / IOData(出) ↔ ProtocolCore      │
├──────────────────────────────────────────────────────────────┤
│ NIOTS       NIOTSConnectionBootstrap + NIOTSEventLoopGroup     │
├──────────────────────────────────────────────────────────────┤
│ System      Network.framework（路径、代理、VPN、能耗）         │
├──────────────────────────────────────────────────────────────┤
│ C           CLibTelnet（libtelnet.c，只做协议解析）            │
└──────────────────────────────────────────────────────────────┘
```

**关键设计决策**

| 决策 | 选择 | 理由 |
| --- | --- | --- |
| C 依赖引入方式 | git 子模块 + 指向子模块根的 C target | 上游无 `Package.swift`；子模块保留上游代码、许可证与历史，升级只需切换 commit，且模块映射由脚本生成、不污染 pin |
| 并发边界 | `TelnetProtocolCore` 的**所有权绑定到 NIO EventLoop**，不入 actor | libtelnet 状态机非线程安全，且其回调会同步产生出站字节；绑定 EventLoop 可零锁、零抢占 |
| 公开并发类型 | `TelnetConnection` 用 `actor`，事件用 `AsyncStream` 包装 | 对外天然 `Sendable`，调用方无需理解 EventLoop |
| 事件传递 | `AsyncStream<TelnetEvent>` + 有界缓冲策略 | 提供背压语义；避免无界增长 |
| 出站调用 | `actor` 方法 → `eventLoop.execute` / `NIOAsyncWriter` 串行化 | 保证与 `telnet_*` 调用同线程，规避数据竞争 |
| 错误模型 | Swift `Error` 枚举，映射 libtelnet `telnet_error_t` | 不泄漏 C 错误码 |
| 关闭语义 | `close()` 幂等；`events` 流在通道关闭后 `finish()` | 避免 `for await` 永久挂起 |

### 4.3 线程/并发模型（必须遵守的约束）

1. **单线程所有权**：`telnet_t*` 只在创建它的 EventLoop 上被访问；所有 `telnet_recv`、`telnet_send*`、`telnet_iac`、`telnet_negotiate` 都必须在同一个 `NIOTSEventLoop`（底层为串行 `DispatchQueue`）上调用。
2. **`user_data` 生命周期**：传给 `telnet_init` 的 `Unmanaged` 指针指向 handler 内部状态，`telnet_free` 之后绝不能再被回调使用；handler 的 `deinit` 中先 `telnet_free` 再释放状态。
3. **回调内不得逃逸**：`telnet_event_t` 里的 `buffer`/`name`/`argv` 指针**仅在回调期间有效**，必须在回调内立即拷贝成 Swift 值类型。
4. **回调内不得重入**：事件回调中不能递归调用 `telnet_send*`；需要发送时必须转成"待发出站队列"，在回调返回后由 handler 顺序 flush。
5. **Swift 6 严格并发**：全包启用 `StrictConcurrency`，公开类型全部 `Sendable`；测试中不得使用 `@unchecked Sendable` 掩盖真实竞争（C 封装点除外，且必须注释说明理由 + 有并发测试覆盖）。

---

## 5. 公开 API 设计

> 以下为**接口契约草案**（进入开发后以 Swift Interface 快照测试固化）。所有类型 `Sendable`，所有方法不出现任何 C 类型。

### 5.1 枚举与基础类型

```swift
/// 选项码建模为 struct + static 常量而非 enum：
/// 因为 RFC 1073/1572 等存在大量未内建选项，需要无名兜底值，enum 的 rawValue 无法表达。
public struct TelnetOption: RawRepresentable, Sendable, Hashable, CaseIterable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }   // 任意码，含未内建

    public static let binary: TelnetOption = .init(rawValue: 0)
    public static let echo: TelnetOption = .init(rawValue: 1)
    public static let suppressGoAhead: TelnetOption = .init(rawValue: 3)
    public static let status: TelnetOption = .init(rawValue: 5)
    public static let timingMark: TelnetOption = .init(rawValue: 6)
    public static let terminalType: TelnetOption = .init(rawValue: 24)
    public static let endOfRecord: TelnetOption = .init(rawValue: 25)
    public static let windowSize: TelnetOption = .init(rawValue: 31)
    public static let terminalSpeed: TelnetOption = .init(rawValue: 32)
    public static let remoteFlowControl: TelnetOption = .init(rawValue: 33)
    public static let lineMode: TelnetOption = .init(rawValue: 34)
    public static let environment: TelnetOption = .init(rawValue: 36)
    public static let newEnvironment: TelnetOption = .init(rawValue: 39)
    public static let mssp: TelnetOption = .init(rawValue: 70)
    public static let compress: TelnetOption = .init(rawValue: 85)
    public static let compress2: TelnetOption = .init(rawValue: 86)
    public static let zmp: TelnetOption = .init(rawValue: 93)
    public static let extendedOptionsList: TelnetOption = .init(rawValue: 255)

    /// 已内建建模的选项（供 UI 展示与测试遍历）
    public static var allCases: [TelnetOption] { [...] }
    /// 人类可读名（未内建 → "option(\(rawValue))"）
    public var displayName: String { get }
}

public enum TelnetCommand: UInt8, Sendable, Hashable {
    case endOfFile = 236, suspend = 237, abort = 238, endOfRecord = 239
    case subnegotiationEnd = 240, noOperation = 241, dataMark = 242, brk = 243
    case interruptProcess = 244, abortOutput = 245, areYouThere = 246
    case eraseCharacter = 247, eraseLine = 248, goAhead = 249, subnegotiation = 250
    case will = 251, wont = 252, do_ = 253, dont = 254
}

/// 协商指令（用 Swift 命名，取代 WILL/WONT/DO/DONT 宏）
public enum TelnetNegotiation: Sendable, Hashable { case will, wont, `do`, dont }

public struct TelnetOptionStatus: Sendable, Hashable {
    public var locallyEnabled: Bool     // 本端 WILL
    public var remotelyEnabled: Bool    // 对端 WILL
    public var localRequested: Bool     // 已发出 WILL/WONT 待确认
    public var remoteRequested: Bool    // 已发出 DO/DONT 待确认
}

// MARK: 事件配套值类型（均为纯 Swift 值类型，无 C 依赖）

public enum EnvironmentScope: Sendable, Hashable { case variable, userVariable }
public struct EnvironmentVariable: Sendable, Hashable {
    public var name: String
    public var value: String?
    public var scope: EnvironmentScope
}

/// 可恢复的协议异常（仅产生 .warning，不断连）
public enum TelnetWarning: Error, Sendable, Equatable {
    case truncatedSequence([UInt8])           // 流结束时的半截 IAC 序列
    case unexpectedByte(UInt8, context: String)
    case subnegotiationTruncated(option: TelnetOption)
    case eventBufferOverflowDropped(count: Int)  // 事件缓冲丢弃（见 FR-CONN-08 策略）
    case compressionUnavailable
}

/// 不可恢复的协议错误（产生 .protocolError 并关闭连接）
public enum TelnetProtocolError: Error, Sendable, Equatable {
    case stateMachineFailure(code: TNLErrorCode, message: String)   // libtelnet errcode 的结构化映射
    case invalidSubnegotiation(option: TelnetOption)
    case outOfMemory
}

/// libtelnet `telnet_error_t` 的 Swift 化映射（公开面不出现 C 枚举）
public enum TNLErrorCode: Sendable, Equatable { case badValue, outOfMemory, overflow, protocol, compression }
```

### 5.2 选项配置

```swift
public struct TelnetOptions: Sendable {
    public struct LocalOption: Sendable, Hashable {   // 本端能力
        public var option: TelnetOption
        public var enabledByDefault: Bool
        public init(_ option: TelnetOption, enabledByDefault: Bool = true)
    }
    public struct RemoteOption: Sendable, Hashable {  // 希望对端提供的能力
        public var option: TelnetOption
        public var requestOnConnect: Bool
        public init(_ option: TelnetOption, requestOnConnect: Bool = true)
    }
    public var local: [LocalOption]
    public var remote: [RemoteOption]

    /// 常用预设：本端提供 BINARY + SGA + TTYPE + NAWS，向对端索取 SGA + ECHO
    public static var standardClient: TelnetOptions { get }
    /// 服务端向客户端主动请求 TTYPE / NAWS / NEW-ENVIRON
    public static func serverRequesting(_ options: [TelnetOption]) -> TelnetOptions
    public var isValid: Bool   // BINARY+LINEMODE 冲突等非法组合检测
}
```

### 5.3 事件模型

```swift
public enum TelnetEvent: Sendable {
    /// 应用数据（已剥离协商字节、已按 NVT 规则还原换行）
    case data(ByteBuffer)                    // 库内部使用 NIOCore.ByteBuffer 作为二进制载体
    case negotiation(TelnetNegotiation, option: TelnetOption, remote: Bool)
    case subnegotiation(option: TelnetOption, payload: [UInt8])
    case command(TelnetCommand)
    case terminalTypeRequested                       // 收到 TTYPE SEND
    case terminalType(String)                        // 收到 TTYPE IS
    case environmentRequested(EnvironmentScope)      // SEND
    case environment(EnvironmentScope, [EnvironmentVariable])
    case localEchoChanged(enabled: Bool)             // 结构化便捷事件
    case mssp([String: String])
    case zmp([String])
    case compressionEnabled(Bool)
    case warning(TelnetWarning)                      // 可恢复：协议异常、SB 超长等
    case protocolError(TelnetProtocolError)          // 不可恢复：状态机报错
}

public extension TelnetEvent {
    /// 把 .data 转成 UTF-8 文本（调用方最常用）
    var text: String? { get }
}
```

### 5.4 连接对象

```swift
public actor TelnetConnection {

    // MARK: 建立
    public static func connect(
        host: String,
        port: Int = 23,
        options: TelnetOptions = .standardClient,
        configuration: TelnetConfiguration = .init()
    ) async throws(TelnetError) -> TelnetConnection

    // MARK: 事件流（单消费者语义）
    public nonisolated var events: AsyncStream<TelnetEvent> { get }

    // MARK: 状态
    public var isConnected: Bool { get }
    public var remoteAddress: String? { get }
    public var localAddress: String? { get }
    public func optionStatus(_ option: TelnetOption) -> TelnetOptionStatus

    // MARK: 发送
    public func send(_ bytes: [UInt8]) async throws(TelnetError)      // 原始字节，自动转义 IAC
    public func send(text: String) async throws(TelnetError)          // 自动 NVT 换行转换
    public func send(text: String, lineEnding: TelnetLineEnding) async throws(TelnetError)
    public func sendRaw(_ bytes: [UInt8]) async throws(TelnetError)   // 不做 NVT 转换

    // MARK: 协商
    @discardableResult
    public func negotiate(_ action: TelnetNegotiation, option: TelnetOption) async throws(TelnetError) -> Bool
    public func requestOption(_ option: TelnetOption) async throws(TelnetError)   // DO/WILL 语义糖
    public func subnegotiate(option: TelnetOption, payload: [UInt8]) async throws(TelnetError)
    public func send(command: TelnetCommand) async throws(TelnetError)

    // MARK: 功能封装
    public func replyTerminalType(_ type: String) async throws(TelnetError)
    public func sendEnvironment(_ values: [EnvironmentVariable], scope: EnvironmentScope) async throws(TelnetError)
    public func sendWindowSize(columns: Int, rows: Int) async throws(TelnetError)

    // MARK: 关闭
    public func close() async
}

public enum TelnetLineEnding: Sendable { case crlf, crNul, lf, none }

public struct TelnetConfiguration: Sendable {
    public var connectTimeout: Duration            // 默认 .seconds(10)
    public var waitForConnectivity: Bool           // 默认 true：无路由时挂起等待而非立即失败
    public var idleTimeout: Duration?              // 默认 nil
    public var inboundBufferLimit: Int             // 默认 64 KiB，超限抛 .bufferOverflow
    public var subnegotiationLimit: Int            // 默认 8 KiB，防 SB 洪泛
    public var maxInflatedBytes: Int               // 默认 16 MiB；v0.2 启用 zlib 后约束单次 inflate 输出，防解压炸弹
    public var eventBufferPolicy: TelnetEventBufferPolicy  // .bounded(1024) / .unbounded / .dropOldest
    public var newlinePolicy: TelnetNewlinePolicy // .nvt / .raw
    public var logger: Logger?                     // swift-log；默认 nil（静默）
}
```

### 5.5 错误模型

```swift
public enum TelnetError: Error, Sendable, Equatable {
    case invalidHost(String)                       // DNS 失败
    case connectionRefused(host: String, port: Int)
    case connectTimeout(Duration)
    case notConnected
    case alreadyClosed
    case transportFailed(TelnetTransportFailure)   // 底层 IO 错误（字符串化，不泄漏 NIO 类型到公开泛型）
    case protocolViolation(TelnetProtocolError)
    case bufferOverflow(limit: Int)
    case subnegotiationTooLarge(option: TelnetOption, limit: Int)
    case unsupportedFeature(String)                // 本构建未提供的能力（首版没有触发点）
    case invalidConfiguration(String)
    case cancelled
}

/// 传输层失败的结构化描述：保留可诊断信息，但公开面不出现 NIOCore 的具体错误泛型，
/// 避免上游 NIO 演进破坏 TelnetKit 的 SemVer 兼容性。
public struct TelnetTransportFailure: Error, Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case dns, posix(code: Int32), tls, channelClosed, writeTimeout, other }
    public var kind: Kind
    public var message: String        // 面向开发者的可读描述（不含业务数据）
    public var isRetryable: Bool
}
```

### 5.6 公开接口约束（硬性）

| 约束 | 校验方式 |
| --- | --- |
| 不暴露 `telnet_t`、`telnet_event_t`、`telnet_telopt_t`、`OpaquePointer` 等 C 类型 | `@testable` 外的测试目标 + `swift-api-digester` / interface 快照 Review |
| 不导出 `TELNET_*` 宏对应的 Swift 符号 | 上述快照中禁止出现 `TELNET_` 前缀常量 |
| 公开符号均带文档注释（`///`）且含代码示例 | DocC 构建无 warning；`swift package generate-documentation` 通过 |
| 公开方法均标注 `async`/`throws` 语义并区分错误类型 | `throws(TelnetError)` 显式类型化抛出（Swift 6 typed throws） |
| 可执行目标（Demo / EchoServer）不作为对外产品接口 | `Package.swift` 中标注为 `.executableTarget`，README 说明 |

---

## 6. 功能需求

### 6.1 连接管理（FR-CONN）

| ID | 需求 | 优先级 | 验收标准 |
| --- | --- | --- | --- |
| FR-CONN-01 | `connect(host:port:options:configuration:)` 建立 TCP 连接 | P0 | 能连本机回环 EchoServer 并收到欢迎语 |
| FR-CONN-02 | 支持 DNS 解析域名（`SocketAddress.makeAddressResolvingHost`） | P0 | `localhost` 与 `127.0.0.1` 均可连通 |
| FR-CONN-03 | 连接超时可配置，超时抛 `.connectTimeout` | P0 | 连接黑洞地址（如 `10.255.255.1:23`）在 1s 配置下 1.5s 内抛错 |
| FR-CONN-04 | 连接建立期支持 `Task` 取消，取消抛 `.cancelled` 并关闭 socket | P0 | 取消后 `lsof`/服务端无残留连接 |
| FR-CONN-05 | `close()` 幂等、优雅半关闭、再次调用不报错 | P0 | 连续 `close()` 两次无崩溃、无错误 |
| FR-CONN-06 | 通道关闭（对端 FIN/RST、`idleTimeout`）时 `events` 流 `finish()` | P0 | `for await` 在 2s 内正常退出而非挂起 |
| FR-CONN-07 | 所有公开方法在连接关闭后调用抛 `.notConnected` | P0 | 关闭后 `send` 抛错 |
| FR-CONN-08 | 出站写满时提供背压（`writeAndFlush` 基于 promise + NIO 水位） | P1 | 灌入 100 MB 数据时内存不线性增长 |
| FR-CONN-09 | 入站缓冲超过 `inboundBufferLimit` 时抛 `.bufferOverflow` 并关闭 | P1 | 恶意无换行洪泛被拦截 |
| FR-CONN-10 | 可选 `idleTimeout`：静默超时主动关闭并抛/通知 | P2 | 配置 1s 后无数据，连接在 ~1s 内关闭 |

### 6.2 协议解析与事件（FR-PROTO）

| ID | 需求 | 优先级 | 验收标准 |
| --- | --- | --- | --- |
| FR-PROTO-01 | 完整解析 15 种 libtelnet 事件并映射为 `TelnetEvent` | P0 | 逐事件单测（见 §8）全绿 |
| FR-PROTO-02 | 剥离所有 `IAC` 序列，`.data` 只含应用数据 | P0 | 混合输入下 `.data` 内容精确匹配期望 |
| FR-PROTO-03 | `IAC IAC`（转义）还原为单字节 `0xFF` 并归入 `.data` | P0 | 单测断言字节 |
| FR-PROTO-04 | 非法/截断 `IAC` 序列产生 `.warning` 而非崩溃 | P0 | 模糊输入（随机字节流 10 万次）无崩溃 |
| FR-PROTO-05 | 子协商内容完整保真（含 `IAC` 转义还原） | P0 | TTYPE/NAWS/NEW-ENVIRON 子协商 payload 精确匹配 |
| FR-PROTO-06 | NVT 行尾语义通过 `configuration.newlinePolicy` 暴露，不暴露宏；代理模式不在范围内（§1.3） | P1 | 换行策略有测试；不存在代理模式的验收标准 |
| FR-PROTO-07 | 子协商长度超 `subnegotiationLimit` 时抛 `.subnegotiationTooLarge` | P1 | 超大 SB 被拦截 |
| FR-PROTO-08 | 回调缓冲零拷贝拷贝策略正确（不出现悬垂指针） | P0 | AddressSanitizer 下跑协议单测无报错 |

### 6.3 选项协商与终端能力（FR-NEG）

| ID | 需求 | 优先级 | 验收标准 |
| --- | --- | --- | --- |
| FR-NEG-01 | 按 `TelnetOptions` 在连接建立后自动发起初始协商 | P0 | 与 EchoServer 握手后 `optionStatus(.echo)` 正确 |
| FR-NEG-02 | 遵循 RFC 1143 Q-method，拒绝回环协商 | P0 | 双方同时 WILL 时不产生无限循环（计数断言） |
| FR-NEG-03 | 收到 `WILL/WONT/DO/DONT` 时产生 `.negotiation` 事件 | P0 | 事件顺序与内容精确断言 |
| FR-NEG-04 | 未声明支持的选项默认 `DONT/WONT` 拒绝 | P0 | 服务端 `DO ZMP` 时本端回 `WONT ZMP` |
| FR-NEG-05 | 支持 `TTYPE`：请求、上报、多类型轮询（重复类型终止） | P1 | 模拟服务端轮询逻辑通过 |
| FR-NEG-06 | 支持 `NAWS`：窗口尺寸变更时自动上报（4×UInt16 大端，含 255 转义） | P1 | SwiftUI Demo 缩放窗口后服务端收到新尺寸 |
| FR-NEG-07 | 支持 `NEW-ENVIRON`：接收变量表并结构化；可主动发送 | P1 | 变量/值/转义（`ESC`）字节序列正确 |
| FR-NEG-08 | 支持 `MSSP` 解析为 `[String: String]` | P2 | 标准 MSSP 报文解析正确 |
| FR-NEG-09 | 支持 `ZMP` 命令与参数解析 | P2 | 多参数/空参数边界正确 |
| FR-NEG-10 | 不在 `TelnetOptions` 中登记 `compress2`：本端对协商回 `WONT`，绝不接受压缩流 | P1 | 收到 `DO COMPRESS2` 时出站 `WONT COMPRESS2`；`optionStatus(.compress2)` 全为 false |
| FR-NEG-11 | 启用压缩（v0.2）的前置条件写清楚：解压上限、压缩态事件流契约、压缩流失败模式三者都有设计才可开启 | P2 | 三项设计各自有测试；缺任一项则 `HAVE_ZLIB` 保持未定义 |
| FR-NEG-12 | `optionStatus(_:)` 实时反映协商状态 | P1 | 协商前后状态断言 |
| FR-NEG-13 | `sendWindowSize`、`replyTerminalType` 等能力可从 Demo 手动触发 | P1 | Demo 中有对应入口 |

### 6.4 文本与编码（FR-TEXT）

| ID | 需求 | 优先级 | 验收标准 |
| --- | --- | --- | --- |
| FR-TEXT-01 | `send(text:)` 默认把字符串已有的行尾改写为 CRLF（`TelnetLineEnding.crlf`）；它不补行尾 | P0 | `send(text: "hi\n")` 写出 `68 69 0D 0A`，`send(text: "hi")` 写出 `68 69` |
| FR-TEXT-02 | 支持把字符串已有的行尾改写为 `crNul` / `lf` / `none` | P1 | 三种策略字节断言，且 `.none` 保持原样 |
| FR-TEXT-03 | BINARY 模式已协商时不做 CR/LF 转换（与 `TELNET_FLAG_NVT_EOL` 语义一致） | P0 | 二进制模式下 `0x0A` 保真 |
| FR-TEXT-04 | 所有文本按 UTF-8 编码；非法字符按 `.lossy` 策略替换并记 warning | P1 | 非 UTF-8 输入不崩溃 |
| FR-TEXT-05 | `send(_ bytes:)` 自动转义 `0xFF`，`sendRaw` 不转义（供高级用法） | P0 | 字节断言 |

### 6.5 网络路径与连接可用性（FR-PATH）

NIOTS 把 Network.framework 的路径事件暴露给 SwiftNIO（`NIOTSNetworkEvents`），这是只用一个传输层换来的能力，因此作为需求而非可选项。

| ID | 需求 | 优先级 | 验收标准 |
| --- | --- | --- | --- |
| FR-PATH-01 | `waitForConnectivity: true` 时，无可用路由的连接请求挂起等待，而不是立即失败 | P0 | 模拟无路由环境，连接不抛错且不结束；路由恢复后连接建立成功 |
| FR-PATH-02 | 路径变化映射为 `.pathChanged(viable:expensive:constrained:)` 事件 | P0 | 切蜂窝↔Wi‑Fi 时收到事件，且 `viable` 取值与 `NWPath` 一致 |
| FR-PATH-03 | 出现更优路径时发出 `.betterPathAvailable`，消失时发出 `.betterPathUnavailable` | P1 | 事件按 `NIOTSNetworkEvents` 语义成对出现 |
| FR-PATH-04 | 连接被系统暂停（等待连通性）时发出 `.waitingForConnectivity(error:description:)`，连接不被关闭 | P0 | 事件可观测，后续恢复不产生重复的连接建立事件 |
| FR-PATH-05 | 路径事件不改变协议状态：`optionStatus(_:)` 与协商状态在路径切换前后一致 | P0 | 切换前后断言 `optionStatus` 相同 |
| FR-PATH-06 | 路径事件在公开接口中以 Swift 值表达，不泄漏 `NWPath` 类型 | P1 | 快照中不出现 `NWPath`、`NWError`、`nw_*` |
| FR-PATH-07 | 仅在通道激活之后才发出 `.pathChanged` | P1 | 测试断言连接事件之前没有路径事件 |

### 6.6 错误与诊断（FR-ERR）

| ID | 需求 | 优先级 | 验收标准 |
| --- | --- | --- | --- |
| FR-ERR-01 | libtelnet `telnet_error_t` 全量映射到 `TelnetError` | P0 | 映射表单测；无 `default: fatalError` |
| FR-ERR-02 | `.protocolError` 触发后连接关闭且 `events` 结束 | P0 | 断言关闭与流结束 |
| FR-ERR-03 | `.warning` 不中断连接 | P0 | 警告后仍可收发 |
| FR-ERR-04 | 可选 `Logger`（swift-log）输出：协议帧（trace）、状态变更（debug）、连接事件（info）、错误（error） | P1 | 注入内存 Logger 断言至少 4 类日志 |
| FR-ERR-05 | 默认不记录应用数据内容（防泄漏敏感信息），需显式开启 | P1 | 默认配置下日志不含 payload |

---

## 7. 非功能需求

| 类别 | 需求 |
| --- | --- |
| 语言与工具链 | Swift 6 语言模式（`swiftLanguageModes: [.v6]`），`swift-tools-version: 6.2`，最低 Xcode 26 / Swift 6.2 |
| 部署目标 | `platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18), .visionOS(.v2)]`；库产物只在这五个 Apple 平台上承诺，非 Apple 平台不做也不保留分支 |
| 严格并发 | 全包 `StrictConcurrency` 完整检查，0 warning |
| 依赖 | `swift-nio`（2.103.0 起）、`swift-log`（1.x，用于可选日志）；不引入其他第三方运行时依赖 |
| 二进制体积 | 单架构 release 下 TelnetKit 增量 < 500 KiB（含 C 源） |
| 性能 | 单连接吞吐 ≥ 50 MB/s（回环、64 KiB 缓冲）；协议解析每字节额外分配次数为 0（除事件边界） |
| 内存 | 单连接常驻内存 < 2 MiB（不含 NIO EventLoop 池）；10 万条输入事件无泄漏（`leaks`/`valgrind` 或 Instruments） |
| 安全 | 不信任对端输入：所有解析路径有长度上限；`IAC` 状态机对截断输入安全；默认不打印业务数据 |
| 可测试性 | 协议层可脱离网络单测（纯 `recv → [TelnetEvent]`）；网络层可对回环服务端集成测试；测试不访问外网 |
| 文档 | 每个公开符号有 DocC 注释与可运行示例；README 覆盖 5 分钟上手；CHANGELOG 遵循 Keep a Changelog |
| 兼容性策略 | SemVer；公开 API 快照测试（interface snapshot）纳入 CI，破坏性变更须显式提交快照 |
| 可观测性 | 与 swift-log 集成；可选 `NIOAsyncChannel` 的 metrics/`swift-metrics`（P2） |

---

## 8. 测试策略与用例清单

### 8.1 分层

本节的用例清单是需求清单；环境、命令、质量门槛与 CI 矩阵由 [docs/testing.md](docs/testing.md) 负责。

| 层 | 目标 | 手段 |
| --- | --- | --- |
| L1 协议单测（白盒） | 逐事件、逐字节正确性 | `@testable import TelnetKit` + `TelnetProtocolCore` 直接喂字节 |
| L2 公开接口测试（黑盒） | 契约稳定性、无 C 泄漏、错误语义 | 只 `import TelnetKit`，配合测试 target 内的回环夹具 |
| L3 集成测试 | 真实连接、超时、取消、并发多连接、路径事件 | `NIOTSConnectionBootstrap` 连本地 `NIOTSListenerBootstrap` 夹具 |
| L4 健壮性 | 模糊输入、资源上限 | 随机/恶意字节流、超大 SB、洪泛 |
| L5 静态保障 | 接口、并发与五平台构建 | `swift-api-digester` 快照、`swift build -Xswiftc -strict-concurrency=complete`、AddressSanitizer job、iOS/watchOS/tvOS/visionOS 模拟器构建与测试矩阵 |

框架统一使用 **Swift Testing**（`import Testing`，`@Test`/`@Suite`/`#expect`/`#require`），异步用 `async` 测试函数；需要超时保护的用 `withTimeout` 辅助（测试内自建）。协议套件在五个平台都能跑；公开接口与集成套件要绑定回环监听，只在 macOS 与 iOS 模拟器上跑。

### 8.2 用例清单（公开接口必测）

**A. 连接生命周期（对应 FR-CONN）**

| 用例 | 断言 |
| --- | --- |
| `connect_loopback_succeeds` | 返回非 nil，`isConnected == true`，`remoteAddress == "127.0.0.1:<port>"` |
| `connect_refused_throws_connectionRefused` | 关闭端口连接抛 `.connectionRefused` |
| `connect_unresolvable_host_throws_invalidHost` | 抛 `.invalidHost` |
| `connect_timeout_throws_connectTimeout` | 连接超过配置上限 → `.connectTimeout` |
| `connect_cancellation_throws_cancelled` | `Task` 取消 → `.cancelled`，服务端无残留连接 |
| `close_is_idempotent` | 两次 `close()` 无错误 |
| `events_finish_on_remote_close` | 服务端关闭后 `for await` 正常结束（带 2s 超时保护） |
| `send_after_close_throws_notConnected` | 抛 `.notConnected` |
| `optionStatus_reflects_negotiation` | 握手后 echo/SGA 状态正确 |
| `inbound_buffer_limit_enforced` | 超限发出致命 `.protocolError` 并关闭连接 |

**B. 协议解析（对应 FR-PROTO，白盒逐事件）**

| 用例 | 输入 → 期望 |
| --- | --- |
| `data_passthrough` | `"hello\r\n"` → `.data("hello\r\n")` |
| `iac_escape_unescaped` | `FF FF` → `.data([0xFF])` |
| `will_wont_do_dont_events` | `FF FB 01` / `FF FC 01` / `FF FD 01` / `FF FE 01` → 4 条 `.negotiation` 且 remote 标记正确 |
| `iac_command_events` | `FF F1`(NOP)、`FF F9`(GA)、`FF EC`(EOF) → `.command(...)` |
| `subnegotiation_payload` | `FF FA 18 00 78 74 65 72 6D FF F0` → `.terminalType("xterm")` |
| `subnegotiation_with_escaped_ff` | payload 含 `FF FF` → 还原为 `0xFF` |
| `truncated_iac_sequence_warns` | `FF FB`（流结束）→ `.warning`，不崩溃 |
| `garbage_stream_no_crash` | 10 万随机字节 → 无崩溃，事件自洽 |
| `subnegotiation_limit_exceeded` | 入站块超限 → `.protocolError(.invalidSubnegotiation(option:))`；出站 payload 超限抛 `.subnegotiationTooLarge` |
| `newenviron_parsing` | VAR/USERVAR/VALUE/ESC 组合 → 结构化变量正确 |
| `mssp_parsing` | `1 name 2 value` → `["name": "value"]` |
| `zmp_parsing` | 多参数命令 → `["cmd", "a", "b"]` |
| `nvt_eol_flag_behavior` | 两种 newline 策略字节差异断言 |

**C. 协商与终端能力（对应 FR-NEG）**

| 用例 | 断言 |
| --- | --- |
| `initial_negotiation_sent_on_connect` | 服务端收到的首批字节是每个已声明条目一个 `IAC <verb> <option>` 三元组，顺序同声明顺序 |
| `rfc1143_no_negotiation_loop` | 重复与同时到达的动词各只应答一次；客户端字节数保持有界 |
| `unsupported_option_rejected` | 收到 `DO ZMP` 且未声明 → 出站含 `WONT ZMP` |
| `ttype_send_triggers_reply_or_event` | 收到 TTYPE SEND → `.terminalTypeRequested`；`replyTerminalType` 发出 IS，重复 SEND 会再次应答 |
| `naws_reported_on_window_resize` | 变更窗口 → 服务端收到 4 字节大端尺寸 |
| `naws_escapes_255` | 列宽 255 → payload 含 `FF FF` |
| `compress2_unsupported` | 协商 → `WONT`，`optionStatus(.compress2)` 全 false，且不抛错 |

**D. 文本与编码（对应 FR-TEXT）**

| 用例 | 断言 |
| --- | --- |
| `send_text_crlf` / `send_text_crNul` / `send_text_lf` / `send_text_none` | 出站字节精确匹配 |
| `send_escapes_iac` | 含 `0xFF` 的应用字节 → 出站 `FF FF`；UTF-8 文本不会出现 `0xFF` 字节 |
| `binary_mode_disables_newline_translation` | BINARY 协商后 `0x0A` 原样 |
| `send_raw_bytes_not_escaped` | `sendRaw([0xFF])` 出站为单字节 |

**E. 错误与日志（对应 FR-ERR）**

| 用例 | 断言 |
| --- | --- |
| `error_code_mapping_exhaustive` | 遍历 `telnet_error_t` 全量 → 均有非崩溃映射 |
| `protocol_error_closes_connection` | 触发 `.protocolError` 后 `isConnected == false` 且流结束 |
| `warning_does_not_close` | warning 后可继续收发 |
| `logger_receives_expected_categories` | 内存 Logger 捕获 info/debug/error |
| `logger_redacts_payload_by_default` | 默认配置日志不含业务内容 |

**F. 并发与资源（对应 NFR）**

| 用例 | 断言 |
| --- | --- |
| `concurrent_connections_are_isolated` | 8 条并发连接各自收到正确回显，无交叉串包 |
| `concurrent_sends_serialized` | 100 个并发 `send(text:)` 全部完整到达、无交错截断 |
| `memory_stable_after_100k_events` | 10 万事件后常驻内存增幅 < 阈值 |
| `no_dangling_buffer_with_asan` | ASan 构建下全量协议测试通过 |

**G. 公开接口契约（对应 §5.6）**

| 用例 | 断言 |
| --- | --- |
| `publicAPI_has_no_clibtelnet_symbols` | 反射/接口快照中无 `telnet_`、`TELNET_`、`OpaquePointer` |
| `publicAPI_snapshot_matches` | `swift package diagnose-api-breaking-changes <baseline>` 无破坏性变更 |
| `documentation_builds` | `xcodebuild docbuild` 产出 `TelnetKit.doccarchive`，target 诊断数为 0 |

### 8.3 质量门槛

- 公开接口测试（L2）**必须覆盖 §5 中列出的每一个公开符号**（方法/属性/枚举 case），覆盖率报告对比公开符号清单核对，缺失即不通过。
- 协议层语句覆盖率不低于 90%。Swift 下 `llvm-cov` 不产出分支数据，因此改为同时记录 region（84.1%）与函数（78.2%）覆盖率，而不是设分支门槛。
- 全部测试必须能离线运行，`swift test` 单次耗时 < 60s。

---

## 9. Demo 项目需求

### 9.1 交付物

| 名称 | 形态 | 作用 |
| --- | --- | --- |
| `telnetkit-client` | `.executableTarget`（CLI，仅 macOS） | 完整交互式 Telnet 客户端：接受 `telnet(1)` 参数并驱动 TelnetKit；它是可用工具，而不是接口展示程序 |
| `TelnetEchoServer`（命令名 `telnetkit-echo-server`） | `.executableTarget`（本地服务端，仅 macOS） | 无外部依赖的联调目标：回显 + 主动发起 TTYPE/NAWS/NEW-ENVIRON 协商 + 注入协商/子协商/Warning/超长子协商场景 |
| `TelnetKitDemoApp` | SwiftUI App，macOS 与 iOS 目标（`Examples/`） | 可交互终端：连接面板、输出区、输入框、选项状态表、事件日志、窗口尺寸自动上报 |

### 9.1.1 文档交付物

本 PRD 的工程约束拆分为开发文档，与代码同仓维护，分层与写作规则见 [docs/AGENTS.md](docs/AGENTS.md)：

| 文档 | 职责 |
| --- | --- |
| [AGENTS.md](AGENTS.md) | 常驻规则：仓库结构、命令、不可协商的约束、约定 |
| [docs/architecture.md](docs/architecture.md) | 设计地图：分层、并发模型、事件流、C 接缝、扩展点、测试布局 |
| [docs/public-api.md](docs/public-api.md) | 公开接口调用方契约与公开符号测试清单 |
| [README.md](README.md) / [README.zh.md](README.zh.md) | 使用方契约：能力、安装、快速开始、已知限制、安全说明 |
| [Examples/TelnetKitDemoApp/README.md](Examples/TelnetKitDemoApp/README.md) | Demo 应用的运行步骤与它所演练的接口 |
| [.agents/skills/](.agents/skills/) | 可复用工作流：公开接口切片、C 库引入、文档规范、行文规范 |

### 9.2 Demo 必须覆盖的接口清单

| 接口 | Demo 中的体现 |
| --- | --- |
| `TelnetConnection.connect(host:port:options:configuration:)` | 连接表单（主机/端口/超时/选项勾选） |
| `TelnetConfiguration` 全部构造参数 | 设置面板（超时、缓冲上限、换行策略、日志开关） |
| `events` + 全部 `TelnetEvent` case | 事件日志面板按 case 分类着色 |
| `send(text:)` / `send(_:)` / `sendRaw(_:)` / `send(text:lineEnding:)` | 输入框发送 + 行尾选择 |
| `negotiate(_:option:)` / `requestOption(_:)` / `subnegotiate(option:payload:)` / `send(command:)` | 手动协议操作按钮 |
| `replyTerminalType(_:)` / `sendEnvironment(...)` / `sendWindowSize(columns:rows:)` | 终端设置区；窗口尺寸随 SwiftUI 窗口变化自动上报 |
| `optionStatus(_:)` / `isConnected` / `remoteAddress` | 状态栏 |
| `close()` | 断开按钮 + 窗口关闭时自动断开 |
| `TelnetError` 全部 case | 错误注入菜单（连接错误端口、超时地址、超大 SB）验证错误展示 |
| `Logger` 注入 | 控制台/面板日志级别切换 |

### 9.3 Demo 验收标准

1. `swift run telnetkit-client 127.0.0.1 2323` 能连上本地服务端并完成一次交互，无需网络与外部服务。
2. Demo 能连真实外部 Telnet 服务（如公开 BBS / 设备）并完成一次完整交互（登录提示可见、可输入命令）；iOS 侧以模拟器内的最小示例打同一台回环服务端，验证同一路径。
3. `TelnetKitDemoApp` 在 macOS 15+ 打开即可用；窗口缩放触发 NAWS 上报（EchoServer 日志可见）。库本身在 iOS 18+ 模拟器上构建通过并跑完全部非网络测试。
4. Demo 代码即文档：每个公开接口在 Demo 中至少出现一次，且在 README 中有对应代码片段。

---

## 10. 里程碑与交付计划

| 里程碑 | 内容 | 出口标准 | 状态 |
| --- | --- | --- | --- |
| M0 脚手架 | `Package.swift`（五平台 + NIOTS 依赖）、libtelnet 子模块 + 我们纳入版本控制的 module map 与两个符号链接 + `UPSTREAM.md`（记录 pin 住的 commit）、目录骨架、CI 骨架、LICENSE/NOTICE | `swift build`/`swift test` 在 macOS 15 目标下通过，且五平台均可构建（**已验证：`swift build --target TelnetKit --triple` 在 macOS 15、iOS 18、watchOS 11、tvOS 18 与 visionOS 2 下限下均成功**） | 已交付 |
| M1 协议层 | `TelnetProtocolCore` + 全部 `TelnetEvent` 映射 + NVT 编码 + L1 单测（B/D 组） | B/D 组用例全绿，ASan 通过 | 已交付 |
| M2 连接层 | `TelnetChannelHandler` + `TelnetConnection` actor + 超时/取消/关闭 + L2/L3 测试（A 组） | A 组用例全绿；`leaks --atExit` 在 300 条连接与 10 万事件后报告 0 泄露字节 | 已交付 |
| M3 协商与能力 | RFC 1143 协商策略、TTYPE/NAWS/NEW-ENVIRON/MSSP/ZMP + C 组测试 | C 组用例全绿；重复与同时协商产生的字节数有界 | 已交付 |
| M4 质量与文档 | E/F/G 组测试、DocC、接口快照、覆盖率门槛、README、CHANGELOG | 协议层行覆盖率 92.3%；DocC 构建 target 诊断数为 0；符号图中无违禁名；API 基线与当前一致 | 已交付 |
| M5 Demo | `telnetkit-client`、`telnetkit-echo-server` 与 `Examples/TelnetKitDemoApp/` 下的 SwiftUI Demo 应用 | §9.3 四条标准全部成立：客户端能连上回显服务端，对真实 telnetd 的会话进入 shell，缩放窗口时服务端日志打印 `NAWS 105x32`，库在 iOS 18 模拟器上 115 个测试全绿且 App 在 iOS 模拟器里跑通回环服务端，App 覆盖全部公开接口且有配套 README 片段 | 已交付 |
| M6 Apple 平台矩阵 | `Package.swift` 声明五平台；CI 增加 iOS/watchOS/tvOS/visionOS 模拟器构建与测试；路径事件（FR-PATH）与后台挂起行为在 iOS 下复核 | 五平台构建成功（**已验证：`swift build --target TelnetKit --triple` 在 macOS 15、iOS 18、watchOS 11、tvOS 18 与 visionOS 2 下限下均成功**）；协议层与公开接口测试在 macOS 与 iOS 全绿（**已验证：115 个测试在 `swift test` 下通过，并在 iPhone 17 模拟器上经 `xcodebuild test` 再次全部通过**），其余平台构建通过 | 已交付 |
| M7 发布 | v0.1.0 tag、Release Notes、macOS 与 iOS 模拟器截图/录屏 | 打 tag 并归档 `Package.resolved` | 计划中 |

> 状态：**已交付** 表示出口标准已满足且证据记录在 [AGENTS.md](AGENTS.md#design-status)；**部分完成** 表示代码或证据已落地但出口标准尚未满足；**计划中** 表示尚未开始。M6 满足其出口标准：五平台构建成功，115 个测试在 macOS 与 iPhone 17 模拟器上全绿，CI workflow 已带上四模拟器矩阵，其余平台构建通过；真实蜂窝↔Wi‑Fi 切换仍是 [docs/testing.zh.md](docs/testing.zh.md#手工验收) 中的纯设备步骤；M5 的 §9.3 四条标准全部成立。

> 建议节奏：M0–M1 一次性完成；M2/M3 可并行；M4/M5 在 M2/M3 后并行；M6 依赖 M4 的全绿测试；每里程碑均有可运行产物，不积累"最后集成"风险。

---

## 11. 风险与对策

| ID | 风险 | 影响 | 对策 |
| --- | --- | --- | --- |
| R1 | libtelnet 无 SwiftPM 支持，vendor 后上游更新需手工同步 | 低 | 在 `NOTICE`/`CLibTelnet/README` 记录上游 commit SHA 与版本（当前 0.23）；每季度检查上游 diff；仅同步 `libtelnet.c/.h`，不修改上游代码（如需 patch 必须单独成 patch 文件并注明） |
| R2 | libtelnet 回调 buffer 仅在回调期间有效，Swift 侧极易写出悬垂指针 | 高 | 强制"回调内立即拷贝"；`TelnetProtocolCore` 不对外暴露指针；ASan 测试 + 专项 code review checklist |
| R3 | `telnet_t` 非线程安全，跨线程访问导致数据竞争 | 高 | 单 EventLoop 所有权（§4.3）；所有入站/出站经 handler 串行化；`Sendable` 检查 + 并发测试 |
| R4 | `telnet_finish_sb` / `telnet_finish_newenviron` / `telnet_finish_zmp` 是宏，Swift 不可见 | 中 | 在 `TelnetProtocolCore` 内以其等价实现替代（`telnet_iac(t, TELNET_SE)`），并在单测中覆盖 |
| R5 | 选项协商策略自研容易产生协商回环或状态错乱 | 中 | 完全复用 libtelnet 的 RFC 1143 Q-method 实现，不自研状态机；补充"报告给用户的 `optionStatus`"与 libtelnet 内部状态一致性的断言 |
| R6 | Telnet 明文传输（含口令），且本库不提供任何加密通道 | 高 | README 与 DocC 显著标注；`telnets`/START-TLS/ENCRYPT/AUTHENTICATION 明确列为不支持；需要保密时由部署方使用 VPN 或跳板机，并在 `TelnetConfiguration` 文档中说明本库不参与保密 |
| R7 | 启用 MCCP2 的解压路径可能被解压炸弹放大（几 KB → GB 级内存） | 中 | 首版不启用；v0.2 启用时必须同时落地 `maxInflatedBytes` 上限、压缩态事件流契约与压缩流失败模式测试，并在 CI 增加开启变体。zlib 本身无需处理：macOS/iOS/iPadOS SDK 均内置（已实测 `-lz` 可链接） |
| R8 | `AsyncStream` 事件缓冲策略不当导致内存暴涨或事件丢失 | 中 | 默认 `.bounded`，丢弃/终止策略可配且**丢弃时发出 `.warning`**；补大流量压测 |
| R9 | 公开 API 与 swift-nio 类型（如 `ByteBuffer`）耦合，未来升级受限 | 低 | `TelnetEvent.data` 采用 `ByteBuffer` 作为二进制载体（与 NIO 生态一致）；同时提供 `text`/`bytes([UInt8])` 便捷访问，避免调用方必须理解 NIO |
| R10 | 应用后台挂起会断开连接（watchOS 与 iOS 最明显），App Store 审核关注明文协议 | 中 | 文档写明「前台会话」语义与后台断开行为，不引入后台常驻能力；提供 `idleTimeout` 与应用层重连示例；`waitForConnectivity` 让恢复时的重连不必手写重试循环；README 安全章节标注明文风险 |
| R11 | 五平台 CI 成本与模拟器资源占用 | 中 | iOS 跑完整测试；watchOS/tvOS/visionOS 只跑构建加不碰网络的套件（vendored C 套件与协议套件）；公开接口与集成套件固定在 macOS 与 iOS 模拟器 |
| R12 | NIOTS 只能在有 Network.framework 的运行时验证：CI 的本机 `swift test` 无法覆盖真实路径事件 | 中 | 集成测试用 `NIOTSListenerBootstrap` 起本地夹具；路径事件用注入的 `NIOTSNetworkEvents` 在协议层单测；真机/模拟器的蜂窝↔Wi‑Fi 切换列入 M6 手工验收 |
| R13 | 单一传输层没有退路：若 Network.framework 在某平台行为异常（例如 watchOS 的连接可用性），没有备选路径 | 中 | 只在五个 Apple 平台承诺且以官方支持的组合为前提；发现平台级缺陷时按平台文档化限制，不临时引入 POSIX 分支（那会推翻 G6） |

---

## 12. 待确认问题

| ID | 问题 | 建议默认值 |
| --- | --- | --- |
| Q1 | `TelnetEvent.data` 用 `NIOCore.ByteBuffer` 还是自定义 `[UInt8]`？ | 用 `ByteBuffer`（零拷贝、与 NIO 生态一致），并提供 `[UInt8]`/`String` 便捷视图 |
| Q2 | 断线重连由库提供还是仅给示例？ | 仅给示例：库负责 `waitForConnectivity` 与清晰错误，重连策略由调用方决定 |
| Q3 | SwiftUI DemoApp 放在包内可执行目标还是 `Examples/` 独立 Xcode 工程？ | 已决策：放 `Examples/` 独立工程，并连同其 XcodeGen `project.yml` 一起提交，避免包内引用 SwiftUI 拖慢 `swift test`；应用自带视图，不新增包内组件 |
| Q4 | 是否需要 `swift-metrics`/`swift-service-lifecycle` 集成？ | 首版不需要，swift-log 足够 |
| Q5 | 是否同步发布中文文档？ | 已决策：全部面向人的文档均为中英双语配对，规则见 [docs/AGENTS.md](docs/AGENTS.zh.md#双语配对)，因此本 PRD 与 [PRD.md](PRD.md) 配对 |

---

## 13. 参考

- [apple/swift-nio](https://github.com/apple/swift-nio)（最新发布 2.103.0）
- [seanmiddleditch/libtelnet](https://github.com/seanmiddleditch/libtelnet)（v0.23，public domain；无 SwiftPM 清单）
- [Developing a basic Swift echo server using Swift NIO](https://medium.com/processone/developing-a-basic-swift-echo-server-using-swift-nio-8a5bf3d3fef2)
- [Building SwiftNIO clients — swiftonserver.com](https://swiftonserver.com/building-swiftnio-clients/)
- [SwiftNIO `NIOAsyncChannel` 与 async bootstrap 文档](https://github.com/apple/swift-nio/blob/2.57.0/Sources/NIOCore/Docs.docc/swift-concurrency.md)
- RFC 854 / RFC 855（Telnet 协议）、RFC 1143（Q-Method 选项协商）、RFC 1073（NAWS）、RFC 1091（TTYPE）、RFC 1572（NEW-ENVIRON）、RFC 859/860（MSSP 相关）
- [Swift Testing 文档](https://developer.apple.com/documentation/testing)

---

## 附录 A：`Package.swift` 草案

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TelnetKit",
    platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11), .tvOS(.v18), .visionOS(.v2)],
    products: [
        .library(name: "TelnetKit", targets: ["TelnetKit"]),
        .executable(name: "telnetkit-client", targets: ["TelnetKitClient"]),
        .executable(name: "telnetkit-echo-server", targets: ["TelnetEchoServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.103.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.20.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.0"),
    ],
    targets: [
        // SwiftPM 只在公开头文件目录里找自定义 module map，而该目录须位于 target path 之下，
        // 且 .c 也从同一路径编译；因此 target 指向我们自己的目录，由两个已提交的符号链接
        // 访问子模块的源码与头文件。
        // 不定义 HAVE_ZLIB：Apple SDK 自带 zlib 可直接 -lz，首版仍不链接（理由与启用条件见 §1.3 与 §6.3 FR-NEG-11）。
        .target(
            name: "CLibTelnet",
            path: "libtelnet",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TelnetKit",
            dependencies: [
                "CLibTelnet",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "Logging", package: "swift-log"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(name: "TelnetKitClient", dependencies: ["TelnetKit"], path: "Sources/TelnetKitClient"),
        // 可执行产物只声明 macOS：watchOS/tvOS/visionOS 没有进程与回环服务端语义。
        .executableTarget(name: "TelnetEchoServer", dependencies: [
            .product(name: "NIOCore", package: "swift-nio"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
        ]),
        .testTarget(name: "TelnetKitTests", dependencies: ["TelnetKit"]),
    ]
)
```

> 说明：原型验证中 `CLibTelnet` 未使用任何自定义编译宏与互操作模式，仅靠 `module.modulemap` 即可被 Swift 正常 `import`，故正式实现同样保持最小配置。
> `swiftLanguageModes` 亦可在包级统一声明（`swiftLanguageModes: [.v6]`），此处按 target 声明以便未来对测试目标放宽。
> 克隆后只需一条命令 `git submodule update --init --recursive`；符号链接与 module map 均已纳入版本控制，不存在生成步骤。
> `path` 与 `publicHeadersPath` 是 SwiftPM 的要求：`.c` 从 target path 编译，公开头文件必须位于该路径之下。
> 若改为 `Sources/CLibTelnet/` 副本（不使用子模块），则只需 `.target(name: "CLibTelnet")`，路径与头文件目录都用默认值。

## 附录 B：`CLibTelnet` 目录与 modulemap

```c
// Sources/CLibTelnet/include/module.modulemap（纳入版本控制；module CLibTelnet 定义在此）
module CLibTelnet {
    umbrella header "libtelnet.h"   // 该头文件是指向子模块的符号链接
    export *
}
```

- `libtelnet.c` 与 `libtelnet.h` 来自 `libtelnet/` 子模块，pin 住的 commit 为 `5f5ecee`（版本注释 `\version 0.23`），通过两个已提交的相对符号链接访问；**上游文件不做任何修改，也不向子模块写入任何内容**。
- pin 由 gitlink 承载，另在 `Sources/CLibTelnet/UPSTREAM.md` 记录；升级即切换子模块 commit 并确认两个链接仍可解析。
- 宏 `telnet_finish_sb` / `telnet_finish_newenviron` / `telnet_finish_zmp` 在 Swift 侧由 `TelnetProtocolCore` 等价实现，不依赖 C 宏导出。

## 附录 C：典型用法示例（Demo/README 使用）

```swift
import TelnetKit

let conn = try await TelnetConnection.connect(
    host: "127.0.0.1",
    port: 2323,
    options: .standardClient,
    configuration: .init(connectTimeout: .seconds(5))
)

// 消费事件
Task {
    for await event in conn.events {
        switch event {
        case .data(let buffer):
            print(buffer.string ?? "", terminator: "")
        case .negotiation(let action, let option, let remote):
            print("[\(remote ? "remote" : "local")] \(action) \(option)")
        case .terminalTypeRequested:
            try? await conn.replyTerminalType("xterm-256color")
        default:
            print(event)
        }
    }
}

try await conn.send(text: "hello telnet")
try await conn.sendWindowSize(columns: 120, rows: 40)
try await conn.close()
```
