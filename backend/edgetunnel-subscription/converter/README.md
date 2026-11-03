# 私有订阅转换后端

复用 [asdlokj1qpi233/subconverter v0.9.9](https://github.com/asdlokj1qpi233/subconverter/releases/tag/v0.9.9) 的 Linux amd64 发布包，SHA-256 为 `b9d6f969300d3c8398f9d970db7436274df0ff3e7c91d935d26bbd79fafc8488`。部署在现有 VPS，无新增订阅费用；客户端仍订阅 EdgeTunnel，代理数据仍通过 Worker 转发。

将发布包解压到 `/opt/edgetunnel-subconverter`，将本目录的配置模板渲染为 `pref.ini`，使用随机私密管理令牌替换 `__PRIVATE_API_TOKEN__`。仅缓存目录归 `edgetunnel-converter` 用户写入，其余程序与配置由 root 管理。安装本目录的 systemd 单元后，先验证本机转换输出。

转换服务只监听 `127.0.0.1:25510`。在现有 Caddy HTTPS 站点内，用随机私密路径仅转发 GET `/私密前缀/sub` 到本机 `/sub`，保留查询参数，并对该路径设置 `log_skip`。私密前缀不入库、不写访问日志；其他路径继续由原订阅服务处理。修改前备份 Caddyfile，执行 `caddy validate` 后重载。

SUBAPI 使用指向该 VPS 的仅 DNS 源站域名，并由 Caddy 自动维护匹配域名的公开可信证书。不能把 IP 地址直接写入 SUBAPI：[Workers fetch 不支持直接请求 IP 地址](https://developers.cloudflare.com/workers/platform/known-issues/)。

验证十节点、规则、DNS、TLS/ECH 与已安装 Mihomo 的解析检查后，仅将 EdgeTunnel KV `config.json` 的 `订阅转换配置.SUBAPI` 改为该 HTTPS 私密前缀。`SUBCONFIG`、节点列表与客户端订阅地址保持原值。失败时将 SUBAPI 恢复为切换前的值，无需修改客户端或重启代理节点。

外部模板缓存 300 秒、规则缓存 21600 秒。发布托管模板后，如需立即生效，清理此服务自身缓存并重启转换服务；验证新的完整订阅后再刷新客户端。

## 统一托管策略层

原 v0.9.9 会重新生成并清空模板的 `proxy-groups`，不保留 icon / expected-status 等完整选项。保留原转换服务和凭据，在 `/opt/edgetunnel-policy` 安装 `policy_server.py` 与上一层目录的 `routing_policy.py`，安装 `edgetunnel-policy.service`；服务仅监听 `127.0.0.1:25511`。缓存目录 `/var/cache/edgetunnel-policy` 仅由原转换用户读写，初始缓存来自已验证的 `clash-base.yaml`。

Caddy 原私密路由的上游从 25510 改为 25511；API 前缀、鉴权、日志跳过及源站 TLS 保留。节点格式转换仍使用原 25510 服务，完整 Clash 输出按统一模板补齐；仅节点和其他格式直接透传。回退时只需恢复此路由的 25510 上游并恢复旧模板，原转换服务和节点服务都不需要更换。
