# vendored 源码来源

[English](UPSTREAM.md) | 中文

`Sources/CLibTelnet/` 携带一份未经修改的 libtelnet 副本，使 Swift Package 能够构建它。本文件记录 pin 信息，并声明该副本是否与上游存在差异。复制、验证与升级流程见 [.agents/skills/telnetkit-import-c-library/SKILL.md](../../.agents/skills/telnetkit-import-c-library/SKILL.md)。

## Pin

| 字段 | 值 |
|---|---|
| 上游 | https://github.com/seanmiddleditch/libtelnet |
| Branch | `develop` |
| Commit | `5f5ecee776b9bdaa4e981e5f807079a9c79d633e`（2020-08-14） |
| 头文件版本 | `0.23`，取自 `libtelnet.h` 中的 `\version` 标记 |
| 复制的文件 | `libtelnet.c`、`libtelnet.h` |
| 目标位置 | `libtelnet.c`；`include/libtelnet.h` |
| 许可证 | 公有领域声明，取自上游 `COPYING` 文件 |

## 本地修改

无。副本落地后，两个文件与 pin 住的 commit 处的上游逐字节一致，且每个文件的 SHA-256 摘要与上游检出结果相同。

`include/module.modulemap` 由我们提供，不属于上游：

```c
module CLibTelnet {
    header "libtelnet.h"
    export *
}
```

## 构建设置

C target 不定义任何自定义宏。`HAVE_ZLIB` 保持未定义，因此没有 MCCP2 支持，COMPRESS2 请求会被拒绝，而不是得到半吊子支持。相应行为见 [COMPRESS2 契约](../../docs/public-api.md#事件)。

## 升级清单

1. 拉取上游，把新的 commit 与头文件版本记入 pin 表。
2. 对两个文件做 diff，检查是否有公开签名变更、新增宏、`telnet_event_t` 成员变更，或新增的 `HAVE_ZLIB` 路径。
3. 复制两个文件，确认没有重新引入本地修改。
4. 重跑[引入 skill 的校验](../../.agents/skills/telnetkit-import-c-library/SKILL.md#校验)，然后跑协议套件。
