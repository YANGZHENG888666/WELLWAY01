# 域名落地切换清单（备案通过后执行）

> 用途：备案域名生效后，把隐私政策/用户协议从 gh-pages 迁到备案域名，
> 并替换占位邮箱。整个过程约 20 分钟，均为机械操作。

## 前提
- 域名已实名 + ICP 备案通过（个人主体，与身份证一致）
- 域名解析可用（阿里云云解析 → 添加 A 记录 / CNAME，TTL 默认即可）

## 1. 上传法务页到备案域名

把以下两个文件原样上传到域名根目录（或 `legal/` 子目录均可，保持两个文件同目录）：
- `legal/privacy.html`
- `legal/terms.html`

> 官网（2026-08-26 新增）：`website/` 目录已包含官网首页 `index.html` +
> 法务页副本（`privacy.html`/`terms.html`）+ 截图素材，纯静态可直接整目录部署。
> 部署说明见 `website/README.md`（Cloudflare Pages / 阿里云 OSS 两种方式）。

托管方式任选：
- 阿里云 OSS 静态网站托管（简单，建议）
- 阿里云 ECS + Nginx
- Cloudflare Pages / Vercel（仅限域名本身已备案，CDN 节点不影响备案要求）

上传后自测：
```
https://你的域名/privacy.html     → 显示「个人信息处理规则」
https://你的域名/terms.html       → 显示「用户服务协议」
```

## 2. 替换占位邮箱

把 `contact@wellway.app` 替换为你的真实邮箱，共 4 处文件：
- `legal/privacy.html`（第 9 条联系邮箱）
- `legal/terms.html`（第 8 条联系邮箱）
- `admin/index.html` 内嵌法务模板（`LEGAL_CONTENT` 里两处）

改完把 `admin/index.html` 重新上传 gh-pages 覆盖（后台照常跑 gh-pages，无需迁域名）。

## 3. App Store Connect 填最终 URL

App 信息 → 隐私政策 URL 填：
```
https://你的域名/privacy.html
```
用户协议（如 ASC 提供协议栏位）填：
```
https://你的域名/terms.html
```

## 4. 后台登录页链接

后台 `admin/index.html` 登录页底部「隐私政策 / 用户协议」链接用的是相对路径
（`./?page=privacy` / `./?page=terms`，跟随当前域名），因此后台留在 gh-pages
也无需改动。若后台以后也迁到备案域名，链接会自动跟随，无需改代码。

## 5. 备案通过后的验证

- [ ] `https://你的域名/privacy.html` 与 `terms.html` 可访问且为 v2.0 全文
- [ ] 替换邮箱后所有页面不再出现 `contact@wellway.app`
- [ ] 工信部备案号显示在法务页底部（如适用，可在页脚加一行「京ICP备XXXXXXXX号」）
- [ ] App Store Connect 隐私政策 URL 已填最终域名
