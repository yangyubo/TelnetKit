# vendored 源码来源

[English](UPSTREAM.md) | 中文

libtelnet 以 git 子模块 `libtelnet/` 的形式进入本包，因此上游源码、上游 `COPYING` 与上游历史都保持发布时的原样，升级也只是切换子模块的 commit 而不是复制文件。本文件记录 pin，并说明我们自己的目录如何访问这些文件。流程见 [.agents/skills/telnetkit-import-c-library/SKILL.md](../../.agents/skills/telnetkit-import-c-library/SKILL.md)。

## 子模块 pin

| 字段 | 值 |
|---|---|
| 上游 | https://github.com/seanmiddleditch/libtelnet |
| 子模块路径 | `libtelnet` |
| URL 记录于 | 包根目录的 `.gitmodules` |
| Commit | `5f5ecee776b9bdaa4e981e5f807079a9c79d633e`，以 gitlink 形式记录在包根 |
| Branch | 克隆时为 `develop` |
| 头文件版本 | `0.23`，取自 `libtelnet.h` 中的 `\version` 标记 |
| 许可证 | 公有领域声明，随子模块以 `COPYING` 提供 |

子模块从不被写入。它内部不生成任何文件，因此 `git -C libtelnet status` 始终干净，升级也不会与本地文件冲突。

## 我们的目录如何访问子模块

SwiftPM 只在 target 的公开头文件目录里寻找自定义 module map，而 SwiftPM 的 `PackageBuilder` 要求该目录位于 target path 之下，同时 `.c` 也从同一个路径编译。因此 target 就是我们自己的 `Sources/CLibTelnet`，子模块文件通过两个已提交的相对符号链接访问：

```text
Sources/CLibTelnet/libtelnet.c                    -> ../../libtelnet/libtelnet.c
Sources/CLibTelnet/include/libtelnet.h            -> ../../../libtelnet/libtelnet.h
Sources/CLibTelnet/include/module.modulemap       我们的文件，纳入版本控制
```

```c
module CLibTelnet {
    umbrella header "libtelnet.h"
    export *
}
```

- 符号链接是相对路径，克隆后无需任何绝对路径即可解析。
- 用 `umbrella header` 而不是 `header`，是为了不偏离 SwiftPM 生成映射时所用的规则；两者在这里都可用，因为映射与头文件同目录。
- `Sources/CLibTelnet/include` 是 clang 的第一个 `-I` 路径，源码中的 `#include "libtelnet.h"` 正是靠它解析。
- 克隆后只需一条命令 `git submodule update --init --recursive`，别无其他：符号链接已纳入版本控制，不存在生成步骤。

## 构建设置

C target 不定义任何自定义宏。`HAVE_ZLIB` 保持未定义，因此 libtelnet 编译时直接去掉 MCCP2 代码，链接期也无需 `-lz`。COMPRESS2 请求会被拒绝，而不是得到半吊子支持；相应行为见 [COMPRESS2 契约](../../docs/public-api.zh.md#事件)。Apple SDK 本可链接 zlib，所以这是设计取舍而非依赖限制。

## 升级清单

1. 在 `libtelnet/` 中拉取上游 remote 并检出目标 commit；然后把新的 commit 与头文件版本记录到本文件。
2. 确认两个符号链接仍能解析，因为新 commit 可能重命名或移动链接所指的文件。
3. 阅读 diff，检查是否有公开签名变更、新增宏、`telnet_event_t` 成员变更，或新增的 `HAVE_ZLIB` 路径；每一项都是 Swift 侧的跟进工作，而不是一次合并冲突。
4. 重跑[引入 skill 的校验](../../.agents/skills/telnetkit-import-c-library/SKILL.zh.md#校验)，然后跑协议套件。
5. 暂存包根目录，使新的 gitlink 与本文件的记录落在同一次提交里。
