# EdgeTunnel 套餐用量显示

为现有 EdgeTunnel Worker 添加一层管理页适配，代理和订阅请求直接交给原 Worker。
保留已有 Worker 源码为私有部署目录中的 `original-entry.mjs`，入口使用：

```js
import original from './original-entry.mjs';
import { createUsageWorker } from './usage.mjs';
export default createUsageWorker(original);
```

部署时复用原 Worker 的全部绑定、域名、兼容设置、CPU 限制与关闭的 workers.dev 设置。
原始下载包中可能包含订阅或令牌，不得提交到仓库。

统计凭据复用原 KV 的 `cf.json`。令牌需在当前账户拥有 Analytics Read 和 Billing Read；
不需要账单写权限。套餐和账期通过 Cloudflare Subscriptions API 获取。
Workers Paid 使用实际账期的 1,000 万次包含请求；Workers Free 使用 UTC 日的 10 万次限额。
无法确认套餐、账期或统计时显示未知/失败，不默认降为免费，也不把今日用量当作账期用量。
数字来自 GraphQL Analytics，为估算值，可能延迟，与最终账单存在口径差异。

页面每 60 秒刷新用量模块，切回标签页也刷新，不重载或覆盖其他未保存的表单。

验证：`node --test backend/edgetunnel-usage/usage.test.mjs`。

官方依据：

- [Workers 计费与账期](https://developers.cloudflare.com/workers/platform/pricing/)
- [Subscriptions API 与 Billing Read 权限](https://developers.cloudflare.com/api/resources/accounts/subresources/subscriptions/methods/get/)
