# EdgeTunnel 与 Voyra 的统一托管分流

`acl4ssr.ini` 通过 subconverter 原生 `clash_rule_base` 加载 `clash-base.yaml`。**分组、图标、服务探活、规则集、AI 分流、DNS 和 UDP 防直连规则统一维护在 `clash-base.yaml`。** INI 关闭规则生成与覆盖，VPS 转换出口按模板合并最终配置；模板中的 `include-all-proxies` 由转换层解析为本次订阅的显式成员列表，保留原节点顺序，并完整保留图标及 Mihomo 专有字段。

三个组分别为 `默认代理`（url-test，60 秒，50ms 容差）、`Claude 专用` 和 `ChatGPT 专用`（fallback，90 秒）。图标采用固定版本的 Qure，文件镜像在自有资源仓库。两个 AI 组排除 WARP 和 `cf-tcp-backup`：Voyra 保持 VPS 原生出口，EdgeTunnel 继续使用自己的节点，两者不复制节点凭据。

Claude / OpenAI 分别使用 MetaCubeX 的每日更新域名规则，并内联已审查的主站、认证、CDN、功能开关和资源域名作为首次启动保障。Claude 专属 Auth0 先于 OpenAI 共用认证；同时保留 Anthropic 官方入站 IP、OpenAI 语音网段和 Artifacts 资源。Voice 网段来自 [OpenAI 官方 JSON](https://openai.com/chatgpt-voice.json)，同步脚本及定制 Worker 刷新时读取自有仓库的 JSON 镜像，失败保留模板快照。

AI DNS 分别经对应代理组使用 Cloudflare 与 Google DoH；国内和私有域名走直连 DNS。Cloudflare DoH 使用 `cloudflare-dns.com` 域名保留 TLS SNI。`proxy-server-nameserver` 单独解析节点域名，避免循环依赖。顶层和 DNS 均关闭 IPv6；全局拒绝 UDP 443 以保留移动网络 QUIC 回落，AI UDP 防直连规则同样保留。模板面向 Mihomo；不保证所有语音客户端都支持 TCP 回落。

EdgeTunnel 后台继续使用原 SUBAPI 和以下 SUBCONFIG，无需更换地址：

```text
https://raw.githubusercontent.com/sssstwee/xiaomao-ai-proxy/main/backend/edgetunnel-subscription/acl4ssr.ini
```

旧版 subconverter 会覆盖模板中的分组，因此 `converter/policy_server.py` 在本机 25511 端口复用原 25510 转换服务，并从同一 YAML 补齐最终配置；Caddy 的原私密转换路由转发到 25511。Worker 不再负责注入分组和规则。转换层每 300 秒检查托管模板，网络失败时使用私有缓存，避免失去最后可用配置。定制 Worker 只保留传输兼容、节点域名解析和语音网段刷新，不覆盖模板策略。保持“仅输出节点信息”关闭。

Voyra 运行 `routing_policy.py`，从同一托管 YAML 更新配置，保留节点参数及原首选顺序、端口和 TUN 等运行设置。安装 `voyra-routing-sync.service` / `.timer` 后每 15 分钟检查一次；写入前使用 Mihomo 验证，原子替换文件，自动保留私有备份。下载或验证失败时保留原订阅，不重启代理节点服务。原订阅 URL 和鉴权保持原值。

```sh
python3 routing_policy.py --config /opt/voyra-subscription/vpn.yml --mihomo /usr/local/bin/mihomo --mihomo-home /var/lib/voyra-routing
python3 -m unittest discover -s backend/edgetunnel-subscription -p 'test_*.py' -v
```

修改托管 YAML 后，EdgeTunnel 等待转换模板缓存（300 秒）失效或清理转换服务缓存，Voyra 等待定时同步或手动启动同步服务，再更新客户端订阅。不要在 Worker 中另写一份分组/业务规则。Clash Verge 覆写脚本和客户端 DNS 设置也不应覆盖托管策略。

转换后端的部署与回退方式见 [converter/README.md](converter/README.md)。线上节点凭据、转换后端私密地址和备份不入库。

## 公共资源归档

19 个远程规则集、3 个图标和 Voice JSON 全部引用 [sssstwee/edgetunnel/resources](https://github.com/sssstwee/edgetunnel/tree/main/resources)。GeoIP / GeoSite / MetaDB / ASN 四个大数据文件引用该仓库 Releases，并在 `geox-url` 中显式指定；保持 MMDB 模式，每 24 小时更新，避免内核回到默认第三方下载地址。转换层和 Voyra 同步均保留这些字段。5 个 inline 规则集继续保存在本模板。

资源仓库每天同步已使用的成熟上游数据，保留来源提交、SHA256、许可证及最后可用快照；更新失败不会清空现有资源。规则和图标使用固定的自有 main 地址，Geo 数据使用自有 `releases/latest/download` 地址。业务规则在此处维护，资源来源在资源仓库的 `sources.json` 维护；不要将鉴权和节点凭据复制到公共文件。
