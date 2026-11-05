# EdgeTunnel 与 Voyra 的统一托管分流

`acl4ssr.ini` 通过 subconverter 原生 `clash_rule_base` 加载 `clash-base.yaml`。**分组、图标、服务探活、规则集、AI 分流、DNS 和 UDP 防直连规则统一维护在 `clash-base.yaml`。** INI 关闭规则生成与覆盖，EdgeTunnel 的内置转换按模板合并最终配置；模板中的 `include-all-proxies` 由转换层解析为本次订阅的显式成员列表，保留原节点顺序，并完整保留图标及 Mihomo 专有字段。

`默认代理`（select）默认使用 `故障转移`（fallback，按订阅顺序选择健康节点），也可手动切换至 `负载均衡`（load-balance，round-robin）或 `自动选择`（url-test，60 秒，50ms 容差）。已保存的手动选择需在客户端切换。`Claude 专用` 和 `ChatGPT 专用` 各自使用 fallback（90 秒）。负载均衡按新连接轮询可用节点，同一长连接中的请求保持同一节点，单连接带宽不会叠加。图标采用固定版本的 Qure：默认代理为蓝色箭头，负载均衡为绿色环形节点，自动选择为黄色闪电，故障转移为绿色心跳，文件镜像在自有资源仓库。两个 AI 组排除 WARP、`cf-tcp-backup` 和 `普通` 标识节点：Voyra 保持 VPS 原生出口，EdgeTunnel 继续使用自己的节点，两者不复制节点凭据。

Claude / OpenAI 分别使用 MetaCubeX 的每日更新域名规则，并内联已审查的主站、认证、CDN、功能开关和资源域名作为首次启动保障。Claude 专属 Auth0 先于 OpenAI 共用认证；同时保留 Anthropic 官方入站 IP、OpenAI 语音网段和 Artifacts 资源。Voice 网段来自 [OpenAI 官方 JSON](https://openai.com/chatgpt-voice.json)，同步脚本及定制 Worker 刷新时读取自有仓库的 JSON 镜像，失败保留模板快照。

Claude、OpenAI 的核心域名与 DNS 分别进入各自的独立 fallback。通用海外 AI 的规则与 DNS 使用“故障转移”，即使“默认代理”选择负载均衡也不会轮询 AI 连接。Artifacts 的公共字体和脚本、公共 CDN 与遥测主机及其 DNS 使用“故障转移”；公共依赖规则先于 AI 核心规则，避免严格回源的 TLS 握手失败。这些 CDN 为多个应用共享，其他应用访问同一主机也采用该路径。普通流量仍可手动选择负载均衡，fallback 在健康变化时仍可能切换节点，已有长连接不会自动迁移。

Claude / ChatGPT 核心 DNS 分别经对应严格代理组使用 Cloudflare DoH；严格回源不能可靠访问 Google DoH，因此不将其放入这两个 DNS 策略。普通及公共依赖 DNS 保留 Cloudflare 与 Google DoH；国内和私有域名走直连 DNS。Cloudflare DoH 使用 `cloudflare-dns.com` 域名保留 TLS SNI。`proxy-server-nameserver` 单独解析节点域名，避免循环依赖。顶层和 DNS 均关闭 IPv6；全局拒绝 UDP 443 以保留移动网络 QUIC 回落，AI UDP 防直连规则同样保留。模板面向 Mihomo；不保证所有语音客户端都支持 TCP 回落。

EdgeTunnel 名单分为 `回源IP 洛杉矶 · AI`（`/proxyip-only=`）和 `回源IP 新加坡 · 普通` / `回源IP 洛杉矶 · 普通`（`/proxyip=`）两套，各默认十六条。Claude / ChatGPT 的独立 fallback 排除普通节点；普通故障转移、负载均衡和自动选择排除严格 AI 节点。普通池优先新加坡和洛杉矶，排除香港；按三轮真实 HTTPS Cloudflare trace 的中位首字节耗时筛选，组内按该结果排序。普通组三个探活地址同样使用 Cloudflare trace（预期 200），验证实际回源；Google / YouTube 主页另行验收。非 Cloudflare 目标可能经 Worker 直接出站，另测 AWS 公网回显排除香港，不能把节点标签当作所有目标的固定出口承诺。严格路径只承诺已实测的核心 HTTPS 目的地，不能当作通用 TCP 出口；普通路径支持非 Cloudflare 网站，但不承诺其出口固定洛杉矶。通用 AI（例如 Gemini）继续走普通故障转移，不进入负载均衡。AI 节点在客户端按组内 API 地址测速；全节点 Google 测速不适合严格节点。

EdgeTunnel 后台继续使用原 SUBAPI 和以下 SUBCONFIG，无需更换地址：

```text
https://raw.githubusercontent.com/sssstwee/xiaomao-ai-proxy/main/backend/edgetunnel-subscription/acl4ssr.ini
```

EdgeTunnel 的 `converter.mjs` 通过私有 Service Binding 调用独立 Cloudflare 转换 Worker，复用 `@subconverter/core` 转换节点，并按本模板补齐完整策略；后台 SUBAPI 填写 Worker 自身 HTTPS 域名，SUBCONFIG 保持上述 INI 地址。模板每 300 秒检查更新，最后可用版本保存到转换服务的专用 Cloudflare KV。节点列表在主 Worker 的同一请求内生成，经私有绑定传给转换 Worker，无需回调自身公网 HTTP，也不再调用 VPS。分组、规则和 DNS 全部来自模板；传输兼容、节点域名解析和语音网段刷新继续保留。保持“仅输出节点信息”关闭。

`converter/policy_server.py` 与原 VPS subconverter 保留为历史回退方案，CF 主订阅不再使用它们。Voyra 仍独立运行原订阅和节点服务，按用户选择保留至停用 VPS 时再切换。

Voyra 运行 `routing_policy.py`，从同一托管 YAML 更新配置，保留节点参数及原首选顺序、端口和 TUN 等运行设置。安装 `voyra-routing-sync.service` / `.timer` 后每 15 分钟检查一次；写入前使用 Mihomo 验证，原子替换文件，自动保留私有备份。下载或验证失败时保留原订阅，不重启代理节点服务。原订阅 URL 和鉴权保持原值。

Voyra 同步服务通过 `--quic-node` 列出已经实测 HTTP/3 的 Hysteria2 节点。普通代理流量的 UDP/443 使用独立的 `Voyra QUIC` 轮询负载均衡组，图标为橙色火箭；原规则命中的直连和拒绝流量继续拦截。Claude / ChatGPT 的 UDP/443 仅在 `voyra-hy2-direct` 同时属于已验证列表和对应 AI 专用组时定向到该节点，每条放行后保留同一服务的 REJECT，避免不支持 UDP 时继续匹配到通用组或直连。节点连接失败时 UDP 请求失败，由支持回退的应用另发 TCP 请求；TCP 继续走各自的 fallback 组，其他 AI UDP 端口仍拒绝。原全局拦截保留在子规则之后。EdgeTunnel 仍使用共享模板中的全局拦截。

```sh
python3 routing_policy.py --config /opt/voyra-subscription/vpn.yml --mihomo /usr/local/bin/mihomo --mihomo-home /var/lib/voyra-routing --quic-node voyra-hy2-direct --quic-node voyra-hy2-warp
python3 -m unittest discover -s backend/edgetunnel-subscription -p 'test_*.py' -v
```

修改托管 YAML 后，EdgeTunnel 等待 Worker 模板缓存（300 秒）失效，Voyra 等待定时同步或手动启动同步服务，再更新客户端订阅。不要在 Worker 中另写一份分组/业务规则。Clash Verge 覆写脚本和客户端 DNS 设置也不应覆盖托管策略。

历史 VPS 转换后端的部署与回退方式见 [converter/README.md](converter/README.md)。线上节点凭据、转换后端私密地址和备份不入库。

## 公共资源归档

19 个远程规则集、6 个共享图标、Voyra QUIC 图标和 Voice JSON 全部引用 [sssstwee/edgetunnel/resources](https://github.com/sssstwee/edgetunnel/tree/main/resources)。GeoIP / GeoSite / MetaDB / ASN 四个大数据文件引用该仓库 Releases，并在 `geox-url` 中显式指定；保持 MMDB 模式，每 24 小时更新，避免内核回到默认第三方下载地址。转换层和 Voyra 同步均保留这些字段。6 个 inline 规则集继续保存在本模板。

资源仓库每天同步已使用的成熟上游数据，保留来源提交、SHA256、许可证及最后可用快照；更新失败不会清空现有资源。规则和图标使用固定的自有 main 地址，Geo 数据使用自有 `releases/latest/download` 地址。业务规则在此处维护，资源来源在资源仓库的 `sources.json` 维护；不要将鉴权和节点凭据复制到公共文件。
