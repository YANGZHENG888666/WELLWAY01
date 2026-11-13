# WELL WAY 上线部署方案与剩余工作(2026-08-21)

> 回答四个问题:要不要地图 API?要不要云服务器?要不要域名?还差什么?

## 一、结论速览

| 问题 | 结论 | 花钱吗 |
|------|------|--------|
| 云服务器 | 不需要自购。Supabase 已经托管了数据库/登录/存储/实时消息 | 免费额度够用 |
| 地图 API | 需要。iOS 内置地图免费但国内有偏移问题;推荐高德(Web 端 JS API + iOS SDK 都免费,额度大) | 免费 |
| 域名 | 上线建议要。个人开发测试可先用 `{ref}.supabase.co` 自带域名 | 域名约 ¥50/年 |
| App Store | iOS 上架必须:开发者账号 ¥688/年 + 隐私政策 + 审核 | 必须花 |

## 二、地图 API 方案(第 4 项)

### 推荐:高德开放平台(免费)

1. 注册 [高德开放平台](https://lbs.amap.com/),创建两个应用:
   - **Web 服务**(后端/后台网页用):路线图绘制、地理编码、路线规划
   - **iOS 平台**(App 用):SDK key,需填 Bundle ID `com.wellway.WELLWAY`
2. 用途分配:
   - App 内实时导航 → 高德 iOS SDK(`MAMapKit` + `AMapLocationKit`),替换现在的地图底图
   - 后台路线图上传 → 后台网页用高德 JS API 生成路线图(可省:现在 App 是画线,后台传图即可)
   - 骑行中轨迹底图 → 现在用 Apple MapKit,若用户在国内接受偏移动画即可,不强求换
3. 不用高德的话,备选:百度地图(同样免费)、腾讯位置服务。

### 现在就要做的吗?

- **不做也不影响功能**:App 目前用 Apple MapKit 显示轨迹,国内有 50~300m 偏移,但路线图是
  后台上传的静态图,不依赖实时定位精度。
- **建议排期**:1.0 上架前把「骑行中地图底图」换成高德 SDK 即可,其余页面继续用图片路线图。

## 三、云服务器与后端(第 4 项)

现状:后端全部跑在 Supabase(Postgres + Auth + Storage + Realtime + Edge Functions),
没有自己的服务器,也不需要。

- 免费额度:50k MAU / 500MB 数据库 / 5GB 存储 / 500k 函数调用,1,000 用户绰绰有余
- 如遇超量再升级:Pro 版 $25/月,可自定义域名、更大额度
- 管理后台是纯静态网页,可部署到:Cloudflare Pages / Vercel / GitHub Pages(免费)

### 域名(可选但建议)

- 后台域名:如 `admin.wellway.cn` → Cloudflare Pages 自定义域(免费,需买域名)
- API 域名:Supabase 团队版才支持自定义,个人用 `{ref}.supabase.co` 即可
- 域名购买:阿里云/腾讯云 .cn 约 ¥30/年,或 Namecheap .com 约 $10/年

## 四、路线图上传方案(第 2 项,已完成)

### 放大不失真的格式

- **推荐 SVG**:矢量,任意放大不失真、文件小
- 后台已支持:上传 SVG 自动转 2048px 高清 PNG 存入 Supabase Storage(`route-images` 桶)
- 也支持直接上传 ≥2048px 的 PNG/JPG
- App 端:`RouteMapImage` 组件优先显示 `routes.map_url`,没有则回退线条轨迹

### 需要你执行的一步(SQL)

在 Supabase Dashboard → SQL Editor 执行:

```sql
alter table public.routes
  add column if not exists map_url text;

insert into storage.buckets (id, name, public) values
  ('route-images', 'route-images', true)
on conflict (id) do nothing;

create policy if not exists "route_images_read_public" on storage.objects
for select to anon, authenticated
using (bucket_id = 'route-images');
```

完整脚本在 `backend/supabase/migrations/0010_route_map_url.sql`。
执行后刷新管理后台,「路线」表单里会出现「路线图」上传入口。

## 五、管理后台 UI(第 3 项,已完成)

- 风格:黑白简洁,贴合品牌(去掉原蓝色主题)
- 品牌 logo 内联进登录页和顶栏
- 表格、按钮、Tab、弹窗全部统一为黑白灰 + 细边框卡片风格
- 本地预览:`cd admin && python3 -m http.server 8000` 后访问 `http://localhost:8000/admin/index.html`

## 六、剩余工作清单(第 5 项)

### 上线前必须(1.0)

- [ ] 跑 `0010_route_map_url.sql` 迁移,给现有 2 条路线配路线图
- [x] 骑行总结闭环(总结页 + 打卡明细 + 重命名/删除) — 已实现,待真机验证定位权限与轨迹落库
- [x] 自动发徽章(打卡全达标 → `award_badge` RPC 落库) — 已实现,待真机验证
- [ ] 管理后台:骑行记录查看/统计页(目前只有 App 端记录)
- [ ] 隐私政策页面上线(`docs/PRIVACY-POLICY.md` 已有草稿,App 内接入)
- [ ] 高德地图 SDK 替换骑行底图(上架前)
- [ ] App Store 上架材料:隐私清单、权限文案、截图、审核备注

### 发布后(1.1)

- [x] 活动报名闭环(报名 → 名额扣减 → 活动详情展示已报人数) — 已实现,待线上数据验证
- [ ] 同路骑士在线状态 + 实时距离(ride_presence 表已建)
- [ ] 推送通知(APNs + Supabase Realtime 触发)
- [x] 我的收藏列表独立页 — 已完成（第 42 轮，入口：我的 → 路线 → 我的收藏）
- [ ] 好友/关注、车队群聊、排行榜
- [ ] 离线地图缓存(骑行山区无信号)

### 数据补全

- [ ] 路线数据:目前线上仅 2 条,需用后台录入更多路线 + 路线图 + 打卡点坐标
- [ ] 车型库:品牌/车型/价格/图片补全(官方公开信息)
- [ ] 徽章配置:设计好各路线徽章图与获得条件

## 七、推荐执行顺序

1. 跑 SQL 迁移 → 后台给 2 条路线传路线图 → App 验证显示
2. 真机骑行一次,验证总结/徽章闭环
3. 注册高德、配好 key,替换骑行底图
4. 部署后台到 Cloudflare Pages + 买域名
5. 整理上架材料,提交 App Store
