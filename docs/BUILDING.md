# 构建 Dylix

## 目录与前提

- `App/`：UIKit 编辑器、项目/存储/Git/AI/编译桥。
- `ShareExtension/`：系统分享入口；`LiveActivityExtension/`：活动扩展资源。
- `Vendor/`：libgit2、REipa 子集和 Rust 桥、MBProgressHUD、兼容头文件。
- `Resources/`：Logos/Perl、Clang 资源头、编辑器素材、示例、许可。
- `scripts/`、`tests/`：构建与回归。`build/` 是忽略的本地产物。

要求 macOS、Xcode/Command Line Tools、Python3、CMake、Rust stable。运行 `xcode-select -p` 和 `xcrun --show-sdk-path` 确认 Apple 工具链。源码没有 `.xcodeproj`：使用 Python 构建入口。

## 1. 工具链

`python3 scripts/fetch_toolchain.py` 下载本仓库 Release 中校验过 SHA-256 的预编译框架，解到 `Vendor/`；下载包不含 Apple SDK。也可设置 `DYLIX_TOOLCHAIN_ROOT` 到另一个包含 `Vendor/*.xcframework` 的目录。

LLVM/Clang/LLD 14 来源为 holzschu/llvm-project；ios_system 3.0.5、Perl 5.34.0 来源见第三方清单。下载脚本只安装数据，不执行外部安装脚本。版本与每个框架文件摘要在 `dependencies.lock.json`。二进制依赖沿用各自许可。

## 2. Apple SDK

分别设置：

```sh
export DYLIX_SDK_16_4=/absolute/path/iPhoneOS16.4.sdk
export DYLIX_SDK_26_0=/absolute/path/iPhoneOS26.0.sdk
```

两者须含 SDKSettings.plist，实际 Version 应为16.4/26.0。SDK 内容不在本仓库中；请通过你可使用的 Apple 开发环境和适用条款准备。构建时会校验元数据并压缩内嵌，默认插件 SDK16.4、最低 iOS15。

## 3. Rust 与 CMake

```sh
rustup target add aarch64-apple-ios x86_64-apple-ios
cmake --version
cargo +stable --version
```

CMake 可用 `TMC_CMAKE` 指定可执行文件。Rust 桥使用 Cargo.lock 固定依赖；首次构建需下载 crates。libgit2 使用 SecureTransport，不启用 SSH CLI。

## 4. 构建

```sh
# 真机 App，以 iOS26 SDK 编译 Dylix 本身
python3 scripts/build.py --sdk-root "$DYLIX_SDK_26_0"
# 模拟器，当前实现为 x86_64
python3 scripts/build.py --simulator
```

模拟器构建使用 Xcode 当前 Simulator SDK；不把 device SDK 传给 `--simulator`。构建输出 `build/device/`、`build/simulator/` 和根下 IPA。签名参数 `--identity`、`--profile`、`--share-profile` 见 `python3 scripts/build.py --help`；实际证书和 provisioning profile 必须匹配主应用及分享扩展标识、App Group。adhoc IPA 仍需签名/适用安装方式。

## 5. 验证

```sh
python3 scripts/test_developer_prompt.py
python3 scripts/test_git.py
python3 scripts/test_package_schemes.py
```

完整测试入口见 scripts/、tests/。iOS 原生回归通过模拟器启动参数运行，例如 `--ai-render122-test`、`--ai-workspace133-test`、`--ai-v2-test`；测试使用本地样本和保留的 `.invalid` 域名拦截，不需要真实模型密钥。模拟器测试必须在一次性测试安装中执行，部分夹具会重置它们自己的样例会话。

部分历史压力脚本引用未随开源版分发的个人 FLEX 测试工程。它不是 Dylix 的运行依赖，请自行提供相应测试夹具或只运行内置基础样例；仓库不包含其代码和二进制。

## 发布材料

公开源码与工具链资产不包含 SDK、证书、用户数据或旧构建。GPL 原创代码、Logos 等对应源码与构建脚本均随仓库提供；第三方许可见仓库及 App 内说明。外部 Apple SDK 与系统库仍受其各自条款约束。
