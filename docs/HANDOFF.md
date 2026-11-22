# WELL WAY 项目交接文档

> 给"下一台电脑上的 Codex"看的开工说明。读完本文档即可继续开发,不需要用户重新解释需求。
>
> **最新接续点（2026-11-22）**：先读 `docs/HANDOFF-2026-11-22.md`。
> 2026-11-12 那条会话因历史顺序问题被上游持续拒绝（HTTP 400），已只作存档；
> 新对话从新文档接上下文，并注意 `BadgesView.swift` 有未提交改动。
> UI 一律以 `docs/DESIGN-SYSTEM.md` 顶部 v6 为准。

## 0.0 车型库目录重建（2026-10-13）

- **车型库从 7 品牌 / 25 款扩到 281 品牌 / 1953 款**：数据改由 `backend/scripts/catalog/` 的流程从
  「汽车之家 · 摩托车频道」公开车系表生成（列表页车系 + 详情页官方排量），命令见
  `backend/scripts/catalog/README.md`。生成的 `data/catalog.json` 是入库唯一依据，
  `load-catalog.mjs` 幂等 upsert，可反复跑刷新价格。
- **分类从 5 个扩到 9 个**：`跑车 / 街车 / 踏板 / 巡航 / 复古 / ADV / 越野 / 旅行 / MINI`
  （汽车之家叫「冒险」，映射为 `ADV`）。`VehiclePickerView` 的类型胶囊改为横向滚动，
  `admin/index.html` 的类型下拉同步补齐。
- **`GarageService.loadCatalog()` 改成翻页拉取**（500 条/页）：PostgREST 单次上限 1000 行，
  1943 条会被静默截断。排序键改为 `brand_id → sort → id`，保证翻页稳定。
- **排量未知（纯电车型等）不再被算成 0cc 混进「250cc以下」**，而是不参与排量筛选。
- 旧的 `backend/supabase/seed.sql`（手写 25 款）保留但不再作为车型库来源。

## 0.2 车型库缩略图：真车抠图 + 分类插画回落（2026-10-14/15）

- **主链路是真车抠图**：用「汽车之家」车系列表页 `__NEXT_DATA__` 里每条车系自带的 `pnglogo`
  （透明底、官方出的整车抠图，约 1920×1440），缩到最长边 720 的透明 PNG，传到 Supabase Storage
  的 `catalog-images` 桶（公开读），地址写进 `models.image_url`，App 显示这个公开地址
  ——**不直连汽车之家图床**。全流程见 `backend/scripts/catalog/README.md` 的「车型缩略图」一节：
  `fetch-series-logos.mjs`（抓 URL，1943 条全部有图）→ `sync-model-images.py`（下载/压缩/上传/生成 SQL，
  并发 3、断点续跑）→ `psql -f data/model-images.sql`（默认只填 `image_url is null` 的行，`--force` 才覆盖）。
- **回落链路是自绘 9 张分类插画**：目录里新增车型但还没图时列表不开天窗。墨色 `#24262B`、
  透明背景（早期是米白 `#F2EFE9`+深色块，已废弃 —— 见下面「车型图不留不透明底」）。
- **车型图不留不透明底（2026-10-16）**：`ModelThumbnail` 原来是 72×72 深色方块 + 图缩在中间，
  而抠图是 4:3 横构图，塞进正方形上下空掉一大半（实测车只占方块的 88%×54%），
  用户反馈「没填满、视觉差、要透明底」。现在改成：
  1. `ModelPhotoLoader` 下载后**按 alpha 把四周透明边裁掉**（只留 4% 呼吸位，内容区铺满、构图统一），
     实测 4:3 抠图从 88%×54% → **93%×72%**；「您已选择」大图从 77%×77% → **93%×87%**。
     ⚠️ 踩过的坑：位图上下文（`CGContext(data:…)`）**不要**加 `translateBy/scaleBy` 翻转 ——
     画完后缓冲区第 0 行本来就是图片顶行，多翻一次整车就是倒着的（用 2×2 红蓝图实测确认）。
     改完用「渲染出的图 vs 原图」的像素级相关验证：正着 0.953 / 翻转 0.054，别只看"有没有裁到白边"。
  2. 缩略图框改成 96×72（`ModelThumbnail.aspectRatio`，贴合 4:3 横构图），
     「您已选择」大图去掉灰色条 + 深色块，抠图直接落在页面底上。
  3. 9 张插画跟着改成墨色 `#24262B`（否则白卡上会看不见）。
  改回去很简单：`ModelThumbnail` 加回 `Theme.darkCard` 底、`ModelImage` 不裁边即可。
- **⚠️ 版权**：抠图是汽车之家的资源，适合内测/TestFlight 自用；**正式上架前应换成品牌方授权素材
  或用户自拍图**（后台 `admin/index.html` 已支持逐个车型上传到 `catalog-images`）。
- **注意 Supabase 新版密钥的用法**：`backend/.env` 里的 `SUPABASE_SERVICE_ROLE_KEY` 是
  `sb_secret_…` 新格式，调 Storage 时必须放 `apikey` 头；放进 `Authorization: Bearer` 会被当成旧版 JWT
  解析，报 `Invalid Compact JWS` / `AccessDenied`。
- **生成器**：`ios/tools/make_model_type_art.py`（用 Playwright 把 SVG 渲染成透明 PNG，零额外依赖）。
  一次产出三份：`ios/tools/model-art-svg/<key>.svg`（源文件）、
  `ios/WELLWAY/Resources/Assets.xcassets/ModelType<X>.imageset/`（1x=72 / 2x=144 / 3x=216 PNG + Contents.json）、
  `outputs/model-type-art/model-type-art-preview.png`（深色底 9 格预览拼图，带分类中文标签）。
  画布 160 单位、线宽 5；每张按墨迹包围盒归一化到同一内容宽度并居中，保证 9 张看起来是一套。
- **`model_type` → 资源名**：`ModelTypeArt.assetName(_:)`（定义在 `ios/WELLWAY/Core/Theme.swift`），
  未知/缺失分类回落到 `ModelTypeStreet`，不会出现空图。
- **真图优先通道已打通**：`VehicleModel` 新增 `imageUrl`（CodingKey `image_url`），
  `GarageService.loadCatalog()` 的 select 已带 `image_url`；`ModelThumbnail` 有真图时显示真图
  （`scaledToFit`，抠图是 4:3，用 fill 会把车头车尾切掉），没图才回落到分类插画。
  将来拿到授权车图，只要在后台
  `admin/index.html` 逐个车型上传到 `catalog-images` 桶（该字段早就是 `type: 'image'`），App 自动优先显示真图。
- **⚠️ 不要用 `AsyncImage` 加载车型图**：本项目的网络图片统一走 `ModelPhotoLoader`
  （`ios/WELLWAY/Core/Theme.swift`，`@MainActor @Observable`，内存缓存 + 同一 URL 去重 +
  3 次退避重试）。踩过的坑：`AsyncImage` 的请求一旦被取消（视图重建 / 导航转场）会把状态
  **永久钉在 `.failure` 且不重试**，于是「添加车辆」页的「您已选择」大图永远只剩插画回落，
  而列表行却正常（同一份 `image_url`，两条链路表现不一致，很容易误判成数据问题）。
  `ModelPhotoLoader` 把图片放进可观察的 `images` 字典、视图 body 直接读缓存，
  **发起下载的那个 `.task` 被取消也不影响结果**，图片到货后视图自动刷新。
  排查这类问题时，可临时给各分支加 `accessibilityLabel` 探针（`DBG-PHOTO`/`DBG-FAIL`/…），
  然后用模拟器的 AX 树看实际走了哪个分支 —— 比截图比对快得多。
  路线缩略图已改为 `RouteCoverPhotoLoader`（与 `ModelPhotoLoader` 同样的缓存 + 去重 +
  退避重试），不再使用 `AsyncImage`；无封面时绘制深色赛道线稿。
- **还有 10 台无真图**：都是老 `backend/supabase/seed.sql` 里的手写车型（如「本田 PCX160」），
  新目录里没有完全对应的款（目录里是「五羊本田 PCX」），按「留空好过写错」继续回落插画。
  如需补齐，要人工把它们映射到目录里最接近的车系再刷 `image_url`。
- **接入位置**：`VehiclePickerView.modelRow`（72×72 车型行缩略图）、
  `AddVehicleFlowView.selectedCard`（230×153「您已选择」大图，原先是白 `photo` 图标）。
  车库卡片 / 车辆切换页的灰渐变占位**保持不变**：那两处展示的是用户自己上传的车辆照片，不是车型图。
- **模拟器实测**（iPhone 17 / iOS 26.5，`车库 → ＋ → 选择品牌及车辆 → 春风动力`）：
  - 真图版：有 `image_url` 的行（如 春风 500SR / 450MT）缩略图里米白线稿降到 0.1%、
    中间灰升到 16%（= 真实抠图）；没有图的 800NK 仍是米白 6.5% / 中间灰 2.7%（= 插画回落）。
    两条链路同时生效。
  - 插画版（回落态）：6 个可见缩略图底板均正好 216×216 px（=72pt@3x），框内米白墨迹≈2800 像素
    且水平/垂直居中（左右各 35px、上下各 59/61px）；跑车 / 街车 / ADV 的墨迹高度分别为 96 / 87 / 98 px，
    与 SVG 设计比例一致 → 分类映射正确。
  - 修复后复测（车库 → ＋ → 选择品牌及车辆 → 川崎 → 川崎 Z900 已选）：列表 6 行的 DB `image_url`
    与渲染判定全部一致（Z900 `t`→真图、Ninja 400 `f`→插画、Z400 `f`→插画、Ninja 650 `t`→真图、
    Versys 650 `f`→插画；Ninja 1000SX 被底部按钮遮住未判，非 bug）。
    「您已选择」大图（底板 690×459 px = 230×153pt@3x）修复后 `dark≈0.72 / mid≈0.116`，
    与该真图逐像素 MSE=204（插画 MSE=3119）→ 确认真图；修复前是 `dark≈0.932 / cream=0.041 / mid≈0.017`（＝插画）。
  - 判定指标（216×216 缩略图区域 = 截图 x151–366、行高 324、首行 y810）：真图 `mid≈0.09–0.10 / cream≈0.008`；
    插画 `mid≈0.027 / cream≈0.06`。注意行坐标会随滚动漂移，别拿固定坐标当绝对依据。
  - **本机截图看不了图**（CC Switch 代理把媒体内容变成 `Unsupported Image`）时的替代办法：
    `xcrun simctl io <UDID> screenshot` 存 PNG，再用 PIL 统计指定区域的像素分布 / 与参考图算 MSE。

## 0.3 车库首页：加完车辆后跳到「刚加的那辆」（2026-10-16）

- **现象**：在「添加车辆」里加完回到首页，看不到刚加的车（用户反馈"添加完之后首页还是不显示"）。
- **根因**：不是没入库、也不是列表没刷新 —— 是轮播跳错了页。
  `loadVehicles()` 的排序是 `is_default desc, created_at desc`（默认车永远排第 0），
  而 `DesignHomeView` 原来用 `vehicleIndex = newCount - 1` 去"定位新车"，
  这个下标指向的是**最老**那辆（排最后的），于是用户看到一张旧车卡片，以为没加进去，
  反复重加 → 数据库里出现一堆重复车辆。
- **修法**：`GarageService` 增加 `lastAddedVehicleId`（`addVehicle` 成功后写入），
  `DesignHomeView.jumpToJustAddedVehicle()` 按 id 在列表里找下标再跳；
  `vehicles.count` 的 onChange 只保留"删除后把下标夹回范围"。跳完清掉标记，避免后续刷新又拉回去。
- **验证**：模拟器里添加 `川崎 Ninja 1000SX` → 首页卡片立刻变成 `Kawasaki / Ninja 1000SX`
  （改前同一步显示的是旧的 `春风 500SR`）；数据库同一条记录也确实落库。
- **遗留**：`f2a6321e…` 这个测试账号里积累了几台重复车辆（春风 500SR ×3 / 800NK ×2），
  是这次 bug 期间反复添加留下的，需要时可以清掉。

## 0.4 车库卡片显示车型库真车图（2026-10-16）

- **现象**：用户反馈「还是没有显示车辆的图片」——车库首页卡片、车辆切换页缩略图、
  「我的车辆」卡片三处，只有用户**自己拍过照片**才有图；没传过照片就永远是灰色渐变 + 白色机车剪影。
- **根因**：车型库真图（`models.image_url`）只接进了「添加车辆」链路
  （`VehiclePickerView.modelRow` / `AddVehicleFlowView.selectedCard`），
  车库这几处 `else` 分支写的是占位图形，从没查过车型图。
- **修法**：`GarageService` 新增 `model(for:)`（按 `modelId` 取 `VehicleModel`），
  四处 `garage.photos[vehicle.id] == nil` 的回落分支改为 `ModelImage(model: garage.model(for: vehicle.modelId))`：
  1. `DesignHomeView.vehicleCard`（340×143 首页卡片）
  2. `DesignHomeView` 里 `VehicleDetailSheet.header`（88×88 详情弹窗头图；顺带把 `estimatedHeight`
     里「有照片才 +88」改成恒定 +88，因为现在总有图）
  3. `VehicleSwitchView.thumbnail`（84×60 车辆切换行）
  4. `MyVehiclesView.vehicleCard`（340×143 我的车辆卡片）
  优先级：**用户自拍照片 > 车型库真图 > 分类插画**（10 台老 seed 车型无真图时回落插画）。
- **不要给抠图垫灰底**：第一版把真图放在原来的灰渐变占位块上，用户立刻反馈「为什么还是有灰色的底」。
  真图是透明 PNG，现在四处都直接落在白底上（`RoundedRectangle`/`LinearGradient` 占位块已删），
  自拍照片那条分支保持原样（照片是矩形图，需要圆角裁切）。
  实测卡片区域纯白占比从 ~0% 升到 64%~74%，灰(190–250)只剩 2%~4% 的抗锯齿像素。
  ⚠️ 车辆切换页第 1 行（当前车辆）整行有一层 `#F7F7F7` 选中高亮，那是「当前」状态，不是图片底。
- **验证**（iPhone 17 / iOS 26.5 模拟器）：本机看不了图，用「截图 + PIL 抠墨迹包围盒 + 与真图算 IoU」
  逐个核对，每处都命中对应车型：
  - 首页卡片（`春风 500SR`）墨迹 629×358 px（= 209×119 pt，正好是 1.59 宽的抠图按 `scaledToFit`
    塞进 328×131 可用区的高度受限尺寸），IoU 0.71 CFMOTO 500SR / 0.54 第二候选 → 图对且正着（翻转对照明显更低）。
  - 详情弹窗头图 212×119 px，IoU 0.53 vs 0.46 → 正确。
  - 车辆切换页 6 行缩略图逐一核对：500SR / Ninja 1000SX / Ninja 650 / Z900 / RS 457 / 800NK
    全部命中自己的车型（IoU 0.55–0.61，第二名 ~0.47）。
  - 「我的车辆」卡片：500SR 0.87、Ninja 1000SX 0.72、Ninja 650 0.77。
  - 核对时注意：卡片左上角的「默认座驾」黑色胶囊会混进墨迹包围盒，统计前要把它那一片涂白，
    否则同一张图的相关度会被拉低到 0.4 左右（看着像"不匹配"）。
- **顺手修掉「我的车辆」偶发空态**：`MyVehiclesView` 加载中会先显示「还没有车辆」，
  且实测首次加载偶尔真返回空列表（无报错）。原因是 `auth` 刚恢复时请求可能还没挂上 token，
  RLS 对未认证请求**静默返回 200 + 空数组**（已用 curl 复现：无用户 token 查 `vehicles` → `200 []`），
  于是列表为空但 `errorMessage` 也是 nil。现在加 `isLoading`（加载中显示转圈而不是空态）+
  空结果且无报错时 600ms 后补拉一次。
- **⚠️ 版权同 0.2**：真图来自汽车之家的公开抠图，内测/TestFlight 自用可以，**正式上架前要换授权素材**。

## 0. 最新变更（2026-08-25 晚）

> 上一轮真机复测发现的 6 个问题已全部修复（2026-08-29），详见下方「0.1 真机复测修复」；以下为 8-25 及更早的变更记录。

## 0.1 真机复测 6 项修复（2026-08-29）

- **邮箱验证码登录失效修复（关键）**：`ios/WELLWAY/Auth/AuthManager.swift` 的 `verifyEmailCode` 原来丢弃了 `verifyOTP` 的返回值，转而重读 `client.auth.session`；无签名/沙盒环境 Keychain 写入失败时重读抛错，被误报成「验证码填写错误」（服务端其实已成功，`email_confirmed_at` 已写入、verify 请求 HTTP 200）。已改为直接用 `verifyOTP` 返回的 `response.session` 取 session/user，仅落地失败时才回退重读。模拟器全链路验证通过：mail.tm 收码 → 提交 → 登录成功页 → 进入车库主界面。
- **「or」分隔符显示成省略号修复**：`ios/WELLWAY/Auth/DesignLoginView.swift` 给分隔符文字加 `.fixedSize()`，不再被压缩成点点。模拟器 OCR 验证显示完整 "or"。
- **slogan 统一为「好路当骑 同行当悉」**：替换 `BadgesView/SettingsView/RideSummaryView/LoginSuccessView/BrandMarkView` 等全部残留旧文案。
- **路线筛选省市联动**：`ios/WELLWAY/Routes/RoutesView.swift` 内置全国 34 个省级行政区及对应地级市数据，改为「先选省再选市的二级级联」（原为孤立下拉无选项）。筛选逻辑按省/市前缀匹配路线起点。
- **第三方地图跳转**：`ios/WELLWAY/Ride/RidingView.swift` 高德优先用 `iosamap://` 直接唤起已安装 App，未安装时退回 `uri.amap.com` 网页跳转；`ios/project.yml` 补 `LSApplicationQueriesSchemes` 声明（高德/百度/腾讯），需重新生成工程后构建。
- **权限索要补齐（定位优先）**：`ios/WELLWAY/Core/PermissionHelper.swift` 新增 `LocationRequester: CLLocationManagerDelegate`，定位权限最先弹（iOS 17+ 需 delegate 才能稳定触发回调），其余权限间隔 0.6s 依次请求。

> 真机包已构建并签名（`work/DeviceDerivedData/Build/Products/Debug-iphoneos/WELLWAY.app`，证书 `9E15353176ED586653EB622CE78ED5412F7E12BF` + 描述文件 `6c0b646b-b095-4056-8869-58199327a8a7`），待用户插线后 `xcrun devicectl device install app --device DDE17635-19C6-55BC-BDF6-CE01F9476A11 <app 路径>` 安装。

- **邮件模板全部补上验证码**：Supabase `confirmation`/`magic_link`/`email_change`/`recovery` 四个模板均已含「你的验证码是 {{ .Token }}」（email_change 用于邮箱绑定 `update(user: email:)`、recovery 用于重置密码，之前只有链接没有验证码，App 输入框收不到码会卡住）。已 PATCH 云端并回读确认。
- **云端残留清理**：删除 4 条中断 `riding` 记录 + `RLS-TEST-*` 测试车辆；注销账号 `delete_my_account()` 已端到端实测（RPC 204 → 用户 404 → 数据级联清空）。批量测试匿名账号清理待用户确认。
- **App Store 截图素材已产出 9 张**：`outputs/appstore-screenshots/01~09`（1320×2868, iPhone 17 Pro Max 模拟器, 6.9" 档位），覆盖 P房/路线详情/地图全览×2/路线卡片/徽章/骑行记录/骑行总结/骑行中。演示数据挂在测试匿名用户 `cd4f33a1-2e91-4c44-b6c3-5e5a57529ee7` 下（2 条完成骑行+2 徽章+2 打卡+Z900 车辆），详情见 `docs/APPSTORE-CHECKLIST.md` 第 2 节。
- **路线 Tab（第二个 Tab）卡片交互闭环**：`ios/WELLWAY/Routes/RoutesView.swift` 卡片模式点地图块由「进路线详情」改为「进地图全览」（用户习惯：点地图=全览）；上滑折叠后的详情按钮由「查看全览」改为「添加到出发页」（写入 `DepartDraft` 并切到出发 Tab，逻辑与 P 房路线详情一致）。已在 Pro Max 模拟器逐屏验证：路线 Tab → 点地图进全览 → 关闭 → 上滑出详情（显示「添加到出发页」）→ 点击切到出发页且路线已选中。
- **邮件验证码长度已改为 6 位**：Supabase 服务端 `mailer_otp_length` 原为 8（App 输入框是 6 格，填不进去），已通过 Management API `PATCH /v1/projects/{ref}/config/auth` 改为 6（GET 回读确认持久化）。SMTP 发送链路正常（OTP 接口 200）。
- **验证码倒计时文案修复**：`ios/WELLWAY/Auth/AuthView.swift` 两处（注册页/忘记密码页）倒计时归零后不再写死「30秒后…」，改为「现在可尝试再次发送」。已构建并装入模拟器。
- **车库→路线全览→详情 交互闭环**：车库首页推荐卡片进详情漏传 `pickDestinationMode` 导致按钮变「查看全览」且全览页无「添加到出发页」，已修复（`Garage/DesignHomeView.swift` 传 `pickDestinationMode: true`）。全览页 `RouteMapFullscreenView` 底部新增「上滑查看路线详情」提示，上滑或点击后变「查看详情」按钮，点击返回详情页。模拟器已逐屏验证（详情页按钮=添加到出发页 → 点地图进全览 → 提示行 → 查看详情 → 返回详情页）。
- **Management API 调用注意**：本机存在代理（CC Switch 类）会拦截 `https://api.supabase.com/api/v1/...` 返回 Scalar 文档页；正确姿势是 `curl --noproxy '*'` 且路径去掉 `/api` 前缀（`https://api.supabase.com/v1/projects/...`）。
- 个人访问 token 无法通过 Management API 撤销（无对应端点），7 天自动过期；需要立即撤销去 Dashboard → Account → Access Tokens 手动 Revoke。
- **模拟器 UI 自动化备注**：CGEvent 鼠标拖拽会让模拟器触摸状态卡死（后续点击全失效，需 `simctl terminate` + 重launch 复位）；点击可用。自动化验证用 OCR（Vision）+ 自写 `/tmp/mouse` 脚本（swiftc 编译的 CGEvent 点击器）。

## 0.2 V1 内测接口清单落地（2026-09-17，最新）

对应《V1 内测・最终定稿 接口清单》。接口文档见 `docs/API-V1.md`（含端点映射、入参、返回样例、错误码、免责文案、隐私要点）。

**数据库迁移已真正跑在云端**（此前一直卡在"迁移没执行"）：

- `0019_trip_and_rider_stats.sql` + `0020_moto_rules.sql` 已执行，合并包 `backend/supabase/migrations/APPLY_0019_0020.sql`。云端已确认存在:8 个函数（`disclaimer_text` / `haversine_m` / `bearing_delta` / `moto_rule` / `trip_plan_create` / `trip_status_update` / `rider_count_to_dest` / `riders_nearby`）、2 张表（`trip_plans` / `moto_rules`）、`profiles.privacy_agreed_at`、`ride_points.bearing`、`ride_presence.bearing|speed_kmh|trip_id`。
- `0021_drop_vehicle_plate.sql` 已执行（2026-09-17）：车牌功能下线，`vehicles.plate` 物理删除；App（模型/服务/详情/表单）、官网与后台隐私政策、App 内协议文案同步改为「我们不收集车牌号」。改动前的车牌数据备份在 `backend/supabase/backups/plate-backup-2026-09-17.txt`（全库仅 1 行测试值）。
- **执行方式**：`backend/.env` 新增 `SUPABASE_DB_URL`（Supavisor 连接池 `aws-0-ap-northeast-1.pooler.supabase.com:5432`，密码取自用户备忘录「supabase.com」条目）。本机 `psql` 在 `/Applications/Postgres.app/Contents/Versions/18/bin/psql`（不在 PATH）。注意 PostgREST **不提供任何 DDL 通道**，service role key 不能建表建函数，必须走 psql / SQL Editor。
- **和风天气 QWeather 已接通**（2026-09-17，清单第 1 项第三方 API）：个人开发者账号注册后建项目、生成 `API KEY` 凭据，Key 与**专属 API Host** 写入 `ios/WELLWAY/Resources/Info.plist` 的 `QWEATHER_KEY` / `QWEATHER_HOST`（当前 `https://nb5u9ycgw3.re.qweatherapi.com`）。两个实测坑：① 公共域名 `devapi/api.qweather.com` 对新凭据一律返回 `403 Invalid Host`（官方公告公共地址 2026 年起逐步停服），必须用「控制台-设置」里的专属 host；② 旧预警接口 `/v7/warning/now` 已下线（`403 Deprecated`），改用新版 `GET /weatheralert/v1/current/{lat}/{lon}`（路径参数，纬度在前），响应字段 `alerts[].{id,headline,description,severity,issuedTime,color.code,eventType.name}`，其中 `severity`/`color.code` 是小写，代码里 capitalize 后复用原有 `isSevere` 与预警配色。`/v7/weather/now`、`/v7/weather/24h` 在新 host 下正常。模拟器实测：当前位置 `22° 东南风17 87%`（= 和风北京值；同点 Open-Meteo 为 `25° 8km/h 64%`），目的地 `25° 阴 东北风4 65%`，逐小时预报条正常渲染。计费为按量计费，每月前 5 万次请求 0 元。
- **迁移里修掉 2 个真实 SQL 报错**：`bearing_delta` 与 `riders_nearby` 里对 `double precision` 用了 `%`（PG 没有该运算符 → 整包回滚），改为 `::numeric % 360` 再转回 double。

**验收（已跑通）**：

- 新增 `backend/scripts/trip-stats-test.mjs`：两个真实账号走 HTTP API 全链路，**31 项全过** —— 限行匿名可查、`trip_plan_create` 返回 trip_id、未登录被拒、人数统计排除自己/跨城为 0、附近统计三种方位（前方同向不计入 behind、后方同向=1、对向驶来=1）、超半径不计入、状态机 planned→riding→finished、非法状态被拒、结束后退出人数统计并清掉位置心跳、轨迹点 bearing 落库、本人可删轨迹且点位级联删除、`privacy_agreed_at` 可写。
- `backend/scripts/smoke-test.mjs`：原来第 7 节测的 `route_chat_messages` 是 0014 已下线的社交表，测试一直红着。已改为断言聊天/活动/报名三张 UGC 表**确实不存在**（对齐清单"骑手之间无任何交互"），并补 `moto_rule` 冒烟，**10 项全过**。
- iOS：`** BUILD SUCCEEDED **`。

**顺带修掉一个真实 UI bug**：`RiderPlanCard` 原来把拉数据的 `.task` 放在卡片自己身上，而卡片在 `count == 0` 时整体不渲染 —— SwiftUI 不会挂载空视图，`.task` 永远不执行，**人数就永远查不出来、这张卡永远不可能出现**（日志实测只有 `motoRule` 跑了，`RiderPlanCard` 的 task 一次都没进）。已把拉取逻辑上移到永远挂载的 `RideInfoPanel.loadRiderStats()`（同时承担"提交目的地时上报行程"），卡片改为纯展示组件。

**模拟器实测（iPhone 17，真实云端数据，不是 mock）**：

- 出发页：`限行提示 北京市` + `「北京市」的摩托车限行规则暂未收录，请以交管部门公告为准。`、`1位骑友计划前往「城市穿梭线」`（用 service role 造了第二位骑友的行程触发）、常驻免责文案整段。
- 整段骑行闭环（点按钮真跑）：`开始骑行` → 通知权限弹窗 → 定位权限弹窗（文案已是新的"骑行时需要后台持续记录位置…"，说明 usage description 生效）→ 导航方式弹窗显示 `距路线起点 1065.8 km，将先导航至起点`（即用户要的"不在起点就先导航到起点"）→ `WELL WAY 骑行模式` → 骑行中页。
- 骑行中数据库实测：`trip_plans` 由 `planned` → **`riding`**（客户端真的调了 `trip_status_update`）→ 结束时 → **`finished`**（`started_at`/`ended_at` 均落库）；`ride_records` 建出来是 `riding` → 结束 `completed`（duration_s=85）；`ride_presence` 带 `trip_id` 写入、**结束时被删掉**；结束后 `rider_count_to_dest` 回到 0（不再参与统计）。
- 沿途匿名统计：用 `simctl location start --speed=8` 让模拟器真的"骑起来"（拿到 `course` 才有航向），再往 `ride_presence` 塞一位"正南 333m 同向北行"的骑友 → 骑行页出现 **`后方同向 1`** + `仅匿名汇总数字，不可作为会车、避险判断依据`，且**不泄露**该骑友的昵称/车型（写了"不应出现"标记验证）。走完这次骑行共写入 75 个轨迹点、29 个带 bearing。
- 顺带修掉一个数据口径问题：`CoreLocation` 正北的 `course` 会落在 360 附近（实测 359.999999999985），`RideService.handleLocation` 现在统一归一到 `[0,360)`，避免读取方用角度区间判断时漏掉正北。

**模拟器自动化提示（下次省时间）**：`osascript` 仍是 -1719（无辅助功能权限），但**自写 CGEvent 点击器可用**——见 `/tmp/simctl-ui/click.swift`（`swiftc -O click.swift -o click`，用法 `./click <设备x_pt> <设备y_pt>`）。坐标映射靠像素扫描标定 Device Hub 窗口里的设备屏幕矩形（当前：窗口全局原点 `(2329,351)`，设备屏幕在窗口内 `(526.5,84,295,640)`，对应 402×874pt）。截图用 `xcrun simctl io <udid> screenshot`，识别文字用 `/tmp/tabshot/ocr`（Vision，按 375pt 宽归一化）。

**还需要用户做的**：只有和风天气 Key（`Info.plist` 的 `QWEATHER_KEY`，dev.qweather.com 个人开发者申请）。没配会自动降级 Open-Meteo，不影响使用。限行 12 城仍是空条目，需要运营按交管公告填 `moto_rules.rule_text`。

## 1. 项目是什么

WELL WAY 是摩托车出行 App:匿名账号 + 邮箱绑定,核心功能为骑行路线、同目的地人群提醒(同路人聊天)、骑行轨迹记录与打卡徽章、车辆车库、活动报名。

## 2. 仓库结构

```text
backend/    Supabase 后端(migrations / seed / 冒烟测试 / 骑行闭环契约测试)
admin/      管理后台(单文件网页,登录后维护品牌/车型/路线/徽章/活动)
ios/        iOS 原生 App(SwiftUI + Supabase Swift SDK,XcodeGen 工程)
docs/       交接文档
outputs/    UI 原型与设计素材
work/       截图/OCR/构建产物(可删除,见 .gitignore 处理)
```

## 3. 当前进度(Figma wellway 设计稿 86 帧)

### 已实现并验证

| 模块 | Figma 页面 | 实现 |
| --- | --- | --- |
| 主框架 | Tab Bar(首页/队伍/出发/热力轨迹/个人中心) | MainTabView 5 Tab(对应 Figma Tab Bar 292:36);首页=GarageView,队伍=TeamView(通知+同路骑士),出发=DepartView(选车/选路线→开始骑行),热力轨迹=RoutesView,个人中心=ProfileView |
| 认证 | 登录页/注册页/账号密码登录/忘记密码/重置密码/验证码/协议隐私 | AuthView + EmailSignupView + PasswordLoginView + ForgotPasswordView + AgreementView;登录页默认展示,随便看看=匿名进入 |
| P房 | 首页PitHouse/待添加车辆/添加车辆/车辆确认-编辑/删除确认 | GarageView(活动入口+车辆卡片+照片)+ VehicleAddView(照片/昵称/颜色/默认,车牌已于 0021 下线)+ VehiclePickerView(品牌搜索/热门品牌/车型类型排量筛选/无结果)+ 删除确认 + 编辑 |
| 路线(热力轨迹) | 卡片/列表模式/搜索/难度筛选/无结果 | RoutesView(卡片/列表切换、搜索、筛选)+ RouteDetailView(信息/打卡点状态/开始骑行/聊天);入口为底部 Tab「热力轨迹」 |
| 骑行(出发) | 出发选车选线/骑行前权限检查/导航方式选择/骑行中/暂停骑行/骑行结束-轨迹总结/打卡完成-徽章 | DepartView(底部 Tab「出发」,默认车辆卡+路线横滑卡+开始骑行)+ PreRidePermissionView + NavChoiceSheet(WELL WAY/高德/苹果)+ RidingView(后台定位、速度/里程/时长、暂停整屏「继续骑行/结束骑行」、地图轨迹)+ RideSummaryView + BadgeEarnedView |
| 记录 | 我的骑行记录/无记录/记录详情/重命名/删除 | RecordsView(列表+空态)+ RecordDetailView(统计/打卡明细/重命名/删除) |
| 徽章 | 我的徽章/无徽章/徽章详情 | BadgesView(已获得 X/Y)+ BadgeDetailView(条件/获得时间/打卡进度/保存分享卡) |
| 活动 | 活动列表/无活动/活动详情/报名成功/报名已满 | ActivitiesView + ActivityDetailView + RegistrationSuccessView;入口在首页 banner 和「我的」 |
| 社交(队伍) | 队伍/通知列表/同路骑士列表/同路横幅/系统通知 | TeamView(底部 Tab「队伍」:通知+同路骑士入口)+ NotificationsView(徽章/打卡/同路消息派生)+ TeamRidersView(全路线位置上报,表未建回退聊天记录)+ RidersView(路线详情内)+ RidingView 内同路横幅 + NotificationHelper(打卡完成/骑行完成/同路提示本地通知) |
| 个人 | 个人中心/设置/隐私说明/关于与反馈/提交反馈 | ProfileView + SettingsView(权限状态/绑定邮箱/通知开关)+ AboutFeedbackView(反馈提交云端 feedback 表,表未建降级本地) |
| 状态 | 加载中/加载骨架屏/网络错误/删除确认/无结果 | 路线列表骨架屏 RouteSkeletonList + 各列表页 ProgressView + NetworkErrorView(重试)+ confirmationDialog + ContentUnavailableView |

### 后端(已全部线上验证)

- migrations `0001~0005` 已执行;`0006`(活动计数 RPC / ride_records.name / 活动带报名数视图)已写好但**尚未在云端执行**,见第 6 节。
- 冒烟测试 `backend/scripts/smoke-test.mjs`:登录/建档/车型/聊天。
- 骑行闭环契约测试 `backend/scripts/ride-flow-test.mjs`:**16/16 通过**(建记录→轨迹→打卡→重算→徽章→活动报名)。
- 演示数据已种:7 品牌 25 车型 + 3 条北京路线(四惠桥通勤线/香山压弯线/长安街夜骑线)+ 打卡点 + 6 徽章 + 2 活动。幂等脚本 `backend/scripts/seed-demo.mjs`。

## 4. 已确定的技术决策(不要推翻)

1. 商用产品,目标至少 1000 用户
2. 不抓取第三方网站数据,车型库由官方公开信息 + 自己维护
3. 后端:Supabase(Postgres + Auth + Storage + Realtime)
4. 客户端:优先 iOS 原生(Swift);后端平台无关,以后可加 Android
5. UI 风格沿用 Figma `wellway` 设计稿:浅灰背景、白卡片、主色 `#4199FD`
6. 账号体系:匿名账号自动创建 + 邮箱绑定;登录页「随便看看」= 匿名进入
7. 骑行记录状态约束允许 `completed / abandoned / riding`,插入时用 `riding`,结束改为 `completed`;骑行记录关联默认车辆(vehicle_id),骑行页展示车辆名

## 5. 本机运行方式

```bash
# 后端冒烟 + 骑行闭环
cd backend/scripts && npm install
node --env-file=../.env smoke-test.mjs
node --env-file=../.env ride-flow-test.mjs

# iOS
cd ios && xcodegen generate
xcodebuild -project WELLWAY.xcodeproj -scheme WELLWAY \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ../work/DerivedData build
# 装到已启动的模拟器
xcrun simctl install <UDID> ../work/DerivedData/Build/Products/Debug-iphonesimulator/WELLWAY.app
xcrun simctl launch <UDID> com.wellway.WELLWAY
```

## 6. 待办(按优先级)

1. **在 Supabase Dashboard → SQL Editor 粘贴执行 `backend/supabase/migrations/ALL.sql`(一次性包含 0006+0007)**
   - 0006 部分:创建 `activity_registration_count` RPC(活动真实剩余名额)、给 `ride_records` 加 `name` 列(重命名云端同步)、`activities_with_count` 视图
   - 0007 部分:创建 `ride_presence`(骑行中位置上报,15 分钟自动过期,同路骑士真实昵称/车辆/距离)+ `feedback`(反馈落库,管理后台可查)
   - 未执行前 App 已优雅降级:活动名额显示为 slots、重命名为本地、同路骑士回退聊天记录、反馈存本地
2. ~~骑行记录重命名~~:App 已改为云端优先(`name` 列)+ 本地兜底,执行 ALL.sql 后自动走云端,无需再改代码
3. ~~同路骑士距离/车辆~~:已通过 `ride_presence` 表实现(执行 ALL.sql 后生效,当前降级为聊天记录)
4. 车型库价格核对(当前为示例值)
5. ~~App 图标与启动屏~~:已加占位图标(蓝底白路线)+ 品牌蓝启动屏;**2026-08-17 已替换为用户定稿箭头 Logo**(`AppIcon.png` 与 `BrandMark.imageset` 均已更新,登录/注册页品牌标识带箭头图标)
6. ~~提交反馈落库~~:已实现(执行 ALL.sql 后走云端,当前降级本地)

## 7. 需要用户提供

- 车型库真实价格数据(或授权从官网整理)
- 正式 App 图标素材
- Figma 后续设计稿变更(当前 86 帧已全部盘点并覆盖主要功能)

## 8. 最近修复记录

### 2026-08-19(键盘闪动根治 + 用户 6 项 bug 复验)

- **键盘闪动根治(bug 1)**:`AuthAgreementRow.swift` 的固定 `.frame(width: 375, height: 812)` 是认证页最后一个 812 帧,它会让 iOS 26 在键盘弹出时把整页(含品牌区)上推约 105pt。已改为 `.frame(maxWidth: .infinity, maxHeight: .infinity)`,内部元素用 `.position(x:y:)` 定位不受影响,协议行在闭合态回到设计稿 y≈601.5(原 626.7)。连拍实测:注册页邮箱/验证码格子页、忘记密码页、密码登录页的键盘弹起动画中品牌区像素级零位移(顶区 diff=0);协议行键盘态可正常勾选。
- **添加车辆页返回按钮被卡片手势抢占**:`AddVehicleFlowView` 外层 ZStack 的整页 `.onTapGesture { showPicker = true }` 会吞掉返回按钮点击(点返回反而打开选择器,用户会困在该页)。已移除外层手势,保留/补齐 `emptyCard` 与 `selectedCard` 各自的卡片点击手势。实测:返回按钮恢复正常。
- **路线页复验(bug 2)**:卡片模式 `TabView(.page)` 左右滑动换路线(20km→58km)、上滑展开详情卡(出现「查看路线详情」)、`.scrollTransition` 向上折叠动效均在。
- **权限弹窗复验(bug 3)**:`PreRidePermissionView` 等待用户选择,定位→通知弹窗依次停留(连拍 5 帧均在),选完后正常返回出发页。
- **tab3 图标复验(bug 4)**:出发 tab 图标为尖端朝上的 V 形(顶宽 3pt→底宽 16.7pt)。
- **logo 再缩小(bug 6)**:`BrandMarkView.logoWidth` 143→132(图标+英文实际 132×36.3pt,原 143×39.3);slogan 文字框保持 143pt 不被截断,位置不变。
- **模拟器点击校准**:tap.sh 映射修正为设备原点 Mac(127,113) 1:1(旧映射 x 偏移约 23pt,小按钮点不中)。
- 复验:创建新账户(勾选协议后可进)、随便看看(重置 keychain 后匿名登录可进)、密码登录页键盘无闪动。

### 2026-08-17

- **验证码倒计时持久化(优化建议 #5 已落地)**:`ios/WELLWAY/Auth/AuthView.swift` 新增 `CodeCooldown`(UserDefaults 存截止时间),注册/忘记密码流程改为「倒计时未结束时复用剩余时间、不重新发码」。实测:首次发送显示 30s → 杀 App 重启 → 再次发送显示剩余 12s,不重置;`restoreCooldown()` 在视图重建时恢复显示,`CodeCooldown.clear()` 在倒计时结束后清掉过期截止时间。
- **模拟器软键盘不弹出(环境问题,非代码)**:原因 = 模拟器「I/O → Keyboard → Connect Hardware Keyboard」被勾选(默认连 Mac 键盘,软键盘隐藏)。已在菜单取消勾选,并把 `com.apple.iphonesimulator` 的全局 + 设备级 `ConnectHardwareKeyboard` 均写为 `false`(含旧设备 DA0842EB),重启模拟器不再复发;真机不受影响。若再遇到,模拟器菜单 `I/O → Keyboard` 取消勾选或按 `⌘K`。

### 2026-08-15

- **骑行结束总结页白屏(核心 bug)已修复**:`RidingView.finishRide()` 原先把 `RideSummary` 存到 `@State` 再置 `showSummary`,封面展示时存在时序不同步(summary 为 nil → 兜底/白屏)。改为 `.fullScreenCover(item:)` 传值(`RideSummaryItem: Identifiable`),数据随封面原子传入,实测完整骑行闭环(出发→权限跳过→WELL WAY 骑行模式→骑行中→结束→确认→总结页)通过。
- **总结页时长兜底**:无 GPS 轨迹点(如模拟器未授权定位)时 `recalculate_ride_stats` 统计出 `duration_s=0`,现 `RideService.end()` 在本地计时 >0 且云端仍为 0 时补写 `duration_s`,总结页不再显示 00:00。
- **UI 还原注记**:骑行中速度字号已按设计稿 `riding.json` 从 56 调到 64;骑行中结束保存时先移除地图层避免 MapKit 金属层与封面冲突。
- **路线卡片模式整页深色修复**:隐藏导航栏后 ScrollView 顶部插入区与卡片下方漏出白色底(设计稿要求整页 #14151A 深色)。已把背景移到内层 VStack,并给卡片轮播加显式 `Theme.darkBackground`,像素级验证整页深色、路线名/元信息/粉色热度文案正常。
- **设计稿核对结论(2026-08-15)**:首页/登录/路线卡片+列表/记录/徽章/活动(列表+详情)/通知/队伍/同路骑士/设置/个人中心/路线详情/骑行中/骑行总结 逐屏与 `work/designs/*.json` 对照一致;数据为空时按设计稿空态展示。

## 9. 底栏 Tab 图标与选路线交互(2026-08-15 复验)

- **Tab 图标 1:1 还原 Figma(Tab Bar 292:36)**:新增 `ios/WELLWAY/App/TabIcons.swift`(约 180 行),用 `SVGPathParser` 解析 Figma 原始 SVG 路径生成 `UIImage`(template 渲染),5 个图标为:首页(U 形描边 stroke 2 + "Pit" 文字 Semi Bold 11pt kern -1,26×32.7)、队伍(双人形 26×27)、出发(火箭旋转 -44.96° 裁到 24×24 窗口,19.25×33.5)、热力轨迹(指南针环形+指针 evenodd,22×28.3)、个人中心(单人像 24×24 画笔内 translate(4,2),24×34.6)。已逐像素验证图标尺寸/位置与设计稿一致。
- **Tab 切换实测**:模拟器逐一点击 5 个 Tab,蓝色选中态依次落在 63.3 / 132 / 200.7 / 270 / 339.3(pt),对应页面(首页P房/队伍/出发/热力轨迹/个人中心)均正常渲染,无白屏。
- **选路线「黑底固定 + 白色地图/介绍滑动」**:热力轨迹卡片模式整页 #14151A 深色;实测横滑两次,白色轨迹卡 + 路线名/元信息随页滑动,页面背景深色全程不变,与 Figma「路线列表-卡片模式」132:2 一致(卡片 339×430、路线名 28pt 白、meta 14pt #dadada、热度 13pt #dc0964、指示点、右侧露出下一张 19px)。
- **点击坐标换算(验证用)**:模拟器窗口 bounds (439,99,380,819) 时,设备 pt → 桌面 pt 约为 `x' = 447.1 + x*0.905`、`y' = 127 + y*0.905`;底栏图标行设备 y≈818。

## 10. 页面验证记录(2026-08-16)

- **底栏已达标**:`MainTabView` 5 个 Tab 均为纯图标(无中文 label),第 2 个 Tab = `TeamRidersView(title: "擦肩而过")`(同路人列表),非队伍页;首页图标内 "Pit" 文字为设计稿自带,已按 Figma 还原。
- **绑定邮箱持久化 bug 已修复**:`AuthManager.testBindEmail()` 原只改内存 `profile.emailBound`,随后 `refreshProfile()` 从云端拉回 false 覆盖 → 显示回退。已改为写库 `profiles.email_bound=true` + `refreshProfile()`。实测绑定后「邮箱已绑定」稳定显示。
- **已验证页面闭环**:#34 绑定邮箱(粘贴 test@test.com → 获取验证码 → 123456 → 保存 → 回个人中心显示已绑定)→ #59 绑定成功瞬态 → #60 解绑确认弹窗(确认后回「匿名账号/去绑定」)→ #80/#82 品牌/车型搜索 → #54/#55 隐私政策/用户协议 → #37 骑行前权限检查(暂时跳过)→ #52 导航方式选择(WELL WAY 骑行模式)→ #2 骑行中(地图/速度/里程/时长/同路横幅)→ #3 骑行总结(总里程/总时长/平均速度/打卡状态/完成)。
- **#50 同路横幅**:实测出现「该路段当前有 2 名骑士」白色胶囊。
- **#51 系统通知(同路)**:`RidingView.loadRiders()` 内 `ridersCount>0 && !NotificationHelper.isForeground && notifySameway` 才 post,前台不触发;代码就绪,后台场景生效。
- **系统权限 #45-49/#78/#79(2026-11-14 复核)**:当前工程只申请定位(前后台)与通知;照片选择使用 `PhotosPicker`,分享卡通过系统分享面板保存,仅保留相册“仅添加”用途描述。代码未使用 CoreBluetooth、MultipeerConnectivity、NetService 或 Bonjour,蓝牙、Bonjour、本地网络及只读相册权限声明已移除。设计归档中的旧系统弹窗截图不再是当前权限清单。
- **#4 打卡完成-徽章**:`BadgeEarnedView` 已实现,需 `summary.awardedBadge != nil`(真实打卡数据)才出现;0.0km 无打卡数据时总结页不显示 badgeCard,属正常逻辑。
- **#61/#62 地图切换-状态A/B(本轮新增)**:`RidingView` 地图卡右上角展开按钮 → 全屏 `MapSwitchView`(深色底 + 339x430 地图 + 底部半透明黑卡:路线名 28 Bold + 里程/爬升/难度 + 导航模式文案)。顶部「地图 A/B」胶囊点按切换:`stateB=false` 显示「WELL WAY 导航中」pageMark 61,`true` 显示「高德/苹果地图导航」pageMark 62。实测 mark 61↔62 切换正常,底部卡文案同步变化。
- **#29 修改成功(本轮新增)**:`ForgotPasswordView` 增加 `step=3 → successStep`(品牌 + 「修改成功」+ 黑按钮「去登录」),pageMark 按 step 映射(0→19 / 1→26 / 2→28 / 3→29)。实测 忘记密码(任意邮箱)→ 验证码(任意6位)→ 重置密码(任意6位+确认)→ 修改成功 → 去登录回到账号密码登录页,闭环通过。
- **#38 报名已满(本轮新增)**:`ActivityDetailView` 当 `remaining<=0 && !isRegistered` 显示 `fullStateView`(满圆徽章「满」+「报名已满」+ 说明 + 灰底「查看其他活动」),pageMark 38。实测:临时将活动1 slots 调为4(=已报名数)后进入详情显示 #38,验证后已恢复 slots=12。
- **#42 加载中(本轮新增)**:`Theme.LoadingPageView`(返回键 + 「加载中」标题 + 圆环 + 「加载中...」),pageMark 42,用于活动详情数据未就绪的瞬态。实测:临时延迟 4s 验证渲染正常(圆环/文案/返回键),随后已移除延迟代码。
- **#75 提交反馈弹窗(本轮新增)**:`AboutFeedbackView` 重构为 #16 关于页(logo/版本/反馈卡)+ 弹窗(遮罩 + 卡片「意见反馈/说明/输入框/取消/提交」)。实测:设置 → 关于与反馈 → 意见反馈 → 弹窗出现,取消/提交按钮齐全,取消可关闭。
- **点击校准(2026-08-16)**:模拟器窗口实测内容区为 (3472,230) 336x724,`work/audit/click.sh`/`nav.sh` 坐标已按此校准;`MapSwitchView` 展开按钮位于地图卡右上 (360,156),需用 `work/audit/tap`(CGEvent 级)点击,`click.sh` 会被 MapKit 手势吞掉。
- **#35/#53/#69-73/#41 交互逻辑图/设计规范帧**:流程说明类帧,不参与 App 界面渲染,未实现属预期。
- **#84 登录账户页键盘重叠修复(本轮)**:`PasswordLoginView` 新增键盘态位移量(`kbShiftTitle=-100 / kbShiftButton=-110 / kbShiftAgreement=-104.5`),删除原来写死的协议行坐标,统一 `601.5 + kbShiftAgreement`。实测:键盘弹出后 登录账户/输入信息/邮箱框/密码/登录按钮/协议 依次为 243/267/317/381/448/504(归一化换算),与设计稿 368:187 一致,无重叠。
- **#24/#33/#32/#80/#82 添加车辆全屏流程重构(本轮)**:`GarageView` 由 `.sheet` 改为 `.fullScreenCover` 呈现 `AddVehicleFlowView`(新建);选车改为 push 流程:`AddVehicleFlowView`(t2:返回+添加车辆+选择品牌及车辆+空卡片/已选卡片+删除按钮+照片区+底部黑按钮「添加到P房」)→ `VehiclePickerView` 重写为品牌页(#33 热门品牌 4 块+全部品牌行+搜索)/车型页(#32 类型排量筛选+车型行)/无结果页(#82/#80 放大镜+「未找到相关结果」+「清除筛选」)。实测全流程:+ → 全屏添加页 → 空卡片 → 品牌页 → 春风动力 → 车型页 → 选 春风450SR → 回填「您已选择 CFMOTO 450SR」→「添加到P房」→ 保存成功回 P 房显示新车。
- **选择页搜索/返回点击失效修复(本轮)**:`VehiclePickerView` 的 `brandBody`/`modelBody` 全屏 ScrollView 覆盖了头部返回键与搜索框,导致点不到。已把 `header`/`searchBar` 移到 ZStack 最上层;搜索框补 `.submitLabel(.search)+.onSubmit` 收键盘,`scrollDismissesKeyboard(.immediately)`,「搜索」由 Text.onTapGesture 改为 Button。
- **键盘弹出整页上移修复(本轮)**:`KeyboardPageFix`(原私有于 AuthView)提取为共享组件 `ios/WELLWAY/Core/KeyboardPageFix.swift`(探针逐帧补偿系统键盘避让),应用到 `VehiclePickerView`。修复后键盘弹出时搜索栏/返回键保持在设计坐标(不再被推入状态栏、不再不可点),实测 搜索可正常收起键盘、无结果页布局稳定。

### 2026-08-16 收尾轮

- **出发页路线卡单屏修复**:`DepartView` 路线卡横滑改为「单屏一张 + 分页滑动」(`LazyHStack` + `containerRelativeFrame` + `scrollTargetBehavior(.paging)`),卡片地图改为 `frame(maxWidth:.infinity)+height 135`、轨迹点 (30,110)/(306,22)、卡片 `padding(.horizontal,20)`。实测出发 Tab 单卡显示、右缘不露第二张。
- **首页车辆卡点击修复**:`DesignHomeView` 车辆卡原来只有「有照片时点照片」才触发编辑,无照片时整卡点不动。已加 `Color.clear` 透明点击层覆盖品牌/车型/照片/「您已选择」区域(375x250),点击任意位置进「车辆确认/编辑」。实测点击卡片正常打开编辑页。
- **#67 车辆删除确认修复**:原 `GarageView.confirmationDialog` 绑定 `deletingVehicle` 从未赋值(死代码),实际点「删除车辆」直接删、无确认。已移除死代码,在 `VehicleAddView` 增加 `.alert("删除这辆车?删除后该车的骑行记录仍会保留")`(删除/取消)。实测:删除车辆 → 弹窗出现(全屏变暗+居中卡片+双按钮)→ 取消可关闭。
- **confirmationDialog 渲染异常修复(iOS 26.5)**:实测本 App 内 `confirmationDialog` 渲染残缺(遮罩只盖上半屏、取消按钮不显示、位置异常),`.alert` 渲染正常(全屏变暗+居中卡片+按钮齐全)。已将全部 4 处 `confirmationDialog` 改为 `.alert`(文案/按钮不变):车辆删除确认、记录删除(#7 详情)、结束骑行(#2)、请先添加车辆(出发页)。实测记录删除 alert:标题「删除这条骑行记录?」+ 说明 + 取消/删除,无重叠。
- **#74 重命名记录弹窗复验**:`.alert` 渲染正常(居中卡片、全屏变暗、输入框+保存/取消),取消可关闭。
- **无徽章 #40 判定修复**:原 `store.entries.isEmpty` 判定的是徽章定义数(恒 26 条空条目)导致空态永不显示;改为 `earnedCount == 0`。实测空态显示「还没有徽章」+「去骑第一条路线」黑按钮,点击 → 通知切到出发 Tab,单卡正常。
- **Tab 跳转通知**:`MainTabView` 增加 `selectedTab` + `.tag()` + `.onReceive(.switchToDepartTab)`(出发 Tab=2),供「去骑第一条路线」等场景跳转。

### 2026-08-16 用户四项收尾(权限弹窗/徽章页/品牌对齐/底栏 Tab)

- **#78/#79 骑行权限弹窗重写(用户要求 1)**:`ios/WELLWAY/Ride/RidingView.swift` 的 `PreRidePermissionView` 按设计稿 SVG(白卡 327x300 圆角22 + 「"WELL WAY"想访问你的位置/想发送通知」黑标题 + 说明 + 黑色「不允许」/灰色「允许」双按钮)1:1 重写。实测闭环:出发页 → 开始骑行 → 定位弹窗 → 不允许 → 通知弹窗 → 不允许 → 导航选择页;弹窗坐标与设计稿吻合。
- **我的徽章页标题/返回键修复(用户要求 2)**:根因 = 系统导航栏未隐藏叠加拦截点击 + `DesignPageHeader` 的 `padding(.top:36)` 与状态栏重叠。修复:`BadgesView` body 加 `.toolbar(.hidden, for: .navigationBar)`;`DesignPageHeader`(Theme.swift)改为 GeometryReader,`.padding(.top, max(0, 62 - safeAreaInsets.top))` + `.frame(height:86)`。实测:「我的徽章」标题 y≈65(状态栏之下),返回键点击成功回到个人中心。
- **品牌对齐(用户要求 3)**:`LoginSuccessView` 品牌 VStack 改 `alignment: .center`(修复「让擦肩不错过」偏左);`AboutFeedbackView` 按设计稿 133:241 对齐:标题 x 102、logo 改深灰 #24262B 圆角22 + W 26pt、「WELL WAY」全宽居中、「让擦肩不放过」改灰底卡(327x72 #F7F7F7 圆角14 + 15pt Bold #24262B)、意见反馈卡 14pt + chevron #B0B0B0。实测:设置 → 关于与反馈 像素级验证(logo #24262B、slogan 卡 #F7F7F7)通过。
- **底部 Tab 保留梳理(用户要求 4)**:按设计稿逐帧核对(86 帧全部扫描,含 Tab Bar 节点者见下表)后,给 7 个「设计稿无 Tab」页面加 `.toolbar(.hidden, for: .tabBar)`:路线详情、设置、关于与反馈、绑定邮箱、通知列表、活动详情、骑行记录详情。实测:设置/关于/通知/绑定邮箱/路线详情底部纯白(无 Tab),首页/路线列表/我的徽章/我的骑行记录/活动列表底部 Tab 保留。
- **待确认(未改)**:设计稿「添加车辆」135:574 带 Tab Bar(首页 fullScreenCover 打开时隐藏),需把首页加车流程改为 push 才能保留;「同路骑士列表」234:43 无 Tab 但它同时是「擦肩而过」Tab 根页,隐藏会导致无法切 Tab,保持现状。

### 2026-08-16 用户四项收尾·复验轮(build8)

- **添加车辆页错位修复复验(135:574)**:标题「添加车辆」(21,68)、副标题「选择品牌及车辆」(33,129)+ 右侧箭头(319,137)、空卡「添加品牌」(33,201)/「添加车型」(33,224)、底部按钮「添加到P房」(121,637) 全部与设计稿坐标吻合(OCR 实测中心 80.7/137.2/137.4/209/234.4/660.5 vs 设计 78/137/137/208.5/234/659)。
- **选择品牌页错位修复复验(153:1722)**:标题(92,76)、搜索框(28,107 283x37)、热门品牌(24,166)/全部品牌(24,322) 标题、热门 4 块横排(x=24/106/188/270 64x64)、品牌行 y=354 起 40pt 高,OCR 全部吻合。顺手把「热门品牌/全部品牌」字号从 15 改为设计值 14 Bold。
- **骑行总结页重写复验(112:889)**:白底 + 返回(28,74)+ 标题(92,76)+ 深色地图卡(24,112 327x200)+ 数据卡(24,332 327x76 白底 #E9E9EB 描边)+「打卡完成」(24,448)+ 编号圆行 y=476/528 + 底部黑色按钮(24,690 327x48)。发现并修复数据卡列顺序颠倒(原 数值上/标签下 → 改 标签 11pt #9A9A9A 在上、数值 15pt Bold 在下,与设计 l-0/v-0 一致),实测标签中心 355.7 / 数值 383.0 vs 设计 355.5/382。
- **登录页品牌间距复验(第 3 项)**:`DesignLoginView` 品牌块已与注册页 `AuthView.brand` 一致(143x72 @ (187.5,131)),实测登录页 WELL WAY/让擦肩不错过 OCR 基线 0.852/0.818,注册页 0.852/0.818,两页完全一致。
- **全库自检**:rg 无 y=93-99 标题残留;仅剩命中为首页「+」按钮(343,97,设计 328,82 30x30 中心值)与出发页路线卡(187.5,305),均与设计稿一致。
- **验证环境**:build8 BUILD SUCCEEDED 已装模拟器 UDID DA0842EB-8310-4D5D-BD59-D4E7351871E2;骑行总结走完整闭环(出发→开始骑行→跳过车辆→权限不允许×2→WELL WAY 骑行模式→结束→确认)实测。

### 2026-08-16 用户三项收尾轮(build12,可交付)

- **个人中心子页标题/返回键统一(用户要求 1)**:`Theme.DesignPageHeader` 重写为 GeometryReader + ZStack:返回键固定 (28, 62-safeTop+12)、标题 20 Bold 左对齐(width 240,左缘恒为 x=52),不再随标题字数变化。Header 移出 ScrollView(设置/通知),`AgreementView`(隐私说明/用户协议/隐私政策)与 `AboutFeedbackView` 改用该组件并 `.toolbar(.hidden)`;`GarageView` 增加 `showsBackButton` 参数,`DesignHomeView` 支持返回模式(ProfileView/RouteDetailView/DepartView 传 true,首页 Tab 默认 false)。实测 设置/我的骑行记录/关于与反馈/隐私说明 标题左缘 67-71(像素级一致,差异仅为首字字形),返回键均可点。
- **协议勾选统一(用户要求 2)**:新增共享组件 `ios/WELLWAY/Auth/AuthAgreementRow.swift`(勾选圆点中心 (74,y)、文字 10pt #828282 自 x=78 起,「用户服务协议」「隐私政策」可点),登录页/注册页(邮箱+验证码)/账号密码登录三处全部替换为同一组件;未勾选时点「创建新账户/发送验证码/登录」显示红字提示「请先阅读并同意…」并拦截,勾选后提示自动消失。实测三页协议行 OCR 位置一致、提示出现/消失、勾选后流程放行(注册页显示「请输入邮箱」)。
- **Tab 栏黑白配色(用户要求 3)**:`MainTabView.init` 用 `UITabBarAppearance` 全局覆盖:白底、选中黑色、未选中 #9A9A9A(设计稿 token),消除系统蓝。实测像素采样选中槽纯黑、其余灰,无蓝分量。
- **AgreementView 返回键修复**:header 置于 ZStack 最上层(不再被 ScrollView 拦截),实测 设置→隐私说明 返回成功回到设置页。

## 11. 收尾轮(build13,2026-08-16 深夜)

### 本轮修复(均已在模拟器实测)

- **「随便看看」卡死修复**:`AuthManager.signInAnonymously()` 非欢迎分支成功后漏置 `state = .signedIn`,导致一直停在「正在进入 WELL WAY…」白屏。已补 `state = .signedIn`;实测 退出登录 → 勾选协议 → 随便看看 → 正常进主界面。
- **路线详情标题对齐(第 7 项)**:`RouteDetailView` 标题原按设计 112:818 放 y=76,与其他子页(中心 y=74)差 2pt。已统一为 y=74。实测 header:back=(41.5,74)、title=(105,74)。
- **中文错误文案(第 10 项)**:`AuthManager.friendlyError(_:)` 将 Supabase/GoTrue 英文报错映射为中文(密码错误/邮箱未验证/已注册/频繁操作/网络异常/验证码错误等),替换全部 `error.localizedDescription` 赋值。

### 第 5 项验证(欢迎页闪动,实测通过)

- 测试模式走完整链路:注册页填任意邮箱 → 发送验证码 → 验证码页填 123456 → 确定 → **连拍 6 帧(每 0.35s)全部直接是「登录成功页」(WELL WAY/让擦肩不错过),「正在进入 WELL WAY…」加载帧一次未出现**。闪动问题闭环。

### 第 1 项验证(协议间距,实测通过)

- 登录页协议行像素级测量:圆环右缘内容 x=78.8,文字起点 85.5,间距 **6.7pt**(设计目标 7pt)。勾选圆点中心 x=74 与设计一致。注册页/账号密码登录页共用同一 `AuthAgreementRow` 组件,自动同步。

### 第 7 项全页排版审计(2026-08-16 实测汇总)

用改进后的 `work/header_analyze.py`(只取第一暗带,排除正文污染)对 17 个页面统一测量,全部达标:

| 页面 | 返回键中心 | 标题中心 |
|---|---|---|
| 我的徽章/骑行记录/设置/活动/通知/我的P房 | (41.5,74) | y=74 |
| 添加车辆/选择品牌/选择车型 | (41.5,74) | y=74 |
| 绑定邮箱/隐私说明/关于与反馈/活动列表 | (41.5,74) | y=74 |
| 路线详情(本轮已修) | (41.5,74) | y=74 |

其余核对:首页标题「我的P房」中心 (84,82.5)=设计 (71,82.5)+13.5 居中偏移 ✓;出发页底部通栏「开始骑行」按钮位于内容区底部(y 727-778),未压系统 Tab 栏 ✓;路线列表列表/卡片模式、筛选、搜索框渲染正常;记录/徽章/活动空态、通知列表、同路骑士列表、隐私说明、关于与反馈内容均无截断;首页空态「您已选择」下的 `************` 经核对 Figma 设计稿(135:376)原样保留,属设计本意。

### 第 8 项 按钮功能测试结果 + 优化建议

已实测可用:5 个 Tab 切换、全部返回键(12+ 页面)、协议勾选/颤动/持久化、创建新账户(测试模式邮箱+验证码)、随便看看、已有账户登录、忘记密码→重置闭环、添加车辆全流程(+→品牌→车型→添加到P房→首页回显)、车辆编辑、路线详情开始骑行→权限→导航选择→骑行中→总结闭环、记录重命名/删除、绑定/解绑邮箱、徽章/记录/活动空态按钮(去骑第一条路线/去看看路线)、关于与反馈提交弹窗(取消/提交)。

优化建议(未改,待排期):
1. **同路骑士列表行不可点**(擦肩而过 Tab 骑士行无点击反馈),但 UI 文案「最近在路线聊天中发言」暗示聊天功能——建议补「骑士主页 + 私聊/群聊」或移除文案,避免功能不符。
2. 「选择目的地」按钮在无「骑行状态」概念时提示「请先选择状态再选目的地」,建议简化提示或实现状态选择。
3. 活动空态「去看看路线」直接跳热力轨迹 Tab,建议加返回路径或默认选中第一条路线。
4. 首页车辆卡整卡可点编辑,但无明确进入反馈(无箭头/高亮),建议加 chevron。
5. 验证码倒计时 30s 仅在当前页面有效,切后台/杀进程后重置,建议持久化剩余时间。

### 第 9 项 对照行业 app 缺失页面/流程建议(待排期)

- **必补**:骑士/用户主页(资料、座驾、路线、成就)、聊天会话页(列表页文案已出现"聊天中发言")、路线收藏(收藏/我的收藏列表)、骑行中暂停/继续与轨迹实时预览。
- **建议补**:排行榜/赛季、车队/群组管理、离线地图缓存、骑行后社交分享卡(微信/抖音)、车辆保养提醒(里程-based)、多车辆快速切换、推送通知细分开关、骑行数据统计周/月视图。
- **流程优化**:开始骑行前增加路线天气/路况提示;打卡点到达前主动提醒;同路骑士在线状态与距离展示;隐私协议/用户协议入口从设置页常驻。

### 第 10 项 App Store 交付(代码侧已完成)

- `PrivacyInfo.xcprivacy` 已创建并加入工程资源(NSPrivacyAccessedAPICategoryUserDefaults / CA92.1),构建产物已含该文件。
- `Info.plist` 新增 `ITSAppUsesNonExemptEncryption=false`(仅 HTTPS,出口合规免审);版本号 0.1.0 → **1.0.0**。
- 权限用途文案已在位:定位(前后台)/相册仅添加;通知走系统授权;`UIBackgroundModes=location`;仅竖屏。未使用的蓝牙、Bonjour、本地网络及只读相册权限声明已移除。
- App 图标 1024×1024 已配置;启动屏色已配置。
- 错误文案已中文化(见上)。

**仍需你(在 App Store Connect 侧)完成**:
1. 托管并填写隐私政策 URL(可在 GitHub Pages/自有域名放一份,内容可复用 App 内《隐私政策》)。
2. 准备 6.7"/6.9" 截图素材(可用模拟器截图,需 6.9" 机型)。
3. 创建 App Store 记录:名称/副标题/关键词/描述/审核备注(测试账号说明,邮箱验证码走测试模式)。
4. 归档签名:Developer 账号 + 证书/描述文件(Xcode → Archive → Upload)。
5. 合规确认:定位用途为「骑行轨迹记录」,符合指南 5.1.2;无第三方广告 SDK,无跟踪,无需 ATT。

### 第 11 节(build14 收尾轮:个人中心头部统一,实测通过)

**用户反馈**:个人中心每个页面点进去后,返回键和标题位置都不同。

**根因**:5 处页面混用了系统导航栏(`.navigationTitle` + `.navigationBarTitleDisplayMode(.inline)`),系统返回键贴屏幕左缘、标题居中,与全 App 统一的自定义头部(返回键中心 41.5,74 / 标题左对齐起点 x=67,中心 y=74)不一致。

**本轮改动**:
- `DesignPageHeader` 新增 `showsBack: Bool = true`;Tab 根页面传 `false` 时隐藏返回键,标题位置不变。
- `RecordDetailView`(骑行记录详情):系统导航栏 → `DesignPageHeader(title: "骑行记录")`,外层加 `.ignoresSafeArea()`(否则头部被安全区顶到 y=130)。
- `BadgeDetailView`(徽章详情):同上,标题「徽章详情」。
- `TeamRidersView`:Tab2 根(擦肩而过,`showsBack: false`)+ 通知入口(同路骑士,`showsBack: true`)统一改用自定义头部。
- `VehicleAddView`(车辆确认/编辑 sheet):去掉系统导航栏与「取消」按钮,改 `DesignPageHeader`(sheet 顶部即头部,返回键即关闭)。

**实测(逐页 OCR + 像素测量)**:
- 骑行记录详情:back=(41.5,74),title 67..140 y=74 ✓;返回键正常回列表。
- 徽章详情:back=(41.5,74),title 67..140 y=74 ✓;返回键正常回徽章页。
- 擦肩而过 Tab:title 67..140 y=74,无返回键(根页)✓。
- 通知 → 同路骑士:back=(41.5,74),title 67..140 y=74 ✓。
- 车辆确认 sheet:头部位于 sheet 顶部(约 y=130),返回键可关闭 sheet ✓。
- 复查 `rg navigationTitle`:仅剩调试页 `DesignGalleryView`(`-gallery` 启动参数才可见,不影响用户)。

**测试数据**:验证用云端测试记录/徽章已清理(REST 204),模拟器当前会话无残留假数据。

### 第 12 节(build15 收尾轮:补齐缺失页面,实测通过)

**用户反馈/目标第 8-9 项落地**:按第 11 节列出的「必补」清单实现骑士主页、路线聊天、路线收藏,并修复同路骑士列表空态 bug。

**新增页面/功能**:
- **骑士主页** `ios/WELLWAY/Social/RiderProfileView.swift`:头像/昵称/座驾/状态 + 资料卡(同路/座驾);路线上下文时显示「打个招呼」(写入路线聊天)+「进入聊天」;Tab 根页进入时显示互动提示。
- **路线聊天** `ios/WELLWAY/Social/ChatView.swift`:消息气泡(自己右蓝/他人左白 + 昵称/时间)+ 底部输入栏,复用 `ChatStore` 3 秒轮询;`ChatView` 头部 `.ignoresSafeArea(edges: .top)` 修复被安全区压低问题。
- **路线收藏** `ios/WELLWAY/Routes/FavoritesStore.swift` + 迁移 `backend/supabase/migrations/0008_route_favorites.sql`(已并入 ALL.sql):路线详情右上角星标切换;路线列表(列表模式)新增「收藏」筛选 chip;云端表未建时自动回退本地 UserDefaults,功能不中断。
- **同路骑士列表行可点**(优化建议 #1):TeamRidersView / RidersView 行点击 → 骑士主页。
- **路线详情增强**:热度行(今天有 N 位骑友骑行)> 可点进入同路骑士列表;右上角新增聊天入口。

**修 bug**:
- `RidersView.loadPresence` 缺少 `guard !rows.isEmpty else { return false }`(TeamRidersView 有),导致无在线上报时直接置空返回,聊天参与者回退逻辑永远不执行 → 同路骑士列表在路线页恒为空态。已补。
- 路线列表筛选行(城市/难度/里程/收藏)在 375pt 宽度溢出,收藏 chip 被挤到屏外 → 改横向滚动 `ScrollView(.horizontal)`。

**实测(全部通过)**:
- 骑士主页(Tab2 入口):header back=(41.5,74) title y=74 ✓;信息卡正常。
- 骑士主页(路线入口):「打个招呼」→ 按钮变「已打招呼」,云端 `route_chat_messages` 写入 `👋 我来和 骑士 1 打个招呼`(已验证后清理);「进入聊天」入口正常。
- 路线聊天:消息加载(含历史冒烟测试消息)、输入发送(云段落库验证后清理)、头部坐标 ✓。
- 收藏:路线详情星标 62→106 深色像素(未选→选中);列表「收藏」筛选后仅剩已收藏路线(5 条中 1 条);筛选行可横向滚动。
- 同路骑士列表(路线页):修复后显示 2 位骑士(聊天回退),行可点进入骑士主页。

**需要你(一次性)**:在 Supabase SQL Editor 执行 `backend/supabase/migrations/0008_route_favorites.sql`,之后收藏会同步到云端(当前未执行时自动用本地存储,功能已可用)。

### 第 13 节(build16 收尾轮:活动空态跳转 + 验证码倒计时持久化 + 附加项验证)

**用户目标第 8 项优化建议落地 + 附加逻辑项验证**:

- **活动空态「去看看路线」跳转修复**:原 `NavigationLink { RoutesView() }` 在活动页(隐藏 Tab 的 push 页)内 push 新的 RoutesView,该视图无返回键、Tab 也被隐藏 → 用户卡死。改为 `Button` 发送 `.switchToRoutesTab` 通知,`RootView.MainTabView` 新增该通知监听 → 直接切到热力轨迹 Tab(与「去骑第一条路线」同机制)。实测:活动空态 → 点「去看看路线」→ 热力轨迹 Tab 卡片模式正常,无卡死。
- **验证码倒计时持久化(优化建议 #5)**:`EmailBindView` 把验证码发送时刻写入 `UserDefaults`(`emailBind.countdownSentAt`),`onAppear` 恢复剩余秒数;倒计时结束自动清除。实测:发送后 29s → 杀进程重启 → 重新进入绑定邮箱页显示剩余 `4s`(约 26 秒后),未重置为 30s ✓。
- **附加项验证(搜索车辆未选车不显示添加按钮)**:`VehiclePickerView.modelBody` 底部 `confirmButton` 仅 `selectedModelId != nil` 时渲染。实测:选品牌进入车型页,底部按钮区域无黑色全宽按钮(仅车型行 72×72 照片占位)✓;点击车型行出现「已选」+ 底部「添加车辆」按钮 ✓。
- **返回键坐标校准(验证用)**:模拟器窗口内容区原点为屏幕 `(368,148.5)`,设备缩放 `0.8308`(`tapd.sh` 公式);返回键 = 屏幕 (392,211)。旧坐标 (345,73)+0.945 映射已废弃。

**文档产出(第 9/10 项)**:
- `docs/GAP-ANALYSIS.md`:对照行业 App 的缺失页面清单(我的收藏列表/好友/排行榜/车队/安全救援/行程分享卡 + 建议优化流程)。
- `docs/APPSTORE-CHECKLIST.md`:App Store 交付清单(代码侧已完成项 + 需用户在 App Store Connect 侧完成:隐私政策 URL、6.9" 截图、App 记录、归档签名、上架前自检)。

**验证截图存档**:`work/verify/` 新增 4 张(车型未选/已选、验证码倒计时启动/恢复、活动空态跳转)。

### 第 14 节(收尾轮:个人中心子页头部一致性复核 + 上架文案产出)

**用户反馈复核(个人中心子页返回/标题位置不一致)**:逐像素对比 6 个子页截图(`work/verify/profile_{garage,badge,records,settings,activity,notifications}.png`),返回键中心 `x=124px(3x)`、标题左缘 `x=199px` 在全部页面完全一致;代码侧 `DesignHomeView`(P房)与 `DesignPageHeader` 坐标相同(返回 28,74 / 标题 172,74,20pt Bold)。该问题已在第 4 项修复中闭环,复核通过。

**新增文档**:
- `docs/APP-STORE-COPY.md`:App Store Connect 可直接复制的名称/副标题/关键词/描述/审核备注。
- `docs/PRIVACY-POLICY.md`:可直接托管到 GitHub Pages 的隐私政策(联系邮箱为占位符,需替换)。

**仍待用户完成(非代码)**:
1. 在 Supabase SQL Editor 执行 `backend/supabase/migrations/ALL.sql`(0006/0007/0008 云端迁移)。
2. 替换 `docs/PRIVACY-POLICY.md` 联系邮箱并托管为网页,URL 填入 App Store Connect。
3. App Store Connect:建 App 记录、传 6.9" 截图、填上架文案(`docs/APP-STORE-COPY.md`)、归档签名提交。

### 第 15 节(云端迁移状态实测:仅 0008 待执行)

用 service_role key 通过 REST API 实测云端状态(2026-08-17):

| 迁移 | 云端状态 | 探测方式 |
|---|---|---|
| 0006 活动计数/记录重命名 | ✅ 已生效 | `activities_with_count` 视图 200、`ride_records.name` 列 200 |
| 0007 位置上报/反馈 | ✅ 已生效 | `ride_presence` 200(空表)、`feedback` 200 |
| 0008 路线收藏 | ❌ 未执行 | `route_favorites` 404(表不存在) |

**用户只需执行一次**(Supabase Dashboard → SQL Editor → 粘贴执行):
`backend/supabase/migrations/0008_route_favorites.sql`(幂等,可重复执行)。
未执行期间 App 已自动降级到本地收藏(UserDefaults),功能不中断。

### 第 16 节(Logo 替换:新山峰 logo + 图标留边距)

**来源**:用户微信发来的 `wellway-logo第二版.svg`(两座渐变黑山峰,透明底,viewBox 1000×1049.5)。

**处理**:
- 高清渲染 SVG(2048px)→ 按内容 bbox 裁剪 → 等比缩放到 1024×1024 画布的 62%(605×635px)居中,四边留白约 19-20%(iOS 图标安全区),白底。
- 覆盖 `ios/WELLWAY/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`(1024×1024 universal,由 Xcode 自动生成各尺寸)。
- `xcodebuild` BUILD SUCCEEDED,`simctl install` 重装到 iPhone 17 Pro 模拟器。

**验证(2026-08-17)**:
- 已安装容器 `AppIcon60x60@2x.png`(120×120):四角纯白、中心 (10,10,10) 深色、深色内容边距 L26/R26/T25/B24(≈20%)✓。
- 主屏截图 NCC 模板匹配得分 0.94,图标位于 (652,576) 尺寸 184px,深色内容边距 19-20.7% 与源图一致 ✓(截图存档 `work/verify/icon_new_on_home.png`,源图标 `work/verify/appicon_new_1024.png`)。
- 主屏角落略带壁纸蓝色为 iOS 26 Liquid Glass 材质效果,属系统渲染,非资源问题。

**存档**:`/tmp/wellway-logo第二版.svg.png`(高清渲染)、`/tmp/new_appicon_1024.png`(最终图标)、`/tmp/old_appicon.png`(旧图标备份)。

**更新(2026-08-17 晚,变体对比后定稿)**:用户希望 logo 更像"导航箭头",做了 5 个变体对比(`work/verify/icon_v1_current~v5_rot45_notch.png` + `icon_variants_preview.png` 拼图)。最终采用 **V5(旋转45° + 底部箭头豁口)**,理由:方向动感 + 箭头识别度最高,黑白极简不变。已重新构建安装,主屏模板匹配得分 0.946(V1 同屏仅 0.684,确认已切换)。换回其他变体只需复制对应 `work/verify/icon_vN.png` 覆盖 AppIcon.png 后重新 build。

**更新2(2026-08-17 深夜)**:用户澄清"圆角"指 **logo 箭头本身圆角**(非白色卡片)。新增 **V6**:V5 箭头路径加圆角描边(stroke-linejoin=round,半径≈38px),白底方形不透明(上架安全)。已构建安装,主屏 NCC 0.951;已装图标四角 alpha=255、箭头尖端圆角(120px 下顶部宽 4px,非尖点)。存档 `work/verify/icon_v6_rounded_logo.png` + `icon_v6_preview.png`。若要调整圆角大小,改 stroke-width 重新生成即可。

**更新3(2026-08-17 深夜)**:用户觉得 V5 尖角"太普通",新增 3 个辨识度方向(对比图 `work/verify/icon_v789_preview.png`):V7 内层右移错位、V8 整体不对称、V9 右下切角。**当前采用 V7(内层错位)**:既有动感又不失箭头识别度。已构建安装,主屏 NCC 0.973,图标不透明、留边 20% ✓。

**更新4(2026-08-17 深夜,图标定稿)**:用户确认最终图标 = **方案C**:圆角箭头 + 外层用 .ai 精确渐变(黑→#333,底部20%纯黑)+ 内层浅灰渐变(#d9d9d9→白)。对比过程:两层同色(内层看不见)→ 内层白色(太割裂)→ 中灰/暗灰(用户仍选回 C)。当前模拟器安装 `work/verify/icon_v6_grad_inner.png`,AppIcon 源文件已替换。此前生成的 D/E/F 方案存于 `work/verify/icon_v6_d_mid.png`、`icon_v6_e_tone.png`(F 未落盘)。

**更新5(2026-08-17 深夜,App 内品牌位)**:用户要求"点击图标进去之后的 wellway 上也要加入这个图标"。已新建 `ios/WELLWAY/Core/BrandMarkView.swift`(方案C 箭头 logo 48pt + WELL WAY/让擦肩不错过 文字块,`textCenterY` 控制文字中心保持设计稿位置),资源 `Assets.xcassets/BrandMark.imageset`(1x/2x/3x 透明底)。替换品牌块:AuthView.swift 3 处、DesignLoginView.swift 1 处、LoginSuccessView.swift 1 处;RootView.swift 加载页加 `Image("BrandMark")` 32×33。登录页 logo 原被灵动岛遮挡,已把 4 处 `textCenterY: 131 → 170`(文字块中心保持 170pt,logo 顶部≈78pt 完全避让灵动岛,截图实测岛止 152px、logo 起 240px @3x)。构建 BUILD SUCCEEDED 并重装验证;AppIcon 校验和仍为 `icon_v6_grad_inner.png`(方案C,未混入 V5/V7 等变体)。

**更新6(2026-08-17 深夜,App 内品牌位修正)**:用户指出"我当时选的不是这个图标吧"——核查发现 App 内 BrandMark 之前用的是**另一款分叉双箭头**(粗壮实心+中间竖缝,与方案C 完全不同),而 AppIcon 校验和始终是 `icon_v6_grad_inner.png`(方案C,未串)。已修复:从 `work/verify/icon_v6_grad_inner.png` 内容 bbox(208,195)-(814,828)按"白度→alpha"转换(纯白背景/底部豁口→透明,近白边缘线性渐变抗锯齿),1x/2x/3x(160×167/320×334/480×501,3% 呼吸边距)重新生成 `BrandMark.imageset`。定量验证:方案C 裁剪 vs 新 BrandMark 灰度 NCC=0.988、形状掩码 NCC=0.968;模拟器登录页截图 logo 区域呈"圆角中空+底部豁口",与方案C 一致。BUILD SUCCEEDED 并重装验证。存档截图 `/tmp/login_logo_v3.png`。

**更新7(2026-08-19,tab3 图标定稿 + 路线页上滑翻滚)**:
- **tab3(出发)图标修正**:此前把品牌箭头旋转 -30° 让尖端竖直朝上,与用户参考图(`大小箭头.png`/`资源 4.png`,尖端朝右上斜 60°)不一致。已改为**保持 SVG 原始方向渲染**(`TabIcons.rocket` 去掉 `rotated(by:-30°)`,仍保留大箭头+顶层小箭头双层与 S/A 曲线解析)。定量验证:tab bar 截图裁剪图标 vs 参考图 IoU **0.933**(改前 0.47),主轴角度 -60.2° vs 参考 -59.9° ✓。
- **路线页上滑动效**(`RoutesView.swift`):
  - 卡片 `scrollTransition` 翻滚(`tumble`):单卡片页滚动相位实测只到 ±0.2,改为 ×5 放大 + 二次曲线,卡片离屏折叠约 110°,配轻微缩放/位移/淡出;拖动中帧截图 OCR 确认地图卡 3D 透视倾斜(标题左移至 x=0.095)。
  - 新增 `arrowRoll`:品牌箭头自身随滑动做 720° 3D 翻滚(轴 x:0.5,y:1)并放大 1.9×,上划即出现视频里「快→慢翻滚」的箭头动效;空闲时保留原有 FlyInArrow 循环(飞入→慢滚→定格)。
  - 移除 `tumbleLogPhase` 调试代码。

### 第 17 节(2026-08-20 晚:卡片折叠动效重做,对齐已确认的 HTML 原理)

用户确认参考动效:另一对话产出的 `card-fold-rendered.html`(黑色卡片 0°→88° 翻折收进灵动岛)。本轮重写 `RoutesView.swift` 折叠逻辑,废弃旧的「sin 翻滚 0→75→0 + 整体缩放 0.30」(落定是平面小卡片,非胶囊/长条):

- **滚动驱动单一进度** `foldPosP`:拖动 1:1 跟手,角度/收窄/位移全部由它派生;松手 spring 吸附 0/1(移除 `foldFlyP`)。
- **3D 翻折**:地图卡 `rotation3DEffect(0→88°, axis x, perspective 0.85)`,终点保留可见薄片(88° 不 90°);飞行中呈上窄下宽梯形(实测:顶部宽 244 → 底部宽 333 @3x)。
- **同步收窄**:`scaleEffect(x: 1→0.38)`(transform,非 frame),折叠后薄片 ≈127×17pt,停在灵动岛正下方(卡中心 315 → 药丸中心 70,线性)。
- **文字层独立**:路线名/meta/热度/分页点不参与 3D,单独上移 70pt + 前 20% 淡出(「仅卡片有动效,文字正常显示」)。
- **详情内容**:随上滑 1:1 上移,折叠完成时顶边对齐薄片底边(遮挡线),内容完整露出。
- 移除旧 foldSheet 的整块白底(3D 旋转时的闪白来源)。

**实测截图**:`work/fold-verify/`(1-展开 / 2-飞行中 / 3-收进灵动岛 / 对比图)。BUILD SUCCEEDED,模拟器已安装。

### 第 18 节(2026-09-11 深夜:Tab 栏 5 个图标线宽统一)

第 3 个 Tab(出发)改用用户定稿的品牌 logo(`Assets.xcassets/TabDepart`,笔画实测 **1.65pt**)后,其余 4 个 Figma 图标明显更粗(2.0~2.7pt),用户反馈"这些图标线条的粗细不一样"。本轮把 4 只收细到与 logo 同一重量:

- `ios/WELLWAY/App/TabIcons.swift`:`makeImage(thin:)` → `makeImage(trim:)`(单位 pt/边);`erodeAlpha`(1px@6x 整数腐蚀,步进 0.33pt 太粗)换成 `trimAlpha` —— 先求到背景的 chamfer 距离场(5/7 权重,单位 1/5px),再按半径截断 alpha,边界 0.6px 线性过渡做反锯齿,实现亚像素级收细。
- 各图标 trim:首页 `0.17`、擦肩而过 `0.28`、热力轨迹 `0.39`、个人中心 `0.46`(品牌 logo 资源不动)。
- **验证**:模拟器截图后把 alpha 上采样 4× 做距离变换取骨架中位数(亚像素线宽)——改前 首页 2.00 / 热力轨迹 2.33 / 擦肩而过 2.05 / 个人中心 2.36pt(logo 1.65);改后 5 只全部 **1.65~1.67pt**(与 logo 差 ≤0.02pt)。图标外框尺寸基本不变(72×69 / 70×71 / 69×70 / 77×61 / 58×71 px @3x)。
- 对比图:`outputs/wellway-tab-stroke-20260911.png`,BUILD SUCCEEDED 并重装模拟器。

### 第 19 节(2026-09-11 深夜:出发 Tab →「更换车辆」页)

**问题**:出发 Tab 点车辆卡片进去的是首页那套车库(`GarageView(showsBackButton: true)` → `DesignHomeView`),排版与首页 P房一模一样,还带着「选择目的地」按钮,但目的地/路线在出发页已经选好。

**新增** `ios/WELLWAY/Garage/VehicleSwitchView.swift`(出发页专用,刻意与首页 P房区分):

- 左上返回键带「出发」字样;标题「更换车辆」+ 副标题「选择本次骑行使用的车辆」。
- 竖排车辆列表(84×60 缩略图 + 品牌英文名 + 车型 + 骑行统计行),当前默认车带描边与「✓ 当前」胶囊;点其它行即切换默认车并 dismiss 回出发页。
- 车辆有骑行记录时显示「总里程 x km · 骑行 n 次 · 累计 h 小时」,没有记录时显示「这辆车还没有骑行记录」。
- 空状态内嵌「添加车辆」入口;右上角 `+` 与车库首页一致。
- **没有**「选择目的地」按钮。

**改动**:

- `Ride/DepartView.swift`:`navigationDestination` 里 `GarageView(showsBackButton: true)` → `VehicleSwitchView()`;新增 `.onReceive(.defaultVehicleChanged)` 刷新出发页车辆卡片。
- `App/RootView.swift`:新增 `Notification.Name.defaultVehicleChanged`。
- `Garage/GarageService.swift`:新增共享 `loadRideStats(userId:)`;`GarageView.loadRideStats()` 改为调用它,删掉重复的 `RideStatRow`。
- 统计行用**单个 `Text` 拼接**(多段 `Text` 放 HStack 会被逐段压成省略号,布局时实际踩到)。

**验证**(模拟器逐步点击实测):

- 进入:出发页点车辆卡 → `n3.png` OCR「<出发 / 更换车辆 / 选择本次骑行使用的车辆」+ 4 辆车,页面上「选择目的地/推荐路线/最近骑行/查看全部」命中数 **0**(与首页 P房确实不同)。
- 返回键:点左上「<出发」→ `n8d.png` 回到出发页(标题「出发」+ 车辆卡)。
- 切换:点某辆车 → 自动返回出发页,车辆卡同步更新(改为春风 500SR 后 `n5.png` 首页 P房「默认座驾」也同步)。
- 骑行记录态:`p4.png` 同一页同时出现「总里程 128.4km·骑行6次·累计5.2小时」与「这辆车还没有骑行记录」两种行,证明有/无记录两个分支都会渲染。

对比图 `outputs/wellway-depart-vehicle-switch-20260911.png`。BUILD SUCCEEDED 并重装模拟器。

**注意**:

- 设计稿 78 张导出图里**没有**「更换车辆」页;`work/figma-ocr2.txt` 的交互说明也只写了「我的P房 · 车辆卡片 ＞ 车辆确认/编辑」(= `screen_60/61`,内容仅上传照片/昵称/车牌/颜色/设为默认车辆/保存),**骑行记录只归「我的骑行记录」**(`screen_17/28/78` → `ios/WELLWAY/Ride/RecordsView.swift`,入口在个人中心)。即「车辆页显示骑行记录」在稿子里没有先例,本页的每车统计行(总里程/次数/累计时长,与车库首页同口径)是新加的,空态文案「这辆车还没有骑行记录」呼应 `screen_28` 的「还没有骑行记录」。
- 本页是按要求**新建**的页面,不是找回旧页面。
- 测试期间把账号默认车切成了 Aprilia RS 457,已还原为 **CFMOTO(春风)500SR**(首页 P房与出发页均已确认)。
- 验证骑行统计用的 `-demoRides` 假数据开关**已删除**,现在跑的是真实数据。

## 调试启动参数补充（2026-11）

- -garageempty：GarageService.loadVehicles 直接返回空数组，用于复检「还没有车辆」首屏与底部「添加车辆」CTA。
- -garageskeleton：加载完成后仍停在骨架屏 25 秒，用于比对骨架与真实首页的坐标是否一致。

两个参数只在启动时生效，不影响正式流程。
