# WELL WAY 上线清单（真·公网）

> 目标：让数据库、后台、App 全部真正在线，不再依赖你这台电脑。

## 现状（刚实测）

| 部分 | 状态 | 说明 |
|---|---|---|
| 数据库 | 真云端 | Supabase hyfxpcwbhfgmtwjhcxdn.supabase.co，不是本地 |
| 管理员账号 | 真云端 | 421975135@qq.com 已在云端验证 |
| 后台代码 | 可用 | admin/index.html 单文件 + Supabase API，可放任何静态托管 |
| 后台访问方式 | 临时 | 现在靠你电脑跑 http.server + Cloudflare 隧道，电脑关机就断 |
| iOS App | 模拟器级 | 编译通过、模拟器能跑；真机需 Apple 开发者账号 |

## 你要做的 3 件事（每件 2~5 分钟）

### 1. 修云端数据库（必做，否则上传路线图报错）

云端缺 3 样东西：routes.map_url 列、route_favorites 表、admin_logs 表。
修复脚本已生成，可重复执行：

- 文件：backend/supabase/migrations/FIX_2026-08-23.sql
- 操作：Supabase Dashboard → SQL Editor → 把文件内容整体粘贴 → Run
- 完成标志：不报错；后台"路线"页能正常上传路线图

更省事的方式：把 Supabase 的数据库连接串（Dashboard → 项目设置 → 数据库 → 连接字符串，postgresql://... 整段）发我，我直接帮你跑。

### 2. 后台变成永久公网地址（三选一）

后台就是 admin/index.html，随便放哪都行：

- GitHub Pages（推荐，免费）：把 admin/ 推到你的 GitHub 仓库 → 仓库 Settings → Pages → 选分支/目录 → 生效
  ⚠️ 注意：GitHub Pages 免费版要求仓库是**公开**的。你的 WELLWAY01 仓库目前是私有的，
  需要先到仓库 Settings → General → Danger Zone → Change visibility 改成 Public；
  不想公开就用下面 Vercel/Netlify 方案（私有仓库也行）。
- Vercel / Netlify（免费）：注册账号 → 新建站点 → 选择/拖入 admin/ 文件夹 → 自动得到永久地址
- 让我来：把 GitHub token 或 Netlify/Vercel 登录方式给我，我直接部署

### 3. App 装到真机（只有你能做）

- 注册 Apple 开发者：https://developer.apple.com/programs/ （$99/年）
- 加入后在 Xcode 里登录账号、勾选自动签名、真机连接运行
- 要分发给别人：Xcode → Product → Archive → TestFlight / App Store

## 已帮你做好的

- backend/scripts/deploy-admin.mjs：一键把后台传到 Supabase 存储（Supabase 对 HTML 强制 text/plain，只能当备份，不能当网页打开）
- 中文文件名上传已修复（后台 uploadImage() 自动清洗文件名）
- App 图标 alpha 已压平、PrivacyInfo.xcprivacy 已补全，满足上架硬性要求

## 当前临时公网地址（电脑开着才有效）

https://hdtv-protection-calculators-assignment.trycloudflare.com/admin/index.html

完成第 2 步后这个地址就不再需要了。

## 后台升级 2026-08-23（模块化 + 数据监测 + 管理员 + 日志加固）

新版后台已上线：https://yangzheng888666.github.io/WELLWAY01/

新增能力：
- 模块化导航：概览（数据监测/操作日志）、内容管理（品牌/车型/路线/打卡点/徽章/活动）、系统（管理员）
- 表单字段分组（基本信息/图片素材/详细参数/展示设置），必填带 `*`，其余标注"选填"
- 数据监测仪表盘：注册用户/今日骑行/路线/车型/打卡点/徽章/活动/收藏统计 + 近 7 日骑行趋势 + 今日各路线骑手榜
- 操作日志：按内容表/动作筛选 + 分页；数据库层已 REVOKE 写权限，任何人不可改/删，只读
- 内容列表：搜索、分页、CSV 导出
- 管理员管理：后台直接授予/移除管理员（无需再手写 SQL）

### 必做：执行升级 SQL（否则数据监测/管理员页不可用）

- 文件：backend/supabase/migrations/0013_admin_dashboard.sql
- 操作：Supabase Dashboard → SQL Editor → 粘贴整个文件 → Run（可重复执行）
- 完成标志：后台"数据监测"出现统计卡片；"管理员"页出现用户列表与授予输入框

更省事的方式（把连接串发我，我直接帮你跑）：
```bash
cd backend/scripts
node --env-file=../.env run-migration.mjs
```
前提：backend/.env 里配置 SUPABASE_DB_URL（Supabase Dashboard → 项目设置 → 数据库 → 连接字符串）。
该脚本可重复执行；也可加参数指定其他迁移文件，如 `node --env-file=../.env run-migration.mjs ../supabase/migrations/FIX_2026-08-23.sql`。

### 密码重置邮件回跳（已完成 ✅）

已配置 Supabase Dashboard → Authentication → URL Configuration → Redirect URLs，白名单包含：
- https://yangzheng888666.github.io/WELLWAY01/
- https://yangzheng888666.github.io/WELLWAY01/admin/index.html

"忘记密码"邮件回跳现在指向线上后台，不再跳转到 localhost:3000。

## 法务页面（隐私政策 / 用户协议，2026-08-25 新增）

隐私政策与用户协议已内嵌进后台单文件 `admin/index.html`，通过查询参数直链访问（无需额外文件、无需改 Pages 配置）：

- 隐私政策：`https://yangzheng888666.github.io/WELLWAY01/?page=privacy`
- 用户协议：`https://yangzheng888666.github.io/WELLWAY01/?page=terms`

同时后台登录卡片底部已加「隐私政策 · 用户协议」链接（新窗口打开）。
内容源与 `legal/privacy.html`、`legal/terms.html`、`docs/PRIVACY-POLICY.md`、`docs/TERMS-OF-SERVICE.md` 保持 v2.0 一致。

### 重新上传（你已完成过同类操作）

线上 gh-pages 分支目前只有 `index.html`（即后台本体）。把新的 `admin/index.html` 内容覆盖上传到
GitHub 仓库 `WELLWAY01` 的 `gh-pages` 分支根目录 `index.html`（和上次传后台一样，拖拽替换即可），
等待 1~2 分钟生效。上传后请自行验证：

- 后台：`https://yangzheng888666.github.io/WELLWAY01/` 仍正常显示登录页
- 隐私政策：`https://yangzheng888666.github.io/WELLWAY01/?page=privacy` 显示 v2.0 全文（含跨境传输/第三方共享/注销）
- 用户协议：`https://yangzheng888666.github.io/WELLWAY01/?page=terms` 显示 v2.0 全文

> ⚠️ 该地址目前 404（线上还是旧版 index.html），上传后生效。上架前请把 App Store Connect「隐私政策 URL」填成上面的隐私政策地址。

## 账号注销（2026-08-25 新增）

- App 内：个人中心 → 注销账号（红色入口 + 二次确认弹窗，明示永久删除不可恢复）
- 后端：`backend/supabase/migrations/0016_delete_account.sql` 提供 `delete_my_account()` 安全函数
  （先删 Storage 车辆照片，再删 `auth.users`，其余用户表外键级联）
- **云端待执行**：Supabase Dashboard → SQL Editor → 粘贴执行 `0016_delete_account.sql`
- 执行完成标志：App 内「注销账号 → 永久删除」能真正删号并回到登录页

## 运营要点：天气 / 导航数据怎么填（2026-08-29）

App 的目的地天气、导航起终点**不是**在「路线」里直接填坐标，而是由该路线的**打卡点（checkpoints）**推算：

- 起点 = 该路线「序号（seq）最小且有经纬度」的打卡点
- 终点 = 该路线「序号（seq）最大且有经纬度」的打卡点
- 目的地天气 = 按终点打卡点的经纬度调用 Open-Meteo 计算（当前地点 = 手机实时定位）

后台已做配套增强（`admin/index.html`）：

- 「路线」列表新增「打卡点」列：显示打卡点数量、起终点坐标是否齐全，缺坐标的路线标黄提醒
- 「路线」编辑弹窗顶部显示该路线当前推算出的起点/终点及坐标
- 「打卡点」编辑弹窗顶部新增「🔍 搜索坐标」：输入地名（如 芹峪口、高崖口）自动带出经纬度并填入（OpenStreetMap Nominatim 公共接口，免费免 key；搜不到时手动填坐标即可）
- 「打卡点」列表新增「角色」列：标记该点被推算为 起点 / 终点 / 途经

运营建议：新建路线后，先到「打卡点」按顺序（seq 1、2、3…）把沿途点位连同经纬度建好，起终点必须有坐标；取坐标可用后台内置搜索，或高德开放平台坐标拾取器（https://lbs.amap.com/tools/picker）。

## 用户反馈（2026-08-29 新增）

- 后台「概览」新增「💬 用户反馈」只读页：查看 App 内「意见反馈」和「品牌添加请求」，支持搜索内容/联系方式、分页、显示提交用户邮箱
- 数据库策略已生效：`backend/supabase/migrations/0017_admin_feedback.sql`（管理员可读全部反馈，普通用户仍只能看自己的；已在云端执行，无需再手动跑）
