# WELL WAY V1 内测 · 后端接口文档

> 版本:v1.0(2026-09-17) · 适用:WELL WAY iOS 内测版(TestFlight)
> 本文档对照《V1 内测・最终定稿 接口清单》逐条给出**请求方式 / 请求头 / 入参 / 返回 JSON 样例 / 错误码**,
> 并标注每个接口在当前代码里的实现状态(`✅ 已有` / `🆕 本次新增` / `⏸ 暂不开发`)。

---

## 0. 架构与通用约定

### 0.1 后端形态(重要)

V1 后端**不使用自建服务器**,而是 Supabase(Postgres + Auth + Storage + PostgREST):

- 数据库表 → PostgREST 自动暴露成 REST:`https://<project>.supabase.co/rest/v1/<table>`
- 数据库函数 → RPC:`POST https://<project>.supabase.co/rest/v1/rpc/<function>`

因此清单里的 `/api/xxx` 是**产品语义路径**,下表给出与真实端点的对应关系(文档其余部分按真实端点书写,方便直接联调):

| 清单语义路径 | 实际端点 | 方式 |
| --- | --- | --- |
| `GET /api/moto/rules` | `/rest/v1/rpc/moto_rule` | POST |
| `GET /api/weather` | 和风天气(客户端直连,V2 可换 Edge Function 代理) | GET |
| `POST /api/trip/plan` | `/rest/v1/rpc/trip_plan_create` | POST |
| `PUT /api/trip/status` | `/rest/v1/rpc/trip_status_update` | POST |
| `GET /api/rider/count` | `/rest/v1/rpc/rider_count_to_dest` | POST |
| `GET /api/rider/nearby` | `/rest/v1/rpc/riders_nearby` | POST |
| 轨迹创建/上传/列表/回放/统计 | `/rest/v1/ride_records`、`/rest/v1/ride_points`、`rpc/recalculate_ride_stats` | GET/POST/PATCH/DELETE |

> 为什么不用自建 Node 服务:内测阶段单机并发低,Supabase 免费额度足够,且省掉一台服务器与 HTTPS 证书;
> 所有"匿名汇总"逻辑都放在 `security definer` 函数里,数据库层直接保证**只出数字、不出个人信息**。

### 0.2 环境与鉴权

| 项 | 值 |
| --- | --- |
| Base URL | `SUPABASE_URL`(App 从 `Info.plist` 读;后端在 `backend/.env`) |
| 匿名 Key | `SUPABASE_ANON_KEY`(`apikey` 头,可公开) |
| 用户登录态 | Supabase Auth 的 `access_token`(JWT) |

**所有请求必带头**:

```http
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <access_token>        # 未登录时也放 anon key,配合匿名登录
Content-Type: application/json
```

写操作建议带 `Prefer: return=representation`(让 PostgREST 回写后的整行数据)。

### 0.3 错误码规范

PostgREST / Postgres 原生错误(所有表接口共用):

| HTTP | code | 含义 | 处理 |
| --- | --- | --- | --- |
| 400 | `PGRST102` | 请求体不是合法 JSON | 检查入参 |
| 401 | `PGRST301` | JWT 缺失/过期 | 重新登录(匿名登录也要先拿 token) |
| 403 | `42501` | RLS 拒绝(访问了别人的数据) | 只能读写 `auth.uid()` 自己的行 |
| 404 | `PGRST116` | 期望单行但 0 行 | 记录不存在或不属于当前用户 |
| 409 | `23505` | 唯一键冲突(如重复车辆) | 提示"已存在" |
| 422 | `23514` | check 约束不满足(如 status 非法) | 校验入参枚举 |
| 500 | `P0001` | 函数内 `raise exception` | 见各接口的 `app_code` |

错误响应体统一长这样:

```json
{
  "code": "23514",
  "details": null,
  "hint": null,
  "message": "new row for relation \"trip_plans\" violates check constraint \"trip_plans_status_check\""
}
```

**业务级错误码**(新增 RPC 里 `raise exception` 抛出,`message` 前缀即 `app_code`,App 按前缀匹配):

| app_code | 场景 |
| --- | --- |
| `AUTH_REQUIRED` | 未登录(匿名也没登录)调用需登录接口 |
| `TRIP_NOT_FOUND` | 行程不存在/不属于当前用户 |
| `TRIP_STATUS_INVALID` | 行程状态不是 `planned/riding/finished/canceled` |
| `BAD_COORD` | 经纬度越界(纬度 ±90 / 经度 ±180) |

### 0.4 固定免责文案(UI 常驻,后端也随接口返回)

```text
⚠️ 提示:本 APP 仅展示城市摩托车限行政策文字摘要、天气参考。点击导航将跳转至高德地图,请手动切换高德摩托车路线。位置统计存在 GPS 延迟、定位误差;骑手数量仅匿名汇总数字,不可作为道路会车、避险判断依据。政策、天气存在变动,信息仅供参考,出行请以交管、气象官方公告为准,不可作为通行唯一依据。
```

该文案在数据库里以 `public.disclaimer_text()` 提供,`moto_rule` / `riders_nearby` / `rider_count_to_dest` 的返回体都带 `disclaimer` 字段,App 端不再硬编码第二份。

---

## 1. 第三方 API

### 1.1 和风天气 QWeather(实时 / 逐小时 / 灾害预警)

| 项 | 说明 |
| --- | --- |
| 用途 | 实时天气、逐小时预报(24h)、气象灾害预警 |
| 申请 | https://dev.qweather.com/ → 注册 → 控制台「项目管理」创建项目 → 生成 **API Key**(免费开发版:个人开发者可用,含每日调用量上限) |
| 域名 | 开发版 `https://devapi.qweather.com`,免费订阅通常需走 `https://<你的专属域名>.re.qweatherapi.com`(控制台可查) |
| 认证 | Query 参数 `key=<QWEATHER_KEY>`;V2 起也支持 JWT(内测用 Key 即可) |
| 配置位置 | App:`ios/WELLWAY/Resources/Info.plist` 的 `QWEATHER_KEY`(`AppConfig.qweatherKey` 读取) |
| 降级 | 未配置 Key 时自动回退到 Open-Meteo(仅实时天气,无小时预报/预警),UI 不报错 |

**QWeather 侧调用(3 个)**:

```http
GET {QWEATHER_HOST}/v7/weather/now?location={lon},{lat}&key={KEY}&lang=zh
GET {QWEATHER_HOST}/v7/weather/24h?location={lon},{lat}&key={KEY}&lang=zh
GET {QWEATHER_HOST}/v7/warning/now?location={lon},{lat}&key={KEY}&lang=zh
```

注意:和风是 **`lon,lat`(经度在前)** 的顺序,和 App 内部 `lat,lon` 相反。

QWeather 错误:`{"code":"401"}` = Key 无效 / 域名不匹配;`{"code":"402"}` = 超额;`{"code":"404"}` = 无数据(预警接口无预警时也返回 200 + 空数组)。

### 1.2 高德地图

**不集成 SDK、不调用 Web 算路接口**:只用 URL Scheme 唤起高德 APP,由用户在**高德内手动切摩托车模式**。

```text
iosamap://navi?sourceApplication=WELLWAY&lat={destLat}&lon={destLon}&dev=0&style=2
```

`style=2` = 骑行(高德不提供摩托车专属参数,故必须由用户手动切换)。未安装高德时降级到 `http(s)://maps.apple.com/?daddr=...`(苹果地图同样不含摩托模式,UI 已有提示)。

---

## 2. 用户账号模块 `✅ 已有`

清单 5 项全部已实现(基于 Supabase Auth + `profiles` 表 + 一个注销函数)。

### 2.1 注册 / 登录(邮箱验证码)

```http
POST {SUPABASE_URL}/auth/v1/otp
apikey: <ANON_KEY>
Content-Type: application/json

{ "email": "rider@example.com", "create_user": true }
```

```json
{}
```

校验验证码:

```http
POST {SUPABASE_URL}/auth/v1/verify
{ "email": "rider@example.com", "token": "123456", "type": "email" }
```

```json
{
  "access_token": "eyJhbGciOi...",
  "token_type": "bearer",
  "expires_in": 3600,
  "refresh_token": "v1-9f...",
  "user": { "id": "8a1f...-uuid", "email": "rider@example.com", "is_anonymous": false }
}
```

> 匿名试用:`{ "create_user": true }` 不传 email 走匿名登录(Supabase Anonymous Sign-In),匿名账号也自动建档,后续可绑定邮箱升级。

错误码:`422` 邮箱格式非法;`429` 发送过于频繁(前端有 30s 倒计时 + `UserDefaults` 持久化,杀进程也不放过);`403` 邮箱未开启 OTP 模板。

### 2.2 用户信息查询 / 更新 / 获取资料

```http
GET {SUPABASE_URL}/rest/v1/profiles?select=*&id=eq.{userId}
Authorization: Bearer <access_token>
```

```json
[
  {
    "id": "8a1f...-uuid",
    "nickname": "夜行的鱼",
    "email_bound": true,
    "avatar_url": "https://<project>.supabase.co/storage/v1/object/public/avatars/8a1f.../a.png",
    "privacy_agreed_at": "2026-09-17T10:02:11.000Z",
    "is_admin": false,
    "created_at": "2026-09-01T09:00:00.000Z"
  }
]
```

`privacy_agreed_at` 为 🆕 本次新增列,其余字段已存在。**邮箱不在 `profiles` 里**,从 `GET /auth/v1/user` 的 `user.email` 取(匿名账号为 `null`)。

更新(只允许更新自己的行,RLS 强制):

```http
PATCH {SUPABASE_URL}/rest/v1/profiles?id=eq.{userId}
Prefer: return=representation

{ "nickname": "夜行的鱼" }
```

错误码:`401 PGRST301` token 过期;`403 42501` 想改别人的资料。

### 2.3 账号注销 / 退出登录

```http
POST {SUPABASE_URL}/rest/v1/rpc/delete_my_account
Authorization: Bearer <access_token>
{}
```

函数返回 `void` → HTTP 200/204,**响应体为空**;App 侧以 HTTP 2xx 判成功,失败时 body 为
`{"code":"P0001","message":"forbidden: 未登录"}`。调用前 App 会先删掉 Storage 里的头像/车辆照片(见 `0016_delete_account.sql` 注释)。

级联删除:`profiles` / `vehicles` / `ride_records`(轨迹点随之删除)/ `user_badges` / `route_favorites` / `ride_checkins` / `ride_presence` / `trip_plans`(🆕)/ `incident_reports`(🆕,事故现场记录);`feedback`、`admin_logs` 匿名化保留(`on delete set null`)。

退出登录是纯客户端行为:`auth.signOut()` 清掉本地 session;服务端可选调 `POST /auth/v1/logout` 吊销 refresh token。

### 2.4 隐私协议确认

```http
PATCH {SUPABASE_URL}/rest/v1/profiles?id=eq.{userId}
{ "privacy_agreed_at": "2026-09-17T10:02:11.000Z" }
```

`privacy_agreed_at` 非空即视为已确认;协议正文见 `legal/privacy.html`、`legal/terms.html`(App 内 `AgreementViews.swift`)。
现状是"只存在本机 `@AppStorage("agreementAccepted")`",本次新增该列后 App 在勾选同意时补写一次,换机/重装后仍有记录。

---

## 3. 城市限行规则模块 `🆕 本次新增`

### 3.1 `GET /api/moto/rules` → `POST /rest/v1/rpc/moto_rule`

```http
POST {SUPABASE_URL}/rest/v1/rpc/moto_rule
apikey: <ANON_KEY>
Authorization: Bearer <access_token>
Content-Type: application/json

{ "p_city_code": "110100" }
```

入参:

| 名称 | 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| `p_city_code` | text | 是 | 行政区划代码(`110100`)或城市名(`北京市`/`北京`),两者都能命中 |

返回(命中):

```json
{
  "found": true,
  "city_code": "110100",
  "city_name": "北京市",
  "province": "北京",
  "rule_text": "1) 京B号牌摩托车禁止进入四环路(不含)以内道路行驶;\n2) 外省市号牌摩托车全天禁止进入六环路(不含)以内道路行驶;\n3) 长安街及延长线等具体路段按交管公告执行。",
  "source_url": "https://jtgl.beijing.gov.cn/",
  "effective_from": "2025-01-01",
  "verified": true,
  "updated_at": "2026-09-17T04:00:00.000Z",
  "disclaimer": "⚠️ 提示:本 APP 仅展示……不可作为通行唯一依据。"
}
```

返回(城市在清单里、但规则原文还没录入):

```json
{
  "found": true,
  "city_code": "330100",
  "city_name": "杭州市",
  "province": "浙江",
  "rule_text": null,
  "source_url": null,
  "effective_from": null,
  "verified": false,
  "updated_at": "2026-09-17T04:00:00.000Z",
  "disclaimer": "⚠️ 提示:本 APP 仅展示……不可作为通行唯一依据。"
}
```

返回(城市完全不在清单里):

```json
{
  "found": false,
  "city_code": "330100",
  "city_name": null,
  "rule_text": null,
  "verified": false,
  "disclaimer": "⚠️ 提示:本 APP 仅展示……不可作为通行唯一依据。"
}
```

设计说明:

- 规则原文由人工核对后录入 `public.moto_rules` 表,**不调用任何第三方限行接口**;表结构含 `source_url` / `effective_from` / `updated_at`,方便后续人工复核。
- `verified=false` 表示"待人工核对",App 会在文案下方追加一行小字提示;`found=false` 也是 **HTTP 200**(不是 404),App 直接展示"暂未收录 + 免责文案",避免把空数据当错误。
- 规则条目是**纯文本摘要**,不含任何算法判定,符合"仅展示文字参考"的合规口径。
- 入参非法(空串)→ 直接返回 `found=false`,不抛错。
- 0020 迁移只预置了 12 个城市的**空条目**(城市码 + 城市名),`rule_text` 由运营按交管公告逐条填;填完 `verified=true` 即上线。

---

## 4. 天气查询模块 `🆕 本次新增(替换原有 Open-Meteo 单点实时)`

### 4.1 `GET /api/weather?lat,lon`

V1 由**客户端直连和风天气**(Key 存 `Info.plist`,见 1.1);对上层暴露成同一个结构,便于以后整体换成后端代理:

```swift
let bundle = try await WeatherService.fetch(lat: 39.9087, lng: 116.3975)
```

请求(内部串行/并行 3 个和风接口):

```http
GET https://devapi.qweather.com/v7/weather/now?location=116.3975,39.9087&key=<KEY>&lang=zh
GET https://devapi.qweather.com/v7/weather/24h?location=116.3975,39.9087&key=<KEY>&lang=zh
GET https://devapi.qweather.com/v7/warning/now?location=116.3975,39.9087&key=<KEY>&lang=zh
```

归一化后的返回(`WeatherBundle`):

```json
{
  "source": "qweather",
  "now": {
    "temp": 24,
    "feelsLike": 26,
    "text": "多云",
    "icon": "101",
    "humidity": 60,
    "windDir": "西北风",
    "windScale": "3",
    "obsTime": "2026-09-17T12:00:00+08:00"
  },
  "hourly": [
    { "time": "2026-09-17T13:00:00+08:00", "temp": 25, "icon": "101", "text": "多云", "pop": 10 },
    { "time": "2026-09-17T14:00:00+08:00", "temp": 26, "icon": "100", "text": "晴",   "pop": 0 }
  ],
  "warnings": [
    {
      "id": "2026091710001234",
      "title": "北京市气象台发布大风蓝色预警",
      "severity": "Minor",
      "severityColor": "Blue",
      "type": "1006",
      "text": "预计 17 日 14 时至 20 时……",
      "pubTime": "2026-09-17T10:00:00+08:00"
    }
  ],
  "disclaimer": "⚠️ 提示:……不可作为通行唯一依据。"
}
```

降级路径(未配 `QWEATHER_KEY`、或和风返回非 `200`/`code != "200"`):

```json
{
  "source": "open-meteo",
  "now": { "temp": 23.4, "feelsLike": 25.1, "text": "多云", "icon": "3", "humidity": 58, "windDir": "西北风", "windScale": "3", "obsTime": "2026-09-17T12:00:00+08:00" },
  "hourly": [],
  "warnings": [],
  "disclaimer": "⚠️ 提示:……不可作为通行唯一依据。"
}
```

错误与处理:

| 情况 | 表现 | App 行为 |
| --- | --- | --- |
| 和风 Key 无效(`code=401`) | 抛 `QWeatherError.badKey` | 静默回退 Open-Meteo,UI 无感知(仅逐小时/预警区隐藏) |
| 超出配额(`code=402`) | 抛 `QWeatherError.quota` | 静默回退 Open-Meteo |
| 城市无预警 | `warnings: []` | 卡片显示"暂无气象预警" |
| 网络错误/超时(5s) | 抛 `URLError` | 卡片显示"天气获取失败,点击重试" |

> V2 建议(尚未实现,需装 supabase CLI 才能部署):把 Key 移到 Supabase Edge Function
> (`backend/supabase/functions/weather/index.ts`),客户端只带 JWT 调 `POST /functions/v1/weather`,Key 不进包。

---

## 5. 骑行轨迹模块 `✅ 已有(+ 本次补 3 处)`

### 5.1 轨迹创建

```http
POST {SUPABASE_URL}/rest/v1/ride_records
Prefer: return=representation

{
  "user_id": "8a1f...-uuid",
  "route_id": 12,
  "vehicle_id": "c0de...-uuid",
  "started_at": "2026-09-17T09:00:00.000Z"
}
```

```json
[
  {
    "id": "5f2a...-uuid",
    "user_id": "8a1f...-uuid",
    "route_id": 12,
    "vehicle_id": "c0de...-uuid",
    "started_at": "2026-09-17T09:00:00.000Z",
    "ended_at": null,
    "distance_m": 0,
    "duration_s": 0,
    "avg_speed_kmh": null,
    "max_speed_kmh": null,
    "elevation_gain_m": 0,
    "status": "completed"
  }
]
```

错误码:`401 PGRST301` 未登录;`409 23505`(不会发生,主键为 uuid);`403 42501` 往别人的 `user_id` 写。

### 5.2 轨迹批量点位上传

```http
POST {SUPABASE_URL}/rest/v1/ride_points
Prefer: return=minimal

[
  { "ride_id": "5f2a...-uuid", "lat": 39.9087, "lng": 116.3975, "speed_kmh": 42.5, "bearing": 78.4, "recorded_at": "2026-09-17T09:00:03.000Z" },
  { "ride_id": "5f2a...-uuid", "lat": 39.9091, "lng": 116.3992, "speed_kmh": 45.0, "bearing": 80.1, "recorded_at": "2026-09-17T09:00:06.000Z" }
]
```

```json
null
```

`bearing`(航向角,0-360,正北为 0,顺时针)为 🆕 本次新增列,用于"后方同向 / 对向驶来"统计;
App 侧每 5 秒聚合一批上报,避免逐点请求。

### 5.3 轨迹列表查询

```http
GET {SUPABASE_URL}/rest/v1/ride_records?select=*&user_id=eq.{userId}&order=started_at.desc&limit=20
```

(RLS 已限制为"只能看自己的",即使不带 `user_id` 条件也拿不到别人的)

### 5.4 轨迹回放查询

```http
GET {SUPABASE_URL}/rest/v1/ride_points?select=lat,lng,speed_kmh,bearing,recorded_at&ride_id=eq.{rideId}&order=recorded_at.asc
```

```json
[
  { "lat": 39.9087, "lng": 116.3975, "speed_kmh": 42.5, "bearing": 78.4, "recorded_at": "2026-09-17T09:00:03.000Z" },
  { "lat": 39.9091, "lng": 116.3992, "speed_kmh": 45.0, "bearing": 80.1, "recorded_at": "2026-09-17T09:00:06.000Z" }
]
```

### 5.5 轨迹统计查询

```http
POST {SUPABASE_URL}/rest/v1/rpc/recalculate_ride_stats
{ "p_ride_id": "5f2a...-uuid" }
```

```json
null
```

函数内部按"相邻点 >1000m 视为定位跳变、速度封顶 300km/h"清洗后,把 `distance_m` / `duration_s` / `avg_speed_kmh` / `max_speed_kmh` 写回 `ride_records`;App 随后重新 `GET` 该行即为统计结果。

### 5.6 删除自己的轨迹 `🆕 本次补策略`

```http
DELETE {SUPABASE_URL}/rest/v1/ride_records?id=eq.{rideId}
```

```json
null
```

`ride_points` 对 `ride_records(id)` 是 `on delete cascade`,故轨迹点自动清除。
**注意**:当前库里 `ride_records` / `ride_points` 只有 `select/insert/update` 策略,**没有 delete 策略** → 本次迁移补上 `rides_delete_own` / `points_delete_own`(仅限自己的行),否则 App 删除会返回 403。

---

## 6. 行程与匿名骑手统计模块 `🆕 本次新增`

> 合规前提:**骑手之间没有任何交互**。下面 4 个接口只返回"聚合数字",不返回任何用户 id / 昵称 / 车辆 / 位置明细,
> 且全部走 `security definer` 函数(RLS 之上再加一层),App 端也拿不到别人的行。

### 6.1 创建行程计划 `POST /api/trip/plan`

```http
POST {SUPABASE_URL}/rest/v1/rpc/trip_plan_create
Authorization: Bearer <access_token>

{
  "p_dest_lat": 39.9087,
  "p_dest_lon": 116.3975,
  "p_dest_name": "中央公园",
  "p_start_lat": 39.8801,
  "p_start_lon": 116.3602
}
```

```json
{
  "trip_id": "9b7c...-uuid",
  "status": "planned",
  "dest_lat": 39.9087,
  "dest_lon": 116.3975,
  "dest_name": "中央公园",
  "created_at": "2026-09-17T09:00:00.000Z"
}
```

行为:先把该用户**其它未结束的行程**置为 `canceled`(一个人同一时间只算一个行程,避免重复计数),再插入新行。

错误码:`AUTH_REQUIRED`(未登录)、`BAD_COORD`(纬度 >90 或经度 >180)。

### 6.2 更新行程状态 `PUT /api/trip/status`

```http
POST {SUPABASE_URL}/rest/v1/rpc/trip_status_update
{ "p_trip_id": "9b7c...-uuid", "p_status": "riding" }
```

状态机:

| 值 | 含义 | 副作用 |
| --- | --- | --- |
| `planned` | 计划中(已上报目的地) | 计入「计划前往骑手数」 |
| `riding` | 骑行中 | 计入「计划前往」+「附近骑手」;写 `started_at` |
| `finished` | 已结束 | 不再参与任何统计;写 `ended_at` |
| `canceled` | 用户取消/被新行程顶掉 | 不再参与任何统计 |

```json
{
  "trip_id": "9b7c...-uuid",
  "status": "finished",
  "started_at": "2026-09-17T09:03:00.000Z",
  "ended_at": "2026-09-17T10:41:00.000Z"
}
```

错误码:`TRIP_NOT_FOUND`(行程不存在或不属于当前用户)、`TRIP_STATUS_INVALID`(`23514` 同义,枚举外取值)。

### 6.3 查询目的地计划前往骑手总人数 `GET /api/rider/count`

```http
POST {SUPABASE_URL}/rest/v1/rpc/rider_count_to_dest
{ "p_dest_lat": 39.9087, "p_dest_lon": 116.3975, "p_radius_m": 3000 }
```

```json
{
  "count": 7,
  "radius_m": 3000,
  "active_window_min": 120,
  "disclaimer": "⚠️ 提示:……不可作为通行唯一依据。"
}
```

口径:

- 统计 `trip_plans` 中 `status in ('planned','riding')`、`updated_at > now() - 120min`、**目的地落在直径 3km 圆内**(haversine ≤ 3000m)的**去重人数**;
- 排除自己;
- 只回数字,不回明细。

### 6.4 查询沿途附近匿名骑手统计 `GET /api/rider/nearby`

```http
POST {SUPABASE_URL}/rest/v1/rpc/riders_nearby
{ "p_lat": 39.9087, "p_lon": 116.3975, "p_bearing": 78.4, "p_radius_m": 2000 }
```

```json
{
  "total": 3,
  "behind_same_direction": 2,
  "oncoming": 1,
  "radius_m": 2000,
  "fresh_seconds": 120,
  "bearing": 78.4,
  "disclaimer": "⚠️ 提示:……不可作为通行唯一依据。"
}
```

判定口径(全部在 SQL 里算,客户端不接触他人位置):

| 分类 | 条件 |
| --- | --- |
| 进入统计 | `ride_presence.updated_at > now() - 120s`(正在骑、且刚上报过)、距离 ≤ `p_radius_m`、排除自己 |
| `behind_same_direction` 后方同向 | 航向差 ≤ 60° **且** 对方在我身后(与我前进方向的点积 < 0) |
| `oncoming` 对向驶来 | 航向差 ≥ 120°(即大致对头) |
| 其它 | 满足距离但方向不明确 → 只计入 `total`,不计入两个分类 |

`p_bearing` 为空/不传 → 只返回 `total`(两个分类为 `null`,App 显示"方向统计需要航向数据")。
`ride_presence` 每 15 分钟自动清理过期行,`fresh_seconds=120` 保证"已经停下/关掉 App 的人"不会长期被算进来。

### 6.5 App 端上报节奏

| 时机 | 动作 |
| --- | --- |
| 出发页选好目的地、点「开始骑行」前 | `trip_plan_create` + `rider_count_to_dest`(卡片显示"计划前往 x 人") |
| 骑行开始 | `trip_status_update(riding)`;`ride_presence` upsert(lat/lng/bearing/vehicle_name/nickname) |
| 骑行中 | 每 5s 上报轨迹点;每 30s upsert `ride_presence` + 调 `riders_nearby`(UI 显示"后方同向 x / 对向 x") |
| 骑行结束 | `trip_status_update(finished)`;删除自己的 `ride_presence` 行 |
| 离开骑行页 | 不再 upsert,120s 后自动从他人统计里消失 |

---

## 7. 安全救援与事故现场记录 `✅ 已有`

> 安全救援只做**本地能力**:110 / 120 / 122 由系统电话确认,位置由系统分享面板交给用户选择的对象;
> 不做自动报警、自动通知、后台值守或救援调度。所有页面文案必须保留这条边界。

### 7.1 紧急电话 / 位置分享 / 附近救援点(纯客户端)

| 能力 | 实现 | 说明 |
| --- | --- | --- |
| 紧急电话 | `tel://110`、`tel://120`、`tel://122` | 先弹系统确认,用户点「拨打」才跳转 |
| 位置分享 | 系统分享面板(`ShareSheet`) | 文案含路线名与实时坐标;无定位时按钮禁用,不伪造位置 |
| 附近救援点 | MapKit `MKLocalSearch` | 8 公里内医院 / 派出所,按距离排序最多 5 条,点击打开 Apple 地图驾车导航;不承诺床位、接诊或出警 |

### 7.2 事故现场记录

```http
POST {SUPABASE_URL}/rest/v1/incident_reports
Authorization: Bearer <access_token>
Content-Type: application/json
Prefer: return=representation

{
  "user_id": "<auth.uid()>",
  "route_name": "城市穿梭线",
  "latitude": 39.9087,
  "longitude": 116.3975,
  "incident_type": "collision",
  "note": "在路口被后车追尾,人无大碍,右侧后视镜损坏。",
  "occurred_at": "2026-11-13T10:02:11.000Z",
  "app_version": "0.1.0"
}
```

```json
[{ "id": 1042, "occurred_at": "2026-11-13T10:02:11.000Z" }]
```

- `incident_type`:`fall`(摔车)/ `collision`(碰撞)/ `breakdown`(车辆故障)/ `other`(其他)
- `note` 最长 500 字;`latitude` / `longitude` 必须同时为空或同时有效(-90..90 / -180..180);无定位时提交 `null`,不填假坐标
- 响应返回 `id` 与 `occurred_at`,App 用其渲染回执编号与时间

权限(`backend/supabase/migrations/0026_incident_reports.sql`):

| 角色 | insert | select | update / delete |
| --- | --- | --- | --- |
| 本人(含匿名登录) | ✅ 仅 `user_id = auth.uid()` | ✅ 仅自己的记录 | ❌ 无策略 |
| 管理员 | ❌ | ✅ 全部(`is_admin()`) | ❌ 无策略 |

后台「事故记录」为只读列表,按发生时间倒序,支持路线 / 经过 / 版本搜索;注销账号时随 `auth.users` 级联删除。
迁移未执行时 PostgREST 返回 `PGRST205`,后台会直接显示执行 `0026_incident_reports.sql` 的提示。

## 8. 可选接口

| 接口 | 状态 | 说明 |
| --- | --- | --- |
| `POST /api/sos` | `⏸ 不提供` | 自动报警 / 通知 / 调度需要短信、客服值守与合规资质;当前只做系统电话、系统分享与本人事故留存(见第 7 节),避免给出无法兑现的安全承诺 |
| `GET /api/version` | `⏸ 暂不开发` | 内测用 TestFlight 自动更新替代;确实需要时用 `GET /rest/v1/app_config?key=eq.min_version` 一张表即可 |

---

## 9. 完整业务流程 × 接口对照

| # | 业务步骤 | 调用 |
| --- | --- | --- |
| 1 | 输入起点终点,定位取城市/经纬度 | 系统 CLLocation + 反地理编码(不走后端) |
| 2 | 并行取限行文字 + 天气 | `rpc/moto_rule`、`WeatherService.fetch`(和风;降级 Open-Meteo) |
| 3 | 提交目的地 → 上报行程 + 看同行人数 | `rpc/trip_plan_create`、`rpc/rider_count_to_dest` |
| 4 | 跳高德导航(手动切摩托模式) | `iosamap://navi?...`(URL Scheme) |
| 5 | 骑行中:上报点位 + 定时查附近骑手 | `POST /rest/v1/ride_points`、`rpc/riders_nearby`、(presence upsert) |
| 6 | 骑行结束:标记结束、轨迹仅本人可见、可删除 | `rpc/trip_status_update(finished)`、`rpc/recalculate_ride_stats`、`DELETE /rest/v1/ride_records?id=eq.` |

---

## 10. 隐私协议要点 × 实现对照

| 协议承诺 | 实现位置 |
| --- | --- |
| 收集位置用于天气/轨迹/匿名统计 | 天气只传经纬度给和风,不留存;轨迹存 `ride_points`(仅本人可读);统计走聚合函数 |
| 行程结束后不再参与附近统计 | `trip_status_update(finished)` + `ride_presence` 行删除 + 120s 新鲜度窗口 |
| 轨迹仅本人可见、可随时删除 | RLS `rides_select_own` + 本次新增 `rides_delete_own`(级联删点位) |
| 不收集车牌、排量、健康/生理数据 | **匿名统计链路**只读经纬度/航向,不碰这些字段;健康/生理数据全库无列;`vehicles` 的排量来自车型库只读展示,不由用户填报;车牌字段已于 `0021_drop_vehicle_plate.sql` 从 `vehicles` 物理删除,App 内无车牌录入/展示,`legal/privacy.html` 同步声明"我们不收集车牌号" |
| 无 UGC、无互相私信、不看彼此资料 | `0014_remove_social.sql` 已删除聊天与主页;所有统计接口只回数字 |
| 事故记录仅本人留存、管理员只读 | `incident_reports` RLS:本人 insert/select 自己的行,管理员只读,无 update/delete;不自动外发、不触发报警 |

---

## 11. 附录

### 11.1 数据表索引(与本节相关)

| 表 | 用途 | 状态 |
| --- | --- | --- |
| `profiles` | 账号资料(+`privacy_agreed_at`) | ✅ / 🆕 加列 |
| `moto_rules` | 城市限行文字规则 | 🆕 |
| `trip_plans` | 行程计划与状态 | 🆕 |
| `ride_presence` | 骑行中位置心跳(+`bearing`) | ✅ / 🆕 加列 |
| `ride_records` / `ride_points` | 轨迹与统计(+`ride_points.bearing`、delete 策略) | ✅ / 🆕 补 |
| `incident_reports` | 事故现场记录(本人可写可读,管理员只读,不可改删) | 🆕 |

### 11.2 RPC 索引

| 函数 | 权限 | 说明 |
| --- | --- | --- |
| `moto_rule(text)` | anon, authenticated | 限行文字 + 免责 |
| `disclaimer_text()` | anon, authenticated | 统一免责文案 |
| `trip_plan_create(...)` | authenticated | 建行程(顶掉旧的) |
| `trip_status_update(uuid, text)` | authenticated | 改状态 |
| `rider_count_to_dest(...)` | anon, authenticated | 计划前往人数(聚合) |
| `riders_nearby(...)` | anon, authenticated | 附近同向/对向(聚合) |
| `delete_my_account()` | anon, authenticated | 注销 ✅ |
| `recalculate_ride_stats(uuid)` | anon, authenticated | 轨迹统计 ✅ |
| `count_route_riders_today()` | anon, authenticated | 今日各路线骑行人数(已有功能) ✅ |
| `rider_badge_counts()` | authenticated | 同路骑友徽章数(已有功能) ✅ |

### 11.3 上线前配置清单

- [x] `backend/supabase/migrations/0019_trip_and_rider_stats.sql` 执行(行程 / 骑手统计 / 轨迹删除 / bearing / 隐私列)——**2026-09-17 已在云端执行**
- [x] `backend/supabase/migrations/0020_moto_rules.sql` 执行(限行规则表 + 免责函数 + 示例城市)——**2026-09-17 已在云端执行**
- [x] `backend/supabase/migrations/0021_drop_vehicle_plate.sql` 执行(下线车牌:删除 `vehicles.plate`)——**2026-09-17 已在云端执行**
- [ ] 和风天气 Key 填入 `ios/WELLWAY/Resources/Info.plist`(`QWEATHER_KEY`),并在控制台确认域名白名单
- [ ] `Info.plist` 定位权限文案已含"用于天气查询、轨迹记录与匿名骑手统计"(已有,复核一遍)
- [ ] `backend/supabase/migrations/0026_incident_reports.sql` 执行(事故现场记录表 + RLS)——**尚未执行**,本机 `backend/.env` 缺 `SUPABASE_DB_URL` 密码
- [ ] 限行规则逐城市人工核对 `moto_rules.rule_text` 与 `source_url`(内测先覆盖一线/新一线)

#### 怎么执行迁移(两条路,任选)

1. **命令行(推荐,可重复执行)**:`backend/.env` 已配好 `SUPABASE_DB_URL`(Supavisor 连接池,`aws-0-ap-northeast-1`)。
   ```bash
   cd backend && /Applications/Postgres.app/Contents/Versions/18/bin/psql \
     "$(grep '^SUPABASE_DB_URL=' .env | cut -d= -f2-)" \
     -v ON_ERROR_STOP=1 --single-transaction \
     -f supabase/migrations/APPLY_0019_0020.sql
   ```
2. **网页**:Supabase Dashboard → SQL Editor,整段粘贴 `backend/supabase/migrations/APPLY_0019_0020.sql`(0019+0020 合并包)→ Run。

#### 验收命令(2026-09-17 已跑通)

```bash
cd backend/scripts
node --env-file=../.env trip-stats-test.mjs   # 行程/状态机/人数/附近统计/轨迹删除/隐私确认,31 项
node --env-file=../.env smoke-test.mjs        # 基础链路 + 无 UGC 校验,10 项
```
