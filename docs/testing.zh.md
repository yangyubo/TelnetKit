# TelnetKit 测试方案

[English](testing.md) | 中文

本文负责"每个套件怎么跑"：环境、框架、每一层的具体命令、质量门槛与 CI 矩阵。需求编号与验收标准留在 [PRD.md](../PRD.md#8-测试策略与用例清单)；单个测试的设计说明留在测试源码里，依据是[层级表](AGENTS.zh.md#层级分类一个事实一个家)。本包尚未实现，因此依据[设计状态规则](../AGENTS.md#design-status)，下文每一条都是**设计中**。

## 环境

在开发机上已核实的事实（Xcode 27.0、`swift-driver` 1.168.6、Apple Swift 6.4、macOS 27.0）：

| 项 | 值 | 为什么重要 |
|---|---|---|
| 框架 | `Testing.framework` 与 `XCTest.framework` 同随 Xcode SDK 提供 | Swift Testing 不需要任何包依赖，也不需要检出 `swift-testing` |
| SwiftPM | `swift test` 支持 `--enable-code-coverage`、`--sanitize`、`--filter`、`--skip`、`--parallel/--no-parallel`、`--list-tests`、`--xunit-output` | 覆盖率、消毒器与按套件选择都无需 `xcodebuild` |
| 模拟器运行时 | 本机**只装了 iOS 26.5 运行时**；watchOS、tvOS、visionOS 需要在 Xcode 里一次性下载 | 命令里的设备名只在该运行时已安装的机器上有效，因此 CI 会先安装它要用的运行时 |
| 设备名 | `xcrun simctl list devices available` | 设备名随运行时变化；本方案只写设备族，每条命令先读已安装列表 |

工具链下限：Xcode 26 或更新，Swift 6.2 或更新。被测部署下限是 macOS 15、iOS 18、watchOS 11、tvOS 18、visionOS 2（PRD §7）。

## 各套件在哪里运行

| 套件 | 被测层 | 夹具 | macOS 15 | iOS 模拟器 | watchOS、tvOS、visionOS |
|---|---|---|---|---|---|
| `Tests/TelnetKitTests/Protocol/` | 经 `@testable import` 测试 `TelnetProtocolCore` | 输入字节，输出 `[TelnetEvent]`；不使用 socket | 是 | 是 | 是，构建并运行 |
| `Tests/TelnetKitTests/PublicAPI/` | 仅经 `import TelnetKit` 测试 `TelnetConnection` | 回环地址上的 `TelnetEchoServer` | 是 | 是 | 仅构建 |
| `Tests/TelnetKitTests/Integration/` | 连接行为：超时、取消、关闭、并发、路径事件 | `NIOTSListenerBootstrap` 起的夹具，以及注入的 `NIOTSNetworkEvents` | 是 | 是 | 否 |

协议套件是正确性关卡且不碰网络，因此它是唯一在所有平台都跑的套件。集成套件要绑定回环监听，而 watchOS、tvOS、visionOS 不提供该语义，所以这些平台止步于构建加协议套件。

## 运行每个套件

所有命令都在包根目录执行。`swift test` 是协议层与公开接口套件的本地证据，两者都能离线完成。

```sh
swift test --filter TelnetKitTests.Protocol        # L1，无网络，信号最快
swift test --filter TelnetKitTests.PublicAPI       # L2，需要回环夹具
swift test --filter TelnetKitTests.Integration     # L3，需要一个空闲本地端口
swift test                                         # 全部套件；必须在 60 s 内结束
swift test --no-parallel                           # 隔离顺序相关的偶发缺陷
swift test --list-tests                            # 列出已有测试，供符号审计使用
swift test --list-tests | wc -l                    # 覆盖率清单核对用的计数
```

回显服务端是夹具而不是服务：集成套件每次运行自己启动一个，并在 teardown 中停掉。

```sh
swift run TelnetEchoServer --port 2323             # 手工：自己启动夹具
swift run TelnetDemo --host 127.0.0.1 --port 2323  # 手工：用 CLI Demo 驱动它
```

模拟器的构建与运行走 `xcodebuild`，因为 SwiftPM 的测试包在这些平台上需要一个宿主应用。

```sh
xcrun simctl list devices available                # 先读已安装的设备名
xcodebuild build -scheme TelnetKit -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test  -scheme TelnetKit -destination 'platform=iOS Simulator,name=iPhone 17' \
                 -only-testing:TelnetKitTests/ProtocolTests
```

`xcodebuild` 只有在包被 Xcode 打开过一次之后才能解析 scheme，因此 CI 在工作区里固定 `TelnetKit-Package` scheme，并在缺少 scheme 时以包名报错退出。

## 覆盖率、消毒器与并发检查

| 检查 | 命令 | 适用范围 | 归属 |
|---|---|---|---|
| 代码覆盖率 | `swift test --enable-code-coverage`，再执行 `xcrun llvm-cov report --instr-profile .build/debug/codecov/default.profdata` | macOS | PRD §8.3：协议层语句 ≥ 90%、分支 ≥ 80% |
| 内存安全 | `swift test --sanitize=address` | macOS | FR-PROTO-08，回调拷贝路径 |
| 数据竞争 | `swift test --sanitize=thread` | macOS | `telnet_t` 单 EventLoop 规则与出站队列 |
| 未定义行为 | `swift test --sanitize=undefined` | macOS | C 接缝与字节运算 |
| 严格并发 | `swift build -Xswiftc -strict-concurrency=complete` | 五个平台 | 零警告；没有注释说明的 `@unchecked Sendable` 一律不接受 |
| 公开接口 | `swift package diagnose-api-breaking-changes baseline.json` | macOS | [符号清单](public-api.md#symbol-checklist) |

消毒器只在 macOS 上跑：iOS 模拟器不支持 Thread Sanitizer，把消毒器与模拟器宿主混在一起只会产生噪声而不是信号。ASan 与 TSan 拆成两个 CI job，避免一个失败掩盖另一个。

## 路径事件与其他时序敏感行为

路径事件与等待连通性是本方案最难的部分，因为托管 CI runner 只有一条网络路径，也无法被要求丢掉它。

| 行为 | 测试方式 | 位置 |
|---|---|---|
| `.pathChanged`、`.betterPathAvailable`、`.betterPathUnavailable`、`.viabilityChanged`、`.waitingForConnectivity` | 向管线注入 `NIOTSNetworkEvents`，断言映射出的 `TelnetEvent` 与被保持不变的选项账本 | 协议套件与集成套件 |
| `waitForConnectivity` 在无路由时挂起连接尝试（FR-PATH-01） | 用 `NIOTSChannelOptions.waitForActivity` 连接不可路由地址，断言调用在限时内既未抛错也未返回，随后释放 | macOS 集成套件 |
| 真实蜂窝↔Wi‑Fi 切换与真实挂起/恢复 | 在设备或模拟器上手工执行，记录进 M6 清单 | M6 手工验收 |
| 超时与取消 | 短的配置上限加宽松的断言上限；绝不使用固定 sleep | 全部套件 |

## 质量门槛

一次变更需要同时满足以下全部条件才算通过，且运行结果要逐条报告观测值：

1. macOS 上 `swift test` 全绿，且在 60 s 内结束。
2. iOS 模拟器上协议层与公开接口套件全绿。
3. 五个平台都能构建。
4. [符号清单](public-api.md#symbol-checklist) 里的每个公开符号都有测试触达；缺一个即判失败，而不是报告"部分覆盖"。
5. PRD §8.3 的覆盖率阈值成立，且与清单核对，而不是只看行数。
6. ASan job 全绿，TSan job 全绿。
7. `-strict-concurrency=complete` 构建零警告。
8. 没有测试访问外网，也没有测试把墙钟 sleep 当作正确性依赖。
9. 依赖树中不含 `NIOSSL`、`CNIOBoringSSL` 与 `NIOPosix`。

## CI 计划

| Job | Runner | 命令 | 覆盖门槛 |
|---|---|---|---|
| `macos-suite` | macOS 15 或更新 | `swift test` 加 `--enable-code-coverage` | 门槛 1、4、5 |
| `sanitizers` | macOS | `swift test --sanitize=address`、`swift test --sanitize=thread` | 门槛 6 |
| `strict-concurrency` | macOS | `swift build -Xswiftc -strict-concurrency=complete` | 门槛 7 |
| `platform-matrix` | 装有全部四个运行时的 macOS | 逐平台执行 `xcodebuild build` 与 `xcodebuild test` | 门槛 2、3 |
| `api-surface` | macOS | `swift package diagnose-api-breaking-changes baseline.json` | 门槛 4 的接口快照部分 |

矩阵 job 会一次性下载并缓存 watchOS、tvOS、visionOS 运行时，且在这些平台上只跑协议套件。运行时下载体积是 [R11 风险](../PRD.md#11-风险与对策) 的成本来源，因此矩阵只在改动 `Sources/` 的 PR 与主分支上运行，而不是每次 push 都跑。

## 手工验收

有三件事无法在托管 runner 上自动化，作为证据记录在里程碑清单中：

1. 通过公网连接真实 Telnet 服务：登录提示可见，命令能往返一次。
2. 在设备上做蜂窝↔Wi‑Fi 切换，观察到 `.pathChanged` 且会话存活。
3. iOS 或 watchOS 上进入后台：连接断开，回到前台后应用重连。
