---
name: telnetkit-import-c-library
description: 在 TelnetKit Swift 包中 vendor、pin、验证或升级 libtelnet C 源码，并修复 Swift 与 C 接缝上的故障。用于新增 Sources/CLibTelnet、记录或更换上游 commit、编写 include/module.modulemap、复现 libtelnet 行为，或诊断 C 头文件与 Swift 封装不一致的问题。
---

# 引入 libtelnet C 库

[English](SKILL.md) | 中文

## 概要

`Sources/CLibTelnet` 携带一份未经修改的 [seanmiddleditch/libtelnet](https://github.com/seanmiddleditch/libtelnet) 副本，使 Swift Package 能够构建它。本工作流覆盖复制、module map、来源记录、Swift 接缝与升级流程。它是有固定验证路径的指导，不是生成器：在手写路径被评审过一次之前，不要为复制过程写脚本。

## 目录

- [约束复制的既定事实](#约束复制的既定事实)
- [工作流：首次 vendoring](#工作流首次-vendoring)
- [工作流：升级 pin](#工作流升级-pin)
- [编写 Swift 接缝](#编写-swift-接缝)
- [规则](#规则)
- [校验](#校验)
- [Dev Note](#dev-note)

## 约束复制的既定事实

对照上游 `develop` 分支、commit `5f5ecee776b9bdaa4e981e5f807079a9c79d633e`（2020-08-14）、头文件版本 0.23 已验证：

- 上游仓库没有 `Package.swift`。`libtelnet.c` 与 `libtelnet.h` 就是整个库；`CMakeLists.txt`、autotools 文件、`test/`、`doc/`、`util/` 都不需要，也不得复制。
- C 源码用 `clang -c libtelnet.c -I include -Wall` 编译无警告，并导出 23 个 `telnet_*` 符号。
- `libtelnet.c` 有一个位于 `HAVE_ZLIB` 之后的可选依赖，用于 MCCP2。不要定义它：压缩支持不在范围内，且 Swift 代码必须以 `wont` 回应 COMPRESS2 请求。
- `libtelnet.h` 声明为 `public domain`。在声明文件中记录这一点；不要把我们的许可证附到 vendored 文件上。
- 有三项能力是宏，因此对 Swift 不可见：`telnet_finish_sb`、`telnet_finish_newenviron`、`telnet_finish_zmp`。接缝要补齐这三者。
- 上游不导出任何协商选项状态的查询。Swift 层维护自己的账本；绝不要新增伸手读 `struct telnet_t` 的 C 辅助函数。

## 工作流：首次 vendoring

1. 在仓库之外克隆上游并 pin 到指定 commit：`git clone https://github.com/seanmiddleditch/libtelnet.git`，再 `git checkout <commit>`。
2. 只复制两个文件：`libtelnet.c` 到 `Sources/CLibTelnet/libtelnet.c`，`libtelnet.h` 到 `Sources/CLibTelnet/include/libtelnet.h`。不要重排格式，不要加许可证头，不要打补丁。
3. 写入 `Sources/CLibTelnet/include/module.modulemap`，内容为 `module CLibTelnet { header "libtelnet.h" export * }`。
4. 写入 `Sources/CLibTelnet/UPSTREAM.md`，包含上游 URL、branch、完整 commit 标识、头文件版本、复制日期，以及一句声明不存在本地修改的话。
5. 在 `Package.swift` 中声明 target：`.target(name: "CLibTelnet")`，不加任何自定义 C 设置，并且不放进 `products`。
6. 首次构建之前，用 `shasum -a 256` 比对两侧，确认副本与上游逐字节一致。
7. 执行[校验](#校验)步骤。

## 工作流：升级 pin

1. 拉取上游，确定新的 commit 与头文件版本。
2. 把两个文件与 vendored 副本做 diff，并把结果记入变更说明。
3. 阅读 diff，留意公开签名变更、新增宏、`telnet_event_t` 成员变更，或新增的 `HAVE_ZLIB` 路径。每一项都是 Swift 侧的跟进工作，而不是一次合并冲突。
4. 复制文件、更新 `UPSTREAM.md`，并执行完整校验。
5. 重跑协议套件。`libtelnet.c` 的行为变更会表现为协议测试失败；选项表变更会表现为协商测试期望值变化。只有当新行为符合测试所引用的 RFC 时才修改期望值。

## 编写 Swift 接缝

只有一个文件导入 `CLibTelnet`：`Sources/TelnetKit/Protocol/TelnetProtocolCore.swift`。其他任何文件都不导入。

1. 把选项表构造为 `[telnet_telopt_t]`，以一个 `telopt` 为 `-1` 的条目结尾，然后在 `withUnsafeBufferPointer` 内调用 `telnet_init`，使该表的生命周期只覆盖这次调用。
2. 用 `Unmanaged.passUnretained(self).toOpaque()` 把拥有者对象作为 `user_data` 传入。持有引用会让 core 在 `telnet_free` 之后仍然存活。
3. 在回调内用 `Unmanaged<TelnetProtocolCore>.fromOpaque(user).takeUnretainedValue()` 取回 core，并对 `event.pointee.type` 做 switch。立即拷贝每个 buffer、字符串与参数数组；这些指针在回调返回时失效。
4. 用 `telnet_iac(handle, TELNET_SE)` 调用替代那三个宏。
5. 在拥有它的 EventLoop 上，从 deinit 或关闭路径中恰好释放一次 handle，并把 handle 置为 nil，使第二次调用不可能重复释放。
6. 通过拷贝 `file`、`func`、`msg`、`err` 来映射 `TELNET_EV_WARNING` 与 `TELNET_EV_ERROR`。

## 规则

- vendored 文件只读。需要改变行为时改 Swift 代码；怀疑上游有缺陷时报告并记录到 `UPSTREAM.md`，而不是就地打补丁。
- 不允许其他文件导入 `CLibTelnet`。当第二个文件需要协议数据时，扩展 core 的 Swift 接口。
- 不要在回调内调用 `telnet_send*`。追加到出站队列，在 `telnet_recv` 返回后 flush。
- 不要读取当前事件类型未选择的 union 成员。读取以该事件命名的成员。
- 不要定义 `HAVE_ZLIB`。Apple SDK 自带 zlib，所以这是设计取舍而非依赖限制。开关关闭时 libtelnet 会把 MCCP2 代码整段编译掉：COMPRESS2 请求以 `wont` 应答，而未协商就到达的压缩载荷会被当作应用数据，不会被识别为违规。

## 校验

按顺序执行并保留观测输出：

1. 对 vendored 文件执行 `shasum -a 256`，与记录 commit 处的上游检出结果一致。
2. `swift build` 成功，且 C target 没有任何警告；同一 target 在 iOS 18 模拟器下限下也能构建。
3. `swift test --filter TelnetKitTests.Protocol` 通过，包括协商事件与字节转义用例。
4. 一个接缝测试喂入 `FF FB 01`（IAC WILL ECHO）再喂 `68 69 0D 0A`，断言先收到一条 `.negotiation` 事件，随后是 `.data("hi\r\n")`。
5. 一个接缝测试在已协商 ECHO 的前提下，经公开路径调用 `telnet_send_text` 发送 `hi\n`，断言出站字节包含 `IAC DO ECHO` 并完成 CR LF 转换。
6. 一个关闭测试释放 handle，并断言不再有任何事件到达回调。

## Dev Note

None.
