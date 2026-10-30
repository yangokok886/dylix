<div align="center">

# Dylix

**把插件开发工作台，放进口袋。**

iPhone / iPad 本机构建 · AI 开发助手 · 项目与 Git · 二进制工具

[![License: GPL v3+](https://img.shields.io/badge/License-GPLv3%2B-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-iOS%20%2F%20iPadOS-black.svg)](#构建与安装)
[更新日志](CHANGELOG.md) · [构建文档](docs/BUILDING.md) · [第三方许可](THIRD_PARTY_NOTICES.md) · [问题与建议](https://github.com/yangokok886/dylix/issues)

</div>

## 这是什么

Dylix 是原生 iOS 插件开发工作台：在手机上管理源码、编辑代码、调用内嵌 Clang / LLD 和 Logos，并生成 dylib 与 deb。AI 可以按权限读取头文件、解释代码、修改项目、检查构建结果；编译工作在设备本机完成。

它使用进程内 LLVM 工具链，并非完整 Theos shell 环境。现有 Theos 工程会经过受支持的 Makefile / 配置解析；任意脚本、Xcode 工程和完整 make 语义并不等同于已支持。

## 可以做什么

- **本机构建**：Objective-C、Objective-C++、C、C++、Logos；dylib 与 deb；多种包布局与产物命名。
- **项目与编辑**：模板创建、源码导入、文件浏览、语法着色、查找替换、项目配置、构建诊断及修改备份。
- **AI 工作流**：多连接/多协议、流式 Markdown、代码块、思考与工具过程折叠、编辑重发、会话文件入口。
- **普通会话也能开发**：列出、创建、克隆及选择项目，经目标确认后在原会话中继续编辑与构建。Git、下载、写入等操作遵循当前权限策略。
- **文件与版本管理**：系统分享导入、只读目录授权、附件按需读取；libgit2 本地版本与 GitHub / Gitee 同步。
- **本地分析工具**：IPA Objective-C 头文件导出、Mach-O / dylib 静态信息检查、离线崩溃分析与符号匹配。
- **后台辅助与存储**：系统后台任务、可选音频辅助、完成通知、分类及按文件清理。

## 界面

![开源版设置](docs/images/settings.png)

## 构建与安装

开发主机为 macOS + Xcode / Apple Command Line Tools，另需 Python 3、CMake、Rust stable。
App 最低目标为 iOS 15；部分界面和后台能力按系统版本启用。当前模拟器构建脚本使用 x86_64（Apple Silicon 主机需安装适用的模拟器运行环境或自行扩展架构）。

```sh
git clone https://github.com/yangokok886/dylix.git
cd dylix
python3 scripts/fetch_toolchain.py
# 提供你本地可使用的 Apple SDK：不要将 SDK 提交到 Git。
export DYLIX_SDK_16_4=/absolute/path/iPhoneOS16.4.sdk
export DYLIX_SDK_26_0=/absolute/path/iPhoneOS26.0.sdk
rustup target add aarch64-apple-ios x86_64-apple-ios
python3 scripts/build.py --sdk-root "$DYLIX_SDK_26_0"
```

输出 `build/Dylix-1.0.3-build134-unsigned.ipa`。安装前使用自己的证书/适用安装方式处理主 App、Share Extension 和嵌套 framework 签名。仓库不包含个人证书、描述文件或共享 API 密钥。

**两个 SDK 角色不同**：`--sdk-root` 决定 Dylix App 自身的构建 SDK；内嵌插件构建 SDK 可选 16.4 / 26.0，默认仍为 **SDK 16.4 + 最低 iOS 15**。

完整环境配置、模拟器构建、依赖来源、测试与签名说明见 [docs/BUILDING.md](docs/BUILDING.md)。Apple SDK 是外部输入，不随 Git 源码或公开依赖包发布；本地生成的完整 IPA 会包含你配置的 SDK，请自行核对其分发许可。

## AI、隐私与运行边界

模型连接由用户配置，API 密钥保存在系统钥匙串。发送聊天或调用读取工具时，相应文本会提交到选定模型服务；联网搜索也会访问对应服务。文件夹授权是按需只读访问，不会一开始把全部文件上传。

项目写入、构建和 Git 操作使用注册工具与范围校验；完全访问只针对当前项目。后台运行受 iOS 调度、音频中断、设备资源及用户设置影响，并非永久保活保证。

IPA 导出依据 Objective-C 元数据，不等于还原源码。加密镜像会被识别并跳过；本项目没有通用解密或任意二进制执行入口。编译成功也不证明插件在目标 App 内的运行效果。

**开源版已移除反馈机器人及 Telegram 入口**，设置中的“项目开源地址”打开本仓库。问题与建议请通过 GitHub Issues 提交并先脱敏。

## 许可证与致谢

Dylix 原创代码与修改采用 **GNU General Public License v3.0 or later（GPL-3.0-or-later）**，完整条款见 [LICENSE](LICENSE)。分发修改版或二进制时，请遵循 GPL 对相应源码、许可文本和必要构建材料的要求；软件按现状提供，不附带担保。

第三方代码保留原许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。感谢 LLVM / Clang / LLD、ios_system、Perl、Theos Logos、libgit2、REipa、MBProgressHUD、highlight.js、diff2html 等项目。第三方许可不因本项目采用 GPL 而被替换。

欢迎通过 [贡献说明](CONTRIBUTING.md) 一起改进 Dylix。
