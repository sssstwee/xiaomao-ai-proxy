# EdgeTunnel 托管订阅分流

`acl4ssr.ini` 沿用 [cmliu 的 ACL4SSR Mini MultiMode CF 配置](https://github.com/cmliu/ACL4SSR/blob/main/Clash/config/ACL4SSR_Online_Mini_MultiMode_CF.ini)，仅通过 subconverter 原生 `clash_rule_base` 指向 `clash-base.yaml`。规则列表继续引用 ACL4SSR，节点和凭据继续由 EdgeTunnel 生成。

DNS 使用 [MetaCubeX/meta-rules-dat](https://github.com/MetaCubeX/meta-rules-dat) 维护的 `cn`、`private` MRS 域名集合，每天更新。匹配国内或私有域名时用直连的阿里／腾讯 DoH；其余域名默认通过 `☁️ CloudFlareCDN` 查询 Cloudflare／Google DoH。已知 AI 域名显式优先于国内集合。没有国内默认查询后再选择境外 fallback 的路径。

节点域名使用独立的 `proxy-server-nameserver`，避免解析依赖代理、代理又依赖解析的循环。`default-nameserver` 只负责解析 DNS 服务本身的域名。EdgeTunnel 仍可按后台 ECH 设置加入 Worker 与 ECH 查询域名的策略。

`direct-nameserver` 为实际选择直连的连接单独使用国内 DoH，且不跟随通用 DNS 策略，避免国内直连域名未命中域名集合时仍绕经境外解析。

这份 EdgeTunnel 订阅的节点未启用 UDP，规则首项拒绝 UDP 443，让 QUIC 回退到 TCP，避免 Mihomo 跳过不支持 UDP 的代理后落到直连。Cloudflare DoH 使用 `cloudflare-dns.com` 域名，保留 TLS SNI；IP 形式的 `1.1.1.1` 在当前 Worker 反代路径上会收到与目标 IP 不匹配的证书。

顶层 `ipv6: false` 与 `dns.ipv6: false` 统一使用 IPv4。手机还需在“工具 → 进阶配置 → 网络”中关闭 VPN 的 IPv6 接入，并重连 VPN；否则应用已获得的 IPv6 地址仍进入隧道，内核会以 `ip version error` 拒绝连接。`unified-delay: true` 统一订阅内核的测速方式，不能保证不同设备的实际延迟相同。

在 EdgeTunnel 后台的订阅转换设置中，将 SUBCONFIG 设置为：

```text
https://raw.githubusercontent.com/sssstwee/xiaomao-ai-proxy/main/backend/edgetunnel-subscription/acl4ssr.ini
```

先验证生成的完整订阅能被已安装的 Mihomo 加载，再刷新客户端。Clash Verge 的扩展脚本和应用 DNS 设置不得覆盖这份订阅的 DNS；端口、TUN 等平台运行设置继续由客户端管理。现有十节点、反代路径和 TLS/ECH 参数不由这些模板修改。此模板面向 Mihomo，其他内核须单独验证。

私有转换服务的版本、缓存、systemd 单元与回退方式见 [转换后端部署说明](converter/README.md)。转换后端的私密地址仅保存在 EdgeTunnel 后台 SUBAPI 中。

参考：[Mihomo DNS 配置](https://wiki.metacubex.one/config/dns/)、[subconverter 外部配置](https://github.com/tindy2013/subconverter/blob/master/README-cn.md#外部配置)。
