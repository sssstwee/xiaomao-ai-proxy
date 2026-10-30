# 小猫代理：FlClash 最新版原生鸿蒙移植

验证日期：2026-10-30。当前完成代码移植、静态检查、可在打包前执行的测试与界面预览。
尚未构建客户端动态库、打包、签名或安装，本记录不代表真机 VPN 已验证。

## 版本与实施方式

| 项目 | 固定基线 |
|---|---|
| 客户端源码 | [FlClash v0.9.2](https://github.com/chen08209/FlClash/releases/tag/v0.9.2)，提交 `7fd417fb9a9a277c6a9339a8ac87f907df7c25f7` |
| 内核 | [Mihomo v1.19.33](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.33)，通过 FlClash 的 `c5062921054902b25215a6a933e72ccd714c9bfa` 集成提交，锁文件核验稳定版祖先及平台补丁 |
| 产品标识 | 小猫代理（暂定），`com.xiaomao.proxy`，`1.0.0+2026103002` |
| 首发设备 | 已只读连接的 HUAWEI Pura X View / VOL-AL00，内部系统 API 26 |
| Flutter | 社区 Flutter-OHOS `3.47.7+ohos-0.0.1-pre`，Dart 3.13.5 |
| 原生工具链 | 固定 OHOS Go 1.26 分支；Rust 1.92.0 的官方 OHOS 目标 |

保留官方最新版的完整手机端架构、仪表盘、代理、配置、工具和编辑器功能，以平台适配接入
鸿蒙。Go Mihomo 继续承担代理和规则执行；C/C++、ArkTS 负责原生 VPN、套接字保护与系统交互；
保留最新版已有的 Rust 编辑器/脚本模块。没有重写代理协议，也没有硬编码业务域名或节点顺序。
既有 backend 源码保留，没有部署或改动线上配置。

## 已完成的验证

| 检查 | 结果 |
|---|---|
| `flutter pub get` | 成功，鸿蒙 Git 依赖已固定为锁文件对应 SHA |
| `flutter analyze --no-fatal-infos` | No issues found |
| 源码秘密扫描与回归 | 2,128 个已暂存文件扫描通过；4 项扫描行为测试、2 个 hook 测试文件通过 |
| 根 Flutter 回归测试 | 4,163 项通过；没有失败文件重跑 |
| 移动界面定向测试 | 136 项通过，涵盖首页导航、仪表盘、网络设置、扫码、工具及平台布局；与根回归有重叠 |
| OHOS 文件选择器 | 5 项真实通道格式测试通过 |
| Core/Dart 定向测试 | 93 项通过；与根回归有重叠 |
| Go | Go 1.26.4 下 portable/OHOS 标签测试、vet 与 Android arm64 cross-vet 通过 |
| 构建工具测试 | 50 项完整构建工具测试通过，没有执行客户端构建 |
| ArkTS VPN 生命周期 | 24 项通过，执行实际 ETS 源码，SDK/通道使用替身 |
| 原生 C/C++ | 当前 cgo 头文件与 OHOS arm64 SDK 的语法检查通过，没有链接客户端库 |
| Rust | OHOS 目标 cargo check 通过；宿主 cargo test --lib 的 60 项通过 |

为遵守打包前确认的要求，测试时临时关闭 Go/Rust 客户端构建 hooks。
`tool/test_without_native_rust.py` 明确列出需要已编译 Rust 客户端动态库的 18 个测试文件，
本轮未运行这些 FFI/编辑器加载集成测试。Rust 算法测试与 OHOS 目标检查不能替代动态库装载验证。
提交的默认 hook 开关保持开启；Actions 在校验及 OHOS 包装全过程使用两个 `false` user-define，
由 setup 显式构建/暂存 OHOS 库。不能依赖被 hook 子进程过滤的环境变量来阻止宿主构建。

## 界面预览

[最新首页](previews/latest-home.png) · [代理](previews/latest-proxies.png) ·
[配置](previews/latest-profiles.png) · [工具](previews/latest-tools.png)

预览来自本次最新源码的 Flutter 界面渲染，按手机尺寸和 OHOS 主题运行。
其中订阅、节点、流量等为示例数据，不能当作手机截图或联网性能证据。
预览生成与平台覆盖说明见 [UI 记录](latest-ui.md)。

## 后续打包与真机验证

仅保留 `.github/workflows/harmony-simple.yml`：PR/push 只验证，`workflow_dispatch` 且为
`main` 才构建 unsigned HAP/APP 并发布 HAP、APP ZIP 与 SHA256SUMS。
用户已于本轮明确授权改造后打包并安装，保留 FlClash 原版 logo、名称为“小猫代理”。
待代码与 CI 验证完成后触发一次该手动流程。

新包名需要匹配的签名 Profile；任务保活权限的 ACL、实际 ArkTS/Hvigor 编译、Go/Rust 库链接与
共同装载、VPN 授权、连接/停止、切网/锁屏、DNS/IPv6 与应用分流均待打包后在目标手机验证。
运行前保留手机现有可用客户端与配置，验证完连接和回滚路径后再切换。
目前没有新客户端的 PSS、CPU、耗电或吞吐测试数据，不能据此承诺内存或性能提升。

细节见 [内核记录](latest-core.md) 与 [原生记录](latest-native.md)。
