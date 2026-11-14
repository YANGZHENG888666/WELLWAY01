# WELL WAY · 接口配置与合规清单

> 用途：上线前逐项核对「哪些接口需要配置 / 哪些已内置免配置」，并标注中国法规合规要求。
> 配套文档：`DEPLOY.md`（部署）、`docs/PRIVACY-POLICY.md`（隐私政策）、`docs/APPSTORE-CHECKLIST.md`（上架）。

## 一、需要配置的接口 / 服务

| # | 服务 | 用途 | 配置位置 | 状态 | 中国合规要求 |
|---|---|---|---|---|---|
| 1 | Supabase 数据库 | 路线/打卡/徽章/车辆/骑行记录等全部业务数据 | iOS：`ios/WELLWAY/Resources/Info.plist`（`SUPABASE_URL` / `SUPABASE_ANON_KEY`）；后端：`backend/.env`；后台：`admin/index.html` 顶部常量 | ✅ 已配置（`hyfxpcwbhfgmtwjhcxdn.supabase.co`） | ①数据出境：《个人信息保护法》第 38/40 条——个人信息存储于境内，跨境传输需安全评估/标准合同；当前托管在国际数据中心，上架前需换国内区（如阿里云 Postgres、腾讯云，或 Supabase 国内区）并更新隐私政策「跨境传输」说明。②后端需 ICP 备案 + 等保 2.0 二级。 |
| 2 | SMTP 邮件 | 邮箱绑定验证 / 忘记密码（后台已做"忘记密码"页） | `backend/.env`：`SMTP_HOST/PORT/USER/PASSWORD` | ⚠️ 未配置（当前为空） | 邮件服务需国内持牌服务商（阿里云邮件推送 / 腾讯云 SES / 163 企业邮）；不得用于营销，仅账号安全用途。 |
| 3 | 数据库备份连接串 | 完整 SQL 备份（`backend/scripts/backup.sh`） | `backend/.env`：`SUPABASE_DB_URL` | ⚠️ 未配置（可选） | 备份数据含个人信息，须加密存储、访问留痕。 |
| 4 | 高德地图（外部跳转） | 「高德地图」导航选项 | 代码内 URL Scheme `iosamap://` + `Info.plist` 的 `LSApplicationQueriesSchemes` | ✅ 已配置（无需 key） | 地图数据由高德提供，合规；若后续改 App 内嵌地图，需高德开放平台企业资质 + SDK key，并列入隐私政策第三方 SDK 清单。 |
| 5 | Apple 地图（外部跳转） | 「苹果地图」导航选项 | 代码内 `maps.apple.com` URL | ✅ 已配置（无需 key） | 中国大陆 Apple 地图数据由高德提供，合规。 |
| 6 | 推送通知（如需） | 骑行提醒/活动通知（当前未接入） | 未接入 | ⛔ 未配置 | 国内上架需厂商推送通道（小米/华为/OPPO/vivo）或持牌聚合推送（极光/个推），APNs 仅作为补充；推送内容须在隐私政策明示，且需用户授权。 |
| 7 | 域名与托管 | 后台永久地址（当前 GitHub Pages 临时方案） | GitHub Pages / 自有域名 | ⚠️ 需固化 | 对外提供服务的域名需 ICP 备案（工信部）；GitHub Pages 为境外托管，正式运营不建议作为业务入口。 |

## 二、已内置、免配置的接口（本次已完善）

| 接口 | 实现位置 | 说明 | 合规注意 |
|---|---|---|---|
| 实时天气 + 逐小时预报 + 气象预警 | `ios/WELLWAY/Core/QWeather.swift`（**和风天气 QWeather**，Key/Host 配置在 `ios/WELLWAY/Resources/Info.plist`） | 出发页「骑行参考」双地天气对比、逐小时预报条、灾害预警条、天气适宜度 | ✅ 国内持牌数据源。⚠️ Key 内嵌客户端只能算内测方案（可被反编译取出），正式上架前改由后端代理转发；未配置 Key 或和风报错时自动回退 Open-Meteo（`RideInfoModules.swift` 的 `fetchSmart`），不影响功能。预警走新版 `GET /weatheralert/v1/current/{lat}/{lon}`（旧 `/v7/warning/now` 已下线）。天气适宜度只算温度、天气、风、降水与气象预警，**不含空气质量**。 |
| 空气质量 AQI | `ios/WELLWAY/Ride/RideInfoModules.swift`（Open-Meteo Air Quality） | 「当前位置空气 AQI xx」独立一行，与目的地天气分开 | 文案按 **US AQI** 六档：良好 / 中等 / 敏感人群不健康 / 不健康 / 非常不健康 / 危险（如 169 → 不健康）；不再使用中国 HJ 633-2012 的「中度污染」等文案。AQI 只取当前位置且异步到达，**不并入天气适宜度评分**。**数据源仍是境外公共接口**，正式版建议换国内持牌源。 |
| 当前位置地名（反向地理编码） | `ios/WELLWAY/Core/LocationFetcher.swift`（系统 CLGeocoder） | 「当前地点」显示真实地名（如「杭州市·西湖区」） | 定位须最小必要原则：仅在用户主动进入「骑行参考」时获取单次位置；已在隐私政策第 4 条说明。CLGeocoder 数据由苹果（国内合作方）提供。 |
| 定位 | 系统 CoreLocation（`OneShotLocationFetcher` / `RideService`） | 路线起点定位、骑行轨迹 | 后台持续定位需在隐私政策 + 系统弹窗文案中说明用途（已配置 `NSLocationAlwaysAndWhenInUseUsageDescription`）；《个人信息保护法》要求单独同意 + 可撤回。 |
| 拥堵预估 | `ios/WELLWAY/Routes/RoutesView.swift`（本地启发式） | 「骑行参考·拥堵预估」 | 纯本地算法不采集数据，合规；如需真实路况需高德交通态势 API（企业资质 + key，见上表 #4）。 |

## 三、法规红线检查（上线前必须满足）

1. **个人信息保护（PIPL）**：位置、车辆、骑行轨迹均为个人信息 → 已具备隐私政策（`docs/PRIVACY-POLICY.md`）、权限最小必要、用途限定。上架前补齐：第三方 SDK 清单、跨境传输说明、数据处理者名称（公司主体或个体户）。
2. **数据本地化（《数据安全法》《PIPL》）**：正式运营必须把数据库换到境内或完成安全评估；当前 Supabase 国际数据中心仅适合开发演示。
3. **地图/天气/导航数据资质**：展示国内地图与导航数据需持牌服务商（高德/百度已具备）；天气/空气质量需国内持牌源。当前跳转式导航合规，内嵌式需上表 #4 配置。
4. **实名制（《网络安全法》第 24 条）**：本应用已去除聊天/活动等社交功能；「擦肩而过」仅展示匿名车型/徽章信息，不开放私信、主页、关注，属轻展示，不构成社交平台；若后续恢复社交功能，需实名认证 + 内容审核 + 属地网信部门要求。
5. **App 上架材料**：软件著作权、ICP 备案（域名/服务器）、隐私政策 + 用户协议（`docs/TERMS-OF-SERVICE.md`）、隐私检测报告（国内安卓渠道要求）；App Store 中国区另需遵守苹果审核条款。
6. **未成年人保护**：本应用无儿童内容，仍建议在隐私政策中声明不面向 14 岁以下儿童（已覆盖）。

## 四、快速核对表

- [ ] `backend/.env` 补齐 SMTP（找回密码可用）
- [ ] 数据库换境内托管或完成跨境安全评估
- [ ] 后台域名 ICP 备案
- [ ] 正式版天气/AQI 切换国内持牌数据源
- [ ] 隐私政策补充：第三方 SDK 清单 + 数据处理者名称
- [ ] 若内嵌地图：配置高德 SDK key 并更新隐私政策
