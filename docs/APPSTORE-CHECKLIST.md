# 第 10 项:App Store 交付清单(2026-08-17)

## 已完成(代码/工程侧)

- [x] `Info.plist` 权限用途描述:定位(前后台)/蓝牙/本地网络/相册,`UIBackgroundModes=location`
- [x] `ITSAppUsesNonExemptEncryption=false`(仅 HTTPS,出口合规免审)
- [x] 版本号 `1.0.0 (1)`(2026-08-25 已统一并打进 built 包);仅竖屏
- [x] App 图标 1024×1024 占位(蓝底白路线);品牌蓝启动屏
- [x] `PrivacyInfo.xcprivacy`(NSPrivacyAccessedAPICategoryUserDefaults / CA92.1)已入工程
- [x] 错误文案全部中文化(`AuthManager.friendlyError`)
- [x] 骑行轨迹用途合规:仅记录骑行轨迹(指南 5.1.2);无第三方广告 SDK、无跟踪、无需 ATT
- [x] 认证链路真实化(2026-08-25):登录/注册/忘记密码/绑定邮箱全部走 Supabase 真实
      邮箱验证码 OTP,移除「任意验证码放行」测试模式(上架审核必过项,测试模式会被判账号造假)

## 需你在 App Store Connect 侧完成

### 1. 隐私政策 URL(上架必填)
- 网页版隐私政策已内嵌进后台单文件并部署在 GitHub Pages(2026-08-25):
  - 隐私政策 URL:`https://yangzheng888666.github.io/WELLWAY01/?page=privacy`(v2.0,含收集/使用/存储与跨境传输/第三方共享/权限/注销/未成年人/更新/联系)
  - 用户协议 URL:`https://yangzheng888666.github.io/WELLWAY01/?page=terms`(v2.0)
  - ✅ 已上线并验证可访问(2026-08-25,gh-pages 分支已含 v2.0 法务页全文)
- App Store Connect → App 信息 → 隐私政策 URL 填上面的隐私政策地址
- 内容与 App 内《隐私政策》《用户协议》(登录页入口)、`docs/PRIVACY-POLICY.md`、`docs/TERMS-OF-SERVICE.md` 一致(v2.0)
- 联系邮箱目前为占位 `contact@wellway.app`,**上架前请替换为真实邮箱**
  (文件: `legal/privacy.html`、`legal/terms.html`、`admin/index.html` 内嵌模板;App 内无邮箱占位)

### 2. 截图素材(6.7"/6.9")
- ✅ 已用 iPhone 17 Pro Max 模拟器产出 9 张 1320×2868(6.9")截图,见 `outputs/appstore-screenshots/`:
  `01-garage.png`(P房/Z900+推荐路线)、`02-route-detail.png`(路线详情 58km)、
  `03-route-overview.png`(地图全览-上滑提示)、`04-route-overview-detail.png`(地图全览-查看详情)、
  `05-routes-list.png`(路线卡片)、`06-badges.png`(徽章 2/6)、`07-records-list.png`(骑行记录)、
  `08-ride-summary.png`(骑行总结 20km 打卡2/2)、`09-riding.png`(骑行中)
- 截图使用模拟器测试匿名用户 `cd4f33a1-2e91-4c44-b6c3-5e5a57529ee7` 的演示数据
  (2 条完成骑行 + 2 枚徽章 + Z900 车辆;如需重新出图可直接复用,上架前如不想保留可删除该用户数据)
- 上架正式出图时可用真机或同尺寸模拟器重拍;目前 1320×2868 满足 6.9" 档位(2796×1290 横竖均可)

### 3. App Store 记录
- 名称:WELL WAY(副标题:摩友骑行路线与同路人)
- 关键词建议:摩托车、骑行、路线、摩友、打卡(≤100 字符)
- 描述:匿名可用 + 邮箱绑定;路线打卡、徽章、同路骑士聊天、车辆车库
- 审核备注:提供可用的测试账号说明(真实邮箱验证码登录)
- ✅ SMTP 真实发信已配置(2026-08-26 实测):`smtp.163.com` + `hbyangzheng@163.com`
  (发件人「wellway团队」),验证码已实测发出并可接收;`mailer_otp_length=6` 与 App 输入框一致

### 4. 归档签名
- Xcode → Product → Archive → Distribute App
- 需要 Apple Developer 账号($99/年)+ 证书 + 描述文件(App Store 分发)

### 5. 上架前最终自检
- [x] `xcodebuild` Release 构建通过(2026-08-26 实测 `BUILD SUCCEEDED`,无 error;
      仅若干 `try?` 未使用/`authorizationStatus()` 废弃等非阻断 warning,不影响上架)
- [ ] 真机跑一遍:定位权限弹窗(模拟器不弹,真机首次必弹)
- [x] 测试残留清理(2026-08-26):已删除 4 条中断 `riding` 记录 + `RLS-TEST-*` 测试车辆;
      活动表已随 0014 移除(无 slots 问题)
- [ ] ⚠️ 批量测试用户清理(待你确认):`backend/scripts/cleanup-test-users.mjs` 已就绪(dry-run 已验证,
      146 账号中保留你的 `421975135@qq.com` + 截图演示账号,其余 144 个测试账号待清)。
      确认后执行 `node --env-file=../.env cleanup-test-users.mjs --apply` 即可
- [x] 车型库价格核对(2026-08-26):25 款车型 `price_min/price_max` 已是真实行情
      (如川崎 Ninja 400 ¥49,800、春风 250SR ¥19,980-21,580),非占位示例

### 6. 中国大陆上架:ICP 备案(2026-08-22 补充)

> 2023 年起 Apple 要求:在中国大陆地区 App Store 上架的 App,其**域名必须完成 ICP 备案**。
> 仅用 `*.supabase.co` 云服务、不上自己的网站/域名时,主要影响是隐私政策 URL 需要挂在一个已备案域名上。

- [ ] 买域名(阿里云/腾讯云 .cn 约 ¥30/年)或复用已有域名
- [ ] 通过云服务商(阿里云/腾讯云)提交 ICP 备案:**个人备案免费**,需身份证 + 手机号 + 人脸核验,周期约 7~20 个工作日
- [ ] 备案通过后,把隐私政策(`docs/PRIVACY-POLICY.md`)与用户协议(`docs/TERMS-OF-SERVICE.md`)托管到该域名
- [ ] App Store Connect → App 信息 → 隐私政策 URL 填写该域名地址
- [ ] 若 App 内嵌网页(如政策页)也需用备案域名,避免审核被拒
- [ ] 上架后 30 日内:如使用自建服务器需公安联网备案(纯 Supabase + 静态托管一般无需)

### 7. 合规与运营记录(2026-08-22 补充)

- [x] **管理操作日志**:已实现。执行 `backend/supabase/migrations/0011_admin_audit.sql` 后,内容表任何增删改自动落 `admin_logs`,后台新增「操作日志」只读 Tab(操作人/时间/变更摘要)
- [x] **用户协议**:`docs/TERMS-OF-SERVICE.md` 已按竞品(高德/Strava/Keep 等)条款补齐风险提示、内容授权、免责、未成年人、法律适用
- [x] **隐私政策**:`docs/PRIVACY-POLICY.md` 已覆盖定位/相册/蓝牙权限说明;建议同步发布到备案域名
- [x] App 内协议入口:登录页《用户协议》《隐私政策》完整版;设置页「隐私说明」短版(v2.0,2026-08-25 已在模拟器验证渲染)
- [x] App 隐私清单 `PrivacyInfo.xcprivacy` 已核对并打进 built 包(含 NSPrivacyCollectedDataTypeOtherUserContent)
- [x] 注销账号:App 入口+确认弹窗+后端 `0016_delete_account.sql`
- [x] 注销 Bug 修复:照片删除改走 Storage API(实测上传/删除 200),SQL 只删 `auth.users`
- [x] 注销账号端到端验证(2026-08-26):云端 `delete_my_account()` 已确认与 `0016_delete_account.sql` 一致;
      实测建一次性用户→造数据→以该用户调 RPC(HTTP 204)→auth 用户 404→profiles/vehicles 级联清空,全部通过
- [ ] 上架后定期导出 `admin_logs` 与运营数据,保留至少 6 个月(配合监管与投诉处理)

## 备注
- 后端迁移云端状态(2026-08-26 实测):`0008`(route_favorites 3 列)、`0010`(routes.map_url)、`0011`(admin_logs 9 列)已全部生效;`0014` 社交表(activities / activity_registrations / route_chat_messages)已按合规要求删除;`0015`(ride_presence,擦肩而过)已生效。现网 public 共 15 张表:admin_logs / badges / brands / checkpoints / feedback / models / profiles / ride_checkins / ride_points / ride_presence / ride_records / route_favorites / routes / user_badges / vehicles。
- 后续若重置/重建项目,直接在 Supabase SQL Editor 执行 `backend/supabase/migrations/ALL.sql`(幂等)一次补全。
- 上架前自检已核对(2026-08-26):built 包版本 1.0.0(1)、`ITSAppUsesNonExemptEncryption=false`、`UIBackgroundModes=[location]`、定位/蓝牙/本地网络/相册权限文案齐全、`PrivacyInfo.xcprivacy` 已入包、App 图标已入包。
