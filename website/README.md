# WELL WAY 官网

纯静态官网，含 `index.html`（首页）、`privacy.html`（隐私政策）、`terms.html`（用户协议）。

> 2026-09-07 品牌更新：所有 logo 位使用第四版「反白」方形徽标
> （米白底 `#f0efeb` + 黑色箭头，源文件见 `assets/logo-full-cream.png`、`assets/logo.svg`）。
> 2026-08-26 重构为黑白橙配色版（橙色 `#f04818` 仅作小面积点缀）：
> 深色英雄区 → 3D 路线走廊滚动飞行（ScrollTrigger pin + scrub）→ 浅色产品展示
> （弹性卡片堆叠，悬停扇形展开、点击弹性置顶）→ 功能 → 三步出发 → 下载 → 页脚。
> GSAP 3.13 已本地化到 `assets/vendor/`，无 CDN 依赖。

## 本地预览

```bash
cd website && python3 -m http.server 8000
# 打开 http://localhost:8000
```

## 上架前必改（TODO 标记）

搜索 `TODO`，共 4 处，均在 `index.html`：

1. 3 处 App Store 下载链接 → 替换为 App Store 真实短链
2. 1 处联系邮箱 `contact@wellway.app` → 替换为真实邮箱
3. 页脚 ICP 备案号 → 备案通过后填写

## 部署到 Cloudflare Pages（推荐，免费）

```bash
cd website
npx wrangler pages deploy . --project-name wellway
```

或网页操作：Cloudflare 控制台 → Workers & Pages → Create → Pages → 上传 `website/` 目录。
备案通过后：域名 → 添加自定义域 `wellway.cn`（CNAME `wellway.pages.dev`）。

## 部署到阿里云 OSS（备案用，备案时域名需指向大陆服务器）

1. 阿里云控制台 → 对象存储 OSS → 创建 Bucket（地域选大陆，如华东 1），开通「静态网站托管」
2. 把 `website/` 下所有文件上传到 Bucket 根目录
3. 域名管理 → 绑定 `wellway.cn` → 云解析添加 CNAME 指向 Bucket 外网域名
4. 提交 ICP 备案

## 页面清单

| 路径 | 说明 |
|------|------|
| `/` | 官网首页 |
| `/privacy.html` | 个人信息处理规则（隐私政策） |
| `/terms.html` | 用户服务协议 |

## 上架前必改（TODO 标记，均在 `index.html`）

1. 3 处 App Store 下载链接 → 替换为真实短链
2. 1 处联系邮箱 `contact@wellway.app` → 替换为真实邮箱
3. 页脚 ICP 备案号 → 备案通过后填写
