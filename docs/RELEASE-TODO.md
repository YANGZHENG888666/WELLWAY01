# WELL WAY 上线前：你需要做的 5 件事（2026-08-25）

> 代码/工程侧合规项已全部完成并验证（见文末「已完成」）。以下 5 件事只有你能做，按顺序执行，每件 2~10 分钟。

## 1. 云端重新执行注销账号 SQL（必做，5 分钟）

- 文件：`backend/supabase/migrations/0016_delete_account.sql`
- 重要：2026-08-25 实测发现旧版函数内 `delete from storage.objects` 会被 Supabase
  Storage 拦截（`42501 Direct deletion from storage tables is not allowed`），
  导致注销必然失败。已修复：照片删除移到 App 端走 Storage API，SQL 函数只删
  `auth.users`（级联清空用户数据）。**请把更新后的文件内容整体粘贴 → Run**（覆盖旧函数）。
- 完成标志：不报错；App 内「个人中心 → 注销账号 → 永久删除」能真正删号并回到登录页
- 验证方法：删完后去 Supabase → Authentication → Users 确认该用户已消失

## 2. 重新上传后台到 GitHub Pages（已完成 ✅ 2026-08-25）

- 已上传并验证（v2.0 法务页全文可访问）：
  - 后台：https://yangzheng888666.github.io/WELLWAY01/
  - 隐私政策：https://yangzheng888666.github.io/WELLWAY01/?page=privacy
  - 用户协议：https://yangzheng888666.github.io/WELLWAY01/?page=terms
- 后续替换邮箱/迁域名后需重新上传一次（覆盖 `index.html`）

## 3. 替换占位邮箱（5 分钟，待你提供真实邮箱）

- 网页与文档里的 `contact@wellway.app` 是占位邮箱，需换成你的真实邮箱
- 需要改的文件（3 处）：
  - `legal/privacy.html`、`legal/terms.html`（第 9 条/第 8 条联系邮箱）
  - `admin/index.html` 内嵌的法务页模板（`LEGAL_CONTENT` 里两处）
  - 改完重复第 2 步重新上传，并重新构建 App

## 4. ICP 备案 + 域名（国区上架必做，周期 1~3 周）

- 买域名（阿里云/腾讯云 .cn 约 ¥30/年）
- 提交 ICP 备案：个人备案免费，需身份证 + 手机号 + 人脸核验，7~20 个工作日
- 备案通过后把隐私政策/用户协议托管到该域名（告诉我，我来帮迁）
- App Store Connect → App 信息 → 隐私政策 URL 填最终地址

## 5. Apple Developer 账号 + 上架材料

- 注册 Apple Developer：https://developer.apple.com/programs/（¥688/年）
- Xcode → 登录账号 → 自动签名 → Product → Archive → Distribute App
- App Store Connect 填资料：截图（6.9" 真实机型）、描述、关键词、审核备注

---

## 已完成并验证（代码/工程侧）

- [x] 隐私说明/隐私政策/用户协议 v2.0（App 内登录页完整版 + 设置页短版，模拟器已验证渲染）
- [x] 注销账号：App 入口 + 确认弹窗 + 后端 `delete_my_account()`
- [x] 注销账号 Bug 修复：Storage 照片改为 App 端经 Storage API 删除（RLS 实测通过：
      上传/列出/删除均 200），SQL 函数只删 `auth.users`
- [x] 注销账号端到端验证通过（2026-08-25）：云端 RPC 返回 204，测试账号从
      `auth.users` 消失、旧 token 失效（user_not_found），级联删除生效
- [x] 隐私清单 `PrivacyInfo.xcprivacy` 已打进 built 包（含 OtherUserContent）
- [x] 后台法务页路由（gh-pages 线上 v2.0 已验证可访问）
- [x] 高德跳转 `iosamap://path`（骑行 t=3 + 起终点）+ 苹果地图兜底 + 白名单
- [x] 权限描述文案 + 后台定位 `UIBackgroundModes=location` 已在 built 包
- [x] 社交功能已下线（国内个人开发者合规）；轻社交"擦肩而过"保留
- [x] 认证链路真实化（2026-08-25）：登录/注册/忘记密码/绑定邮箱全部走 Supabase
      真实邮箱验证码 OTP；移除「任意验证码放行」测试模式（上架审核必过项）
      ⚠️ 需在 Supabase → Authentication → SMTP 配置真实发信，否则验证码可能收不到
