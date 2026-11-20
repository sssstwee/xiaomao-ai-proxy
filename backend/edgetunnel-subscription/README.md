# EdgeTunnel 与 Voyra 的统一托管分流

`acl4ssr.ini` 通过 subconverter 原生 `clash_rule_base` 加载 `clash-base.yaml`。**分组、图标、服务探活、规则集、AI 分流、DNS 和 UDP 防直连规则统一维护在 `clash-base.yaml`。** INI 关闭规则生成与覆盖，EdgeTunnel 的内置转换按模板合并最终配置；模板中的 `include-all-proxies` 由转换层解析为本次订阅的显式成员列表，保留原节点顺序，并完整保留图标及 Mihomo 专有字段。

`默认代理`（select）包含 `自动选择`（url-test，300 秒，100ms 容差）和 `故障转移`（fallback，按订阅顺序选择健康节点，300 秒）。2026-11-11 起移除 `负载均衡`（round-robin），健康检查统一为 timeout 5000、lazy true、max-failed-times 3，以减少对 Worker 的探活请求。已保存的手动选择需在客户端切换。`Claude 专用`、`ChatGPT 专用` 和 `Gemini 专用` 各自使用 fallback（600 秒）。图标采用固定版本的 Qure：默认代理为蓝色箭头，自动选择为黄色闪电，故障转移为绿色心跳，文件镜像在自有资源仓库。三个 AI 组排除 WARP、`cf-tcp-backup` 和 `普通` 标识节点：Voyra 保持 VPS 原生出口，EdgeTunnel 继续使用自己的节点，两者不复制节点凭据。

Claude / OpenAI 分别使用 MetaCubeX 的每日更新域名规则，并内联已审查的主站、认证、CDN、功能开关和资源域名作为首次启动保障。Claude 专属 Auth0 先于 OpenAI 共用认证；同时保留 Anthropic 官方入站 IP、OpenAI 语音网段和 Artifacts 资源。Voice 网段来自 [OpenAI 官方 JSON](https://openai.com/chatgpt-voice.json)，同步脚本及定制 Worker 刷新时读取自有仓库的 JSON 镜像，失败保留模板快照。

Claude、OpenAI 的核心域名与 DNS 分别进入各自的独立 fallback，优先于共享资源。通用海外 AI、Meta Muse、Grok / X、Copilot / Bing、翻译与生成服务及其 DNS 使用“故障转移”，AI 连接不随“默认代理”的选择切换。Artifacts 字体和脚本、登录、验证码、安装更新、MCP 连接器、公共 CDN 与遥测主机也使用该组。这些主机为多个应用共享，其他应用访问同一主机也采用该路径；同理，X 和 Bing 的共享域整体进入故障转移。fallback 在健康变化时仍可能切换节点，已有长连接不会自动迁移。

2026-11-15 参考 JMS 的 11 月 14 日 AI 覆盖补充：内联 Gemini、Meta 引导域名，以及 Claude 第三方依赖和海外 AI 补充清单的去重并集（207 条）。包含 DeepL / Lara / Yandex、character.ai、Replicate、Runway、v0、Bolt、Lovable、Suno、Together、Fireworks、DeepInfra、LMArena 等。共享依赖按域名进入“故障转移”，不将 JMS 的美国节点编号或客户端进程策略复制到模板。Google 共享域、Gemini、Twitter 与 Bing 均使用与 JMS 相同的成熟 MetaCubeX 清单，镜像到资源仓库并每日更新。国内 AI 显式例外在最前；固定 AI 主站与依赖先于宽泛国内 AI、应用、广告和国内地址规则，DNS 采用相同优先级。

2026-11-20 起，Gemini / Antigravity / NotebookLM / AI Studio / Jules 的内联引导域名（`gemini-bootstrap`）、MetaCubeX `google-gemini` 清单以及 Google 共享域（`google`，含账号登录、YouTube 等）的路由与 DNS 统一使用 `Gemini 专用`（fallback，600 秒，探活 `generativelanguage.googleapis.com/v1beta/models`；Mihomo 以 HEAD 探活，无密钥时返回 404，GET 返回 403，均视为可达），使 Gemini 与其登录、静态资源同一出口。`find-process-mode` 改为 `strict`；在国内与局域网直连规则之后、`MATCH` 之前，Antigravity 应用（macOS `/Applications/Antigravity.app/`、Windows `Programs\Antigravity\`）及名为 `gemini` 的进程未被域名规则命中的流量也进入 `Gemini 专用`。Gemini CLI 以 `node` 运行时不匹配进程规则，依赖上述域名规则。Voyra 的 QUIC 子规则对这些流量继续 REJECT。

2026-11-20 起，Loyalsoldier `reject` 广告与追踪清单由 `默认代理` 改为 `REJECT`，不再把广告请求转发到节点、消耗 Worker 请求额度；它位于全部 AI、Claude 依赖、Google / Gemini 和国内 AI 规则之后，这些服务自身依赖的统计主机（如 Segment、Google Analytics）仍按其原分组放行，DNS 策略也不再为该清单使用代理 DoH。18 个 domain / ipcidr 远程规则集改用资源仓库每日编译的 Mihomo 二进制格式（`.mrs`），降低客户端内存和加载时间；`line-ip` 为 classical 规则，保持 YAML。

国内 AI、原有 Loyalsoldier 和 `GEOSITE,cn` 国内域名、局域网域名和私有网段走直连。没有可识别域名、目标属于中国大陆网段（`cncidr`，`no-resolve`）的纯 IP 连接也直连，规则位于全部 AI 与代理规则之后、`MATCH` 之前；域名流量不在本地解析。其余流量按专用规则或 `默认代理` 转发。模板启用 HTTP / TLS / QUIC 嗅探（`parse-pure-ip`），自带 DoH 或直连 IP 的应用也按真实域名分流；2026-11-20 起开启 `override-destination`，绕过内核 DNS、拿到被污染 IP 的应用（如手机上经局域网 DNS 解析的浏览器）也按嗅探出的真实域名由节点远端解析连接，Apple 推送等固定 IP 服务在 `skip-domain` 中跳过；第二条规则拒绝没有映射的 fake-ip（`198.18.0.0/16`），内核重启后残留的 fake-ip 立即失败重试，不再被当作局域网地址直连超时；Voyra 同步不写入 `sniffer`，保留其现有设置。

2026-11-18 起，Claude、Claude Code 与 Claude Desktop 的第三方依赖（Datadog / GrowthBook / Claude 的 Sentry 项目 / Statsig 遥测，hCaptcha / Turnstile / reCAPTCHA，Stripe、Intercom、Segment，安装更新与插件、Artifacts 资源、Bedrock / Vertex / Foundry、内置 MCP 连接器、文档站资源）在 `claude-deps` 中，紧随 Anthropic IP、先于 OpenAI 共享引导，路由与 DNS 均使用 `Claude 专用`，使登录、验证码、计费和遥测与 claude.ai 同一出口。共享主机按域名整体生效，ChatGPT 访问 Stripe、Intercom、Segment、Statsig、Turnstile 时同样使用 `Claude 专用`。WorkOS、Google 与 Microsoft 账号主机及 OpenAI 自己的 Sentry 项目不在该集合，仍按原规则。

Claude 和 ChatGPT 的核心域名通过各自的代理组查询 Cloudflare DoH。普通海外流量和公共依赖使用各自代理组中的 Cloudflare 或 Google DoH。国内域名使用国内 DoH，局域网域名沿用系统 DNS。`proxy-server-nameserver` 负责解析节点域名。模板启用 IPv6 TUN，DNS 保留原 IPv4 解析设置。EdgeTunnel 拦截 UDP/443，使支持回落的客户端改走 TCP。默认代理无法承载的其他 UDP 请求也会被拦截。

EdgeTunnel 按用户最新要求，仅保留原 AI 组的十六条 `洛杉矶NN · AI`（`/proxyip-only=`）节点，移除原十条普通节点。普通故障转移、自动选择与 Claude / ChatGPT 专用组共用这些节点；两个 AI 组仍为独立 fallback，AI 规则、DNS 与 UDP/443 防直连策略保持原样。普通组两个探活地址使用支持 HEAD 的 `https://cp.cloudflare.com/generate_204`（预期 204），严格路径不在 Worker 本地合成测速响应；API 专用组继续使用各自 API 探活。判断探活还须核对对应 URL 的 `extra.alive` 与响应状态，不能只检查返回 delay。Cloudflare trace 仅用 GET 做独立出口核验。严格路径此前对 Google / YouTube 及部分公共资源出现 TLS 失败，共用节点不代表通用网站兼容性已解决，也不承诺 ≤250ms。Voyra 的普通组成员不变；共享探活地址已单独验证其现有六条节点。

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

修改托管 YAML 后，更新 `acl4ssr.ini` 引用的模板提交。EdgeTunnel 等待 Worker 模板缓存（300 秒）失效，Voyra 等待定时同步或手动启动同步服务，再更新客户端订阅。分流与 DNS 以托管模板为准。

历史 VPS 转换后端的部署与回退方式见 [converter/README.md](converter/README.md)。线上节点凭据、转换后端私密地址和备份不入库。

## 公共资源归档

19 个远程规则集、7 个共享图标、Voyra QUIC 图标和 Voice JSON 全部引用 [sssstwee/edgetunnel/resources](https://github.com/sssstwee/edgetunnel/tree/main/resources)。GeoIP / GeoSite / MetaDB / ASN 四个大数据文件引用该仓库 Releases，并在 `geox-url` 中显式指定；保持 MMDB 模式，每 24 小时更新，避免内核回到默认第三方下载地址。转换层和 Voyra 同步均保留这些字段。11 个 inline 规则集继续保存在本模板。

资源仓库每天同步已使用的成熟上游数据，保留来源提交、SHA256、许可证及最后可用快照；更新失败不会清空现有资源。规则和图标使用固定的自有 main 地址，Geo 数据使用自有 `releases/latest/download` 地址。业务规则在此处维护，资源来源在资源仓库的 `sources.json` 维护；不要将鉴权和节点凭据复制到公共文件。
