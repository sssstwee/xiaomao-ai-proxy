# FlClash v0.9.2 鸿蒙界面预览

本次预览直接渲染官方 FlClash v0.9.2（上游 `7fd417fb`）的 `HomePage`、`DashboardView`、`ProxiesView`、`ProfilesView` 和 `ToolsView`。没有使用旧版自定义首页，也没有用 AI 绘图或另写示意界面。

## 渲染条件

- Flutter OHOS `3.47.7+ohos-0.0.1-pre`，Dart `3.13.5`。
- Pura X View 截图对应的逻辑尺寸：440 × 744；PNG 输出为 880 × 1488（2 倍像素）。
- 最新界面的浅色主题、简体中文、默认浮动导航。保留原版卡片、图标、四页导航与布局。
- 主题平台设为 `TargetPlatform.ohos`，首页使用独立 `SupportPlatform.HarmonyOS`，工具页使用移动平台参数。宿主仍是 macOS，未将 `dart:io` 的实际系统伪造成鸿蒙。
- 为避免 Flutter 测试字体 Ahem，临时载入宿主 SFNS / STHeiti 字体，并为 Roboto 注册中文字体。字形不是目标手机 HarmonyOS 系统字体的精确复刻。
- 每页用独立 Flutter test 进程渲染，截图与 PNG 编码置于 `tester.runAsync`；完成后再复制到此目录，避免测试引擎图层复用及读取正在写入的图片。

## 示例数据

所有配置名、节点和延迟均为测试假数据。订阅只使用 `example.com` / `example.org`，出口地址为文档保留地址 `203.0.113.10`。住宅类型、质量、流量和节点延迟也由测试提供，不是实测结果。截图没有加载真实订阅、账号或凭证。

- 首页：原版状态与启动按钮、网络速度、规则/全局/直连选择和配置卡片；状态为“未运行”。
- 代理：手动选择与自动测速两个示例分组，显示四个示例节点及模拟延迟。
- 配置：两个远程示例订阅和一个本地示例配置。
- 工具：最近请求、实时连接、DNS 查询、资源、日志、语言、主题、备份与恢复、访问控制等原版入口。日志入口通过现有设置启用。

## 验证

- UI 定向测试 136 项通过：应用访问控制、网络设置、工具移动入口、扫码生命周期、文件读取、滚动、首页布局和导航。
- `file_picker_ohos` 的 5 项通道协议测试通过：真实旧 OHOS map 结构、缓存文件字节/流读取、选择取消、保存文档 URI、空文件分发、保存取消。
- `file_picker_ohos` Dart 分析无问题；Code Forge 两处移动交互平台判断的定向 Dart 分析无问题。
- 四页独立渲染的视图断言通过；PNG 尺寸及实际像素图经检查。
- 本次没有运行客户端 build、打包或安装。这是 Flutter widget 测试预览，尚不能替代新客户端的真机 VPN、系统选择器、权限、扫码摄像头与折叠屏实测。

临时渲染脚本：`/tmp/xiaomao-latest-mobile-preview_test.dart`。定向测试日志：`/tmp/xiaomao-latest-ui-tests-final.log`。独立预览日志：`/tmp/xiaomao-latest-preview-{dashboard,proxies,profiles,tools}-isolated.log`。脚本未加入长期测试或 golden 基线。

## 图片

![首页](previews/latest-home.png)

![代理](previews/latest-proxies.png)

![配置](previews/latest-profiles.png)

![工具](previews/latest-tools.png)
