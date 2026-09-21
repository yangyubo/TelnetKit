# vendored 源码来源

[English](UPSTREAM.md) | 中文

libtelnet 以 git 子模块 `libtelnet/` 的形式进入本包，因此上游源码、上游 `COPYING` 与上游历史都保持发布时的原样，升级也只是切换子模块的 commit 而不是复制文件。本文件记录 pin，并说明我们往子模块里添加了什么。流程见 [.agents/skills/telnetkit-import-c-library/SKILL.md](../../.agents/skills/telnetkit-import-c-library/SKILL.md)。

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

## 我们往子模块里添加了什么

只有一个文件，由 [.doc-tools/prepare-libtelnet.sh](../../.doc-tools/prepare-libtelnet.sh) 写出，且不提交到任何仓库：

```text
libtelnet/include/module.modulemap     在子模块中处于未跟踪状态，因此不会弄脏 pin
```

```c
module CLibTelnet {
    header "../libtelnet.h"
    export *
}
```

SwiftPM 从 target path 编译 `.c`，并要求公开头文件位于该路径之下，所以映射文件写在这里而不是我们自己的目录里。

有两个细节决定它能否构建：

- `header` 路径相对于 module map 本身，而不是相对于 include 搜索路径，因此这里必须写 `../libtelnet.h`。写成裸的 `libtelnet.h` 会报 `header 'libtelnet.h' not found`。
- `libtelnet/include` 是 clang 的第一个 `-I` 路径，映射文件正是靠它找到同级的头文件。

任何克隆都必须在 `git submodule update --init --recursive` 之后执行一次 `./.doc-tools/prepare-libtelnet.sh`。脚本是幂等的，并在子模块缺失时明确报错。

## 构建设置

C target 不定义任何自定义宏。`HAVE_ZLIB` 保持未定义，因此 libtelnet 编译时直接去掉 MCCP2 代码，链接期也无需 `-lz`。COMPRESS2 请求会被拒绝，而不是得到半吊子支持；相应行为见 [COMPRESS2 契约](../../docs/public-api.zh.md#事件)。Apple SDK 本可链接 zlib，所以这是设计取舍而非依赖限制。

## 升级清单

1. 在 `libtelnet/` 中拉取上游 remote 并检出目标 commit；然后把新的 commit 与头文件版本记录到本文件。
2. 重新执行 `./.doc-tools/prepare-libtelnet.sh`，因为新 commit 可能重命名或移动头文件。
3. 阅读 diff，检查是否有公开签名变更、新增宏、`telnet_event_t` 成员变更，或新增的 `HAVE_ZLIB` 路径；每一项都是 Swift 侧的跟进工作，而不是一次合并冲突。
4. 重跑[引入 skill 的校验](../../.agents/skills/telnetkit-import-c-library/SKILL.zh.md#校验)，然后跑协议套件。
5. 暂存包根目录，使新的 gitlink 与本文件的记录落在同一次提交里。
