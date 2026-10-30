# 小猫代理 1.0 代码与验证记录

日期：2026-10-30（Asia/Shanghai）。目标：HUAWEI Pura X View，VOL-AL00，设备报告 OpenHarmony 7.0.0.111 / API 26。

## 交付范围

- 应用名称“小猫代理”，独立标识 `com.xiaomao.proxy`，版本 `1.0.0+2026103001`，与旧 CC保镖分开安装和存储。
- 首页、代理、配置、工具四个入口；通用订阅、本地文件/二维码导入、手动节点选择、日志与连接列表。
- 配置与节点选择跨重启保留；托管更新只修改其拥有的配置，不抢占用户当前选择，不按显示名称删除用户文件。
- 路由、DNS与故障切换由当前配置管理；鸿蒙隐藏不生效的本地覆写入口。
- 固定 Mihomo v1.19.33，复用 FlClash v0.9.2 的兼容接口；精确提交、OHOS补丁和SHA256见 `core/mihomo.lock.json` 与 `core/README.md`。
- 原生启动等待真实结果，失败回滚监听；配置无响应和明确错误均不会启动VPN。修复停止/销毁竞态、后台任务与订阅清理、跨语言字符串所有权和JS线程同步等待风险。

## 代码验证

- Flutter 3.44.10 / Dart 3.12.2，使用固定的社区OHOS工具链；依赖安装、国际化及Riverpod/模型代码生成完成。
- `flutter analyze --no-pub --no-fatal-infos`：No issues found。
- `flutter test --no-pub --reporter expanded`：680项通过（含内核接口与生命周期21项、源码准备6项及32项手机UI测试）。
- `node --test test/native/harmony_vpn_test.cjs`：18项通过，直接转译执行生产ArkTS逻辑并模拟平台SDK，不生成客户端。
- `python3 -m unittest discover -s test/ci -v`：6项通过。
- Go 1.26.4：`CGO_ENABLED=0 go test -mod=readonly -tags=with_gvisor ./...`、OHOS标签DNS测试、`go vet`、`go mod verify`通过；Go 1.24.3兼容探测通过。
- NAPI使用OHOS arm64 clang进行 `-fsyntax-only` 检查通过。此检查使用临时C ABI声明，不能替代真实Go共享库链接及HAP编译。
- 在全新远程克隆上验证固定提交、stable祖先、补丁准备/校验/逆向，并确认子模块恢复干净。
- CI保留只有用户授权后的 `workflow_dispatch` 且位于 `main` 才构建/上传/发布客户端的门禁；PR和push仅做代码检查。

## 性能与语言选择

本轮选择继续使用Go Mihomo、Flutter界面与ArkTS/C++薄桥。以下是结合项目结构的工程判断，未声称完成跨语言性能跑分：

| 层次 | 当前选择 | 判断依据 |
|---|---|---|
| 代理数据平面 | Go Mihomo | 直接复用上游协议与规则实现，持续跟进最新稳定版；重写为Rust/C++会变成不同内核项目。 |
| 鸿蒙系统入口 | ArkTS | 调用平台VPN、网络、电源与后台任务接口。 |
| 原生桥接 | 保留精简C++ | 已有实现，优先修复字符串所有权、回调队列和阻塞清理；增加Rust层不能消除Go和Flutter运行时。 |
| 手机界面 | Flutter | 复用FlClash功能与测试，开发和维护投入较低；如以后只面向鸿蒙且实测界面引擎成为主要内存瓶颈，再对比ArkUI原生界面。 |

旧版真机单次只读基线（CC保镖 0.8.94+2026102703，负载未控制）：界面进程RSS 195592 KiB（约191 MiB），VPN进程RSS 481992 KiB（约471 MiB）。RSS含共享页，不能相加作为应用总占用；未获得可用PSS，未把VSZ当实际内存。该数据不能用于宣称新版本更省内存或某种语言更快。

授权打包后，用相同配置、节点、设备与负载，分别测冷启动、静置、锁屏、持续传输和反复切网场景的PSS、Go堆、CPU、耗电、连接恢复耗时与资源增长；再决定缓存、回收策略、轮询频率或界面技术是否需要调整。本轮未调整生产路由、GC参数或线上DNS。

参考：[Go GC指南](https://go.dev/doc/gc-guide)、[Flutter内存分析](https://docs.flutter.dev/tools/devtools/memory)、[Flutter性能实践](https://docs.flutter.dev/perf/best-practices)。

## 可审阅预览

[首页预览](previews/home.png)与[代理预览](previews/proxies.png)由Flutter widget测试渲染，逻辑尺寸440×744，输出880×1488。节点、延迟与流量均为明确标注的假数据；不是新客户端真机运行截图。

## 尚需授权打包后的真机验收

本轮未构建 `.so`、HAP或APP客户端产物，也未安装新版本。尚需验证实际ArkTS/HAP编译与签名、Go共享库ABI、手机VPN系统弹窗、真实应用访问、IPv6/DNS走向、Wi-Fi/蜂窝切换、锁屏后台、长时间资源变化及升级/共存流程。新包发布时应包含HAP、APP ZIP与SHA256SUMS。
