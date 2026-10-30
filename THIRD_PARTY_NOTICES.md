# 第三方组件与许可证

本清单与 App 内的 `Resources/ThirdPartyNotices/` 一同保留。各组件维持原版权；GPL 仅适用于本项目有权许可的原创部分。

- **LLVM** — Apache-2.0 with LLVM exceptions。https://github.com/llvm/llvm-project/tree/llvmorg-14.0.0；许可文本：[`llvm-LICENSE.txt`](Resources/ThirdPartyNotices/llvm-LICENSE.txt)。
- **Clang** — Apache-2.0 with LLVM exceptions。https://github.com/holzschu/llvm-project；许可文本：[`clang-LICENSE.txt`](Resources/ThirdPartyNotices/clang-LICENSE.txt)。
- **LLD** — Apache-2.0 with LLVM exceptions。https://github.com/holzschu/llvm-project；许可文本：[`lld-LICENSE.txt`](Resources/ThirdPartyNotices/lld-LICENSE.txt)。
- **ios_system** — BSD-3-Clause。https://github.com/holzschu/ios_system；许可文本：[`ios_system-LICENSE.txt`](Resources/ThirdPartyNotices/ios_system-LICENSE.txt)。
- **Perl 5.34.0** — Artistic 1.0 / GPL（见原文）。https://github.com/holzschu/perl5；许可文本：[`perl-artistic-LICENSE.txt`](Resources/ThirdPartyNotices/perl-artistic-LICENSE.txt)。
- **Perl GPL 文本** — GPL（Perl 双许可证选项）。https://github.com/holzschu/perl5；许可文本：[`perl-LICENSE.txt`](Resources/ThirdPartyNotices/perl-LICENSE.txt)。
- **Theos Logos** — GPL-3.0-or-later。https://github.com/theos/logos；许可文本：[`Logos-LICENSE.txt`](Resources/ThirdPartyNotices/Logos-LICENSE.txt)。
- **highlight.js** — BSD-3-Clause。https://github.com/highlightjs/highlight.js；许可文本：[`highlight.js-LICENSE.txt`](Resources/ThirdPartyNotices/highlight.js-LICENSE.txt)。
- **MBProgressHUD** — MIT。https://github.com/jdg/MBProgressHUD；许可文本：[`MBProgressHUD-LICENSE.txt`](Resources/ThirdPartyNotices/MBProgressHUD-LICENSE.txt)。
- **libarchive（系统组件）** — BSD 及文件级许可（见原文）。https://github.com/libarchive/libarchive；许可文本：[`libarchive-LICENSE.txt`](Resources/ThirdPartyNotices/libarchive-LICENSE.txt)。
- **libgit2 1.9.7** — GPL-2.0-only with linking exception。https://github.com/libgit2/libgit2/tree/v1.9.7；许可文本：[`libgit2-LICENSE.txt`](Resources/ThirdPartyNotices/libgit2-LICENSE.txt)。
- **diff2html 3.4.55** — MIT。https://github.com/rtfpessoa/diff2html/tree/3.4.55；许可文本：[`diff2html-MIT.txt`](Resources/ThirdPartyNotices/diff2html-MIT.txt)。
- **jsdiff（diff2html 内含）** — BSD-3-Clause。https://github.com/kpdecker/jsdiff/tree/7.0.0；许可文本：[`jsdiff-LICENSE.txt`](Resources/ThirdPartyNotices/jsdiff-LICENSE.txt)。
- **Hogan（diff2html 内含）** — Apache-2.0。https://github.com/twitter/hogan.js；许可文本：[`hogan-LICENSE.txt`](Resources/ThirdPartyNotices/hogan-LICENSE.txt)。
- **AI 模块与研究参考** — 独立原生实现 · 上游许可见说明。https://github.com/cline/cline；许可文本：[`AI-Research.txt`](Resources/ThirdPartyNotices/AI-Research.txt)。
- **REipa 0.1.0** — MIT。https://github.com/JRBusiness/REipa；许可文本：[`REipa-MIT.txt`](Resources/ThirdPartyNotices/REipa-MIT.txt)。
- **Rust standard library 1.99.1** — MIT / Apache-2.0（依赖归属见完整清单）。https://github.com/rust-lang/rust/tree/1.99.1；许可文本：[`Rust-LICENSE.txt`](Resources/ThirdPartyNotices/Rust-LICENSE.txt)。
- **thiserror 与 Rust 宏依赖** — MIT / Apache-2.0 / Unicode-3.0（见原文）。https://github.com/dtolnay/thiserror；许可文本：[`REipa-Rust-Dependencies.txt`](Resources/ThirdPartyNotices/REipa-Rust-Dependencies.txt)。
- **iOS tweak development 指南** — MIT。https://github.com/liamschwie/skills/tree/main/skills/ios-tweak-development；许可文本：[`ios-tweak-skills-LICENSE.txt`](Resources/ThirdPartyNotices/ios-tweak-skills-LICENSE.txt)。
- **Cydia Substrate compatibility header** — BSD-style (see header)。https://github.com/theos/headers；许可文本：[`CydiaSubstrate-header.txt`](Resources/ThirdPartyNotices/CydiaSubstrate-header.txt)。

## 本地修改与归属

- REipa 固定上游 revision `b0d4759451ed20796892a059fa53d9dbb130af61`，包含本地边界检查/大镜像/增量导出修改；详情见 Vendor/REipa/README-TweakForge.md，源码完整保留。
- libgit2 完整来源及 COPYING 在 Vendor/libgit2；其 GPLv2 linking exception 不将 Dylix 主程序强制改为 GPLv2。
- Logos 的实际源码在 Resources/logos，使用 GPL-3.0-or-later。
- 原生 AI 交互研究参考不代表复制代码或链接其运行时，见 AI-Research.txt；另参考 OpenMinis（https://github.com/OpenMinis/OpenMinis）的流式呈现与生命周期设计，Dylix 使用自己的 UIKit 实现。
- Apple SDK 与 Apple 系统 framework 是外部输入/系统组件，不包含在开源仓库的许可授权中。
- 未分发个人 FLEX 测试样例、参考 macOS Perl 副本、设备日志、模型会话或用户附件。

## 预编译工具链

Release 的工具链包包含 ios_system、LLVM/Clang/LLD、Perl 对应 xcframework 和许可证。来源、版本与包/文件摘要见 dependencies.lock.json；它不包含 Apple SDK。Apache/BSD/Artistic 等第三方组件继续适用原条款。
