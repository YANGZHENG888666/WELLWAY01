# WELL WAY 摩托车出行 App

> 最新接续点：先读 [`docs/HANDOFF-2026-11-12.md`](docs/HANDOFF-2026-11-12.md)。
> 项目已于 2026-11-12 完整迁移到 `/Users/young/Documents/ChatGPT/wellway`。

匿名账号 + 邮箱绑定,核心功能:骑行路线、同目的地人群提醒(同路人聊天)、路线打卡与徽章、车辆车库(品牌/车型筛选)。

## 仓库结构

```text
backend/   Supabase 后端(migrations / seed / 冒烟测试脚本)
admin/     管理后台网页(维护车型库/路线/徽章/活动)
ios/       iOS 原生 App(SwiftUI + Supabase Swift SDK)
docs/      交接文档与决策记录
outputs/   UI 原型与设计素材(HTML + 图片)
```

## 技术选型(已确定,不要推翻)

- 商用产品,目标至少 1000 用户
- 不抓取第三方网站数据,车型库由官方公开信息 + 自己维护
- 后端:Supabase(Postgres + Auth + Storage + Realtime)
- 客户端:优先 iOS 原生(Swift),有 Mac;后端平台无关,以后可加 Android
- UI 风格:黑白简洁(浅灰背景、白卡片、黑色主色),品牌见 `第三版logo+英文标题/`
- 账号体系:匿名账号自动创建 + 邮箱绑定,不做游客/登录双身份

## 快速开始

1. 看 `docs/HANDOFF.md` 了解项目全貌与下一步。
2. 后端:按 `backend/README.md` 创建 Supabase 项目、跑 migration + seed、开启匿名登录。
3. 客户端:按 `ios/README.md` 打开 Xcode 工程运行。

## 当前进度

- 后端:schema、RLS、聊天/打卡、存储桶、SQL 函数、冒烟测试脚本 — 完成(待建 Supabase 项目验证)
- 管理后台:品牌/车型/路线/徽章/活动 增删改 + 图片上传 — 完成(待接 Supabase)
- iOS:匿名登录 + 邮箱绑定 + 车库 + 路线/聊天 + 个人中心 — 完成,已通过模拟器编译
- 骑行中轨迹/打卡/总结/徽章/活动报名 — 完成(待真机验证定位闭环)
- 同路骑士提醒(骑行中只提示音,不弹窗)— 完成,见 `docs/COMPANION-ALERT-DESIGN.md`
- 管理操作日志(后台增删改自动审计)— 完成,迁移见 `backend/supabase/migrations/0011_admin_audit.sql`
- UI 设计稿:在另一个工程中,待接入

## 最近更新(2026-08-21)

- 路线详情/徽章/关于与反馈等页面 375 画布居中修复(适配 iPhone 17 等宽屏)
- 路线图上传:后台「路线」表单新增「路线图」入口,支持 SVG 自动转 2048px 高清 PNG(`routes.map_url` + `route-images` 桶,迁移见 `backend/supabase/migrations/0010_route_map_url.sql`)
- App 端 `RouteMapImage`:有路线图显示图片,无图回退画线轨迹
- 管理后台 UI 重构:黑白简洁风 + 品牌 logo
- 上线方案与剩余工作清单:`docs/DEPLOYMENT-PLAN.md`

## 最近更新(2026-08-22)

- 首页空状态按钮改为「选择更多路线」,点击跳转热力轨迹 Tab(右上角保留添加车辆)
- 后台路线图支持透明背景(PNG/SVG 均保留透明),上传提示已更新
- 上线测试清单:`docs/LAUNCH-TEST-CHECKLIST.md`;App Store 备案/合规补充见 `docs/APPSTORE-CHECKLIST.md`
- 用户协议:新增 `docs/TERMS-OF-SERVICE.md`(参考竞品补齐风险提示/内容授权/免责条款)
- 数据备份:新增 `backend/scripts/backup.sh`(pg_dump 或 JSON 方式,保留最近 10 份)
- 同行人提醒机制:新增 `docs/COMPANION-ALERT-DESIGN.md`,并实现「骑行中只提示音不弹窗」的防打扰逻辑

详细进度见 `docs/HANDOFF.md`。
