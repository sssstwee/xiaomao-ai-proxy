# 最新 FlClash 鸿蒙移植：原生验证记录

日期：2026-10-30。验证对象为 `codex/flclash-latest-harmony` 中以官方 FlClash v0.9.2
（`7fd417fb`）为基础的源码，不能以旧 PR #38 的 CI 结果替代本次验证。

## 工具链与范围

- Flutter-OHOS 3.47.7 预览工具链，固定提交
  `650641656fef1d0578f0bc1ed8f7a35087fc99f3`，Dart 3.13.5。
- Rust 1.92.0，OHOS 脚本默认固定该版本，已安装官方 `aarch64-unknown-linux-ohos` 标准库。
- 首发设备为 Pura X View / VOL-AL00，既有设备读数为 API 26。
- 本轮只验证源码、测试程序和目标平台类型；没有执行客户端 `.so` 构建、HAP/APP 打包、
  签名、安装、设备 VPN 切换或发布。

## 已执行的检查

| 命令或检查 | 结果 |
|---|---|
| `node --test test/native/harmony_vpn_test.cjs` | 24 项通过 |
| `bash plugins/rust_api/tool/ohos_rust.sh check` | OHOS 目标 `cargo check --locked` 通过，包含 rquickjs bindgen |
| `cargo test --locked --manifest-path plugins/rust_api/rust/Cargo.toml --lib` | 宿主测试二进制的 60 项测试通过 |
| `cargo fmt --manifest-path plugins/rust_api/rust/Cargo.toml -- --check` | 通过 |
| `bash -n plugins/rust_api/tool/ohos_rust.sh` | 通过 |
| `dart analyze lib/plugins/app.dart plugins/rust_api/lib/rust_api.dart plugins/rust_api/lib/src/initialize.dart plugins/rust_api/lib/src/initialize_io.dart plugins/rust_api/hook/build.dart lib/main.dart` | Dart 3.13.5：No issues found |
| `git diff --check`（原生、Rust、main 与相关适配文件） | 通过 |

另在临时目录运行 `go tool cgo -objdir <临时目录> main.go`，取得当前
`core/ohos/main.go` 的真实 `_cgo_export.h`，作为 `libclash.h` 使用。随后使用 OHOS
SDK clang 的 `--target=aarch64-linux-ohos --sysroot=<SDK>/native/sysroot -fsyntax-only`
检查 `core/ohos/bridge.c`（C11）与 `ohos/core/src/main/cpp/napi_init.cpp`（C++17），均通过。
这没有生成或链接客户端库。

Rust 宿主测试仅验证编辑器、脚本、键码转换和唯一临时 socket 的 IPC 行为，不注册系统快捷键。
检查产物目录后未发现 `librust_api.so`、`librust_api.dylib` 或 `librust_api.a` 客户端库。

## 原生契约覆盖

- 使用最新版 `/core` 通道的 `invokeMethod`，响应和事件均为 UTF-8 字节，保持
  `CoreMethodCall` / `CoreMethodResponse` 结构，事件批次不重复编码。
- 移动端 start/stop 返回值表示接受操作意图；原生失败用 `stopped(revision)` 回报。
  过期回调不能覆盖新命令，未完成的启动在更新意图后取消并清理；运行时间读取等待队列稳定。
- Go C ABI 与 NAPI 分别传递 socket 保护结果、UID 和包名。保护失败向 Go 返回 false；
  UID 查询失败返回 -1，包名失败返回空字符串。
- 最新 `mtu`、`congestionController` 传至 Go；NetworkKit MTU 与 Go TUN 使用相同值，
  平台范围限制为 576–1500，IPv6 下限为 1280，默认 1500。
- 物理网络切换调用最新版 `resetNetwork`，即使 DNS 地址未变化也能触发。
- 保留轻量 shared-state 同步未携带的 setup 参数，供原生恢复使用。
- 覆盖启动失败、启动期间停止/销毁、异步 TUN 清理、重复操作、观察者重连、RPC 半包清理、
  后台任务取消、重启定时器清理，以及停止后不再发布过期通知。

## 包装入口与依赖审查

- 仅保留 `.github/workflows/harmony-simple.yml`；PR/push 运行检查，客户端包与 Release
  限定为 `workflow_dispatch` 且分支为 `main`。校验阶段临时关闭 setup/rust native-assets
  构建 hooks；普通源码中的默认值仍保持开启。
- OHOS 授权构建须在进入 Dart 包装入口前将 setup/rust 两个 `build_assets` 设为 `false`，
  并在整个 Flutter HAP/APP 流程中保持关闭。Dart hooks 会过滤非白名单环境变量，
  `FLCLASH_OHOS_BUILD` 不能作为禁止隐式宿主构建的可靠开关。OHOS 包装通过显式 Go/Rust
  构建流程暂存库，随后运行 Flutter HAP/APP；其他平台继续使用上游 hooks。
- setup-ohos v2.0.0 导出 `HOS_SDK_HOME=…/command-line-tools/sdk`；原生测试 resolver 和
  Rust SDK 脚本均识别 `default/openharmony` 路径。
- `libclash.so` 暂存于 `ohos/core/libs/arm64-v8a`，`libclash.h` 与 `bridge.h`
  暂存于 core 的 `cpp/includes/arm64-v8a`。缺少库或头文件时 CMake 失败，不生成空壳 core。
- `librust_api.so` 暂存于 `ohos/entry/libs/arm64-v8a`；OHOS 通过
  `initializeRustApi()` 显式打开同名库，其他平台保留原初始化。没有手改 FRB 生成代码。
- 已移除 core HAR 指向旧 `plugins/setup/buildkit` 的失效 Hvigor 插件入口。
- 已阅读固定 Flutter-OHOS 源码：HAP/APP 均支持 `--no-codesign`，默认目标为
  `ohos-arm64`，默认 unsigned 文件名分别为 `entry-default-unsigned.hap` 与
  `ohos-default-unsigned.app`。当前 setup 输出和 Release APP ZIP/校验文件流程与之匹配。

## 明确的验证边界

- Node 测试执行实际 `.ets` 源码，但 SDK 和 Flutter 通道使用替身；不替代正式 ArkTS/Hvigor
  编译、库链接、HAP 中动态库依赖核验或真机运行。
- `cargo check` 不验证最终 `librust_api.so` 的链接、装载及其与 Go 运行时的共存。
  编辑器与脚本的 Rust 算法测试通过，也不等同于 Flutter 到 Rust 的真机 FFI 验证。
- unsigned HAP 不能直接作为可安装产品。独立包名 `com.xiaomao.proxy` 需要匹配的新签名
  Profile；旧 CC保镖 的包名、数据目录和签名适用性不能直接沿用。
- 当前 `TASK_KEEPING` 在手机上需要 `KEEP_BACKGROUND_RUNNING_SYSTEM` 的 ACL。
  [官方权限说明](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/security/AccessToken/restricted-permissions.md#ohospermissionkeep_background_running_system)
  将其列为 `system_basic` / `system_grant`，SDK 注释也明确非 PC 设备的 ACL 要求。
  本轮只完善既有权限用途说明，未增删权限或改变后台策略；新包名能否取得该权限、锁屏后台持续性
  和 VPN 被系统回收后的恢复能力，仍须在授权签名与真机测试时核验。
- 后续真机应对照相同配置验证连接/停止、切网、锁屏、DNS/IPv6、应用分流及原生/兼容环境应用，
  并测量 PSS、CPU、恢复耗时和耗电；本轮不宣称已有性能提升数据。
