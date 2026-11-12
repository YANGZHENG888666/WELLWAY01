# WELL WAY Backend

WELL WAY(摩托车出行 App)的后端,基于 Supabase(Postgres + Auth + Storage + Realtime)。

## 目录结构

```text
supabase/
  config.toml                # Supabase CLI 配置
  migrations/
    0001_initial_schema.sql  # 核心表 + RLS 权限策略 + 匿名自动建档
    0002_core_extensions.sql # 同路人聊天、骑行打卡、存储桶、实时订阅、约束
    0003_functions.sql       # 骑行统计、徽章发放、活动状态视图
  seed.sql                   # 品牌/车型/示例路线/打卡点/徽章种子数据
scripts/
  smoke-test.mjs             # API 冒烟测试(匿名登录 → 车型筛选 → 聊天)
  ride-flow-test.mjs         # 骑行闭环契约测试(轨迹→打卡→重算→徽章→活动报名)
  seed-demo.mjs              # 幂等补种 Figma 演示数据(北京路线/徽章/活动,用 service role)
.env.example                 # 环境变量模板
```

## 快速开始

1. 在 [supabase.com](https://supabase.com) 注册并创建项目。
2. 安装 Supabase CLI 并链接项目:

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

   也可以把三个 migration 文件和 `seed.sql` 按顺序贴进 Supabase SQL Editor 执行。

3. 开启匿名登录:
   - Authentication > Providers > Email:开启
   - Authentication > Sign In > Anonymous Sign-Ins:开启
   - Authentication > Email:配置邮箱模板(绑定邮箱用 OTP)

4. 复制 `.env.example` 为 `.env`,填入项目 URL / Keys:

   ```bash
   cp .env.example .env
   ```

5. 冒烟测试:

   ```bash
   cd scripts
   npm install
   npm run smoke
   ```

   期望输出全部 `✓`,测试项见下文。

## 冒烟测试覆盖

- 匿名登录(Anonymous Sign-In)
- 匿名账号自动建档(profiles 触发器)
- 品牌列表公开读
- 车型筛选(`model_type` + `displacement_cc` + `rating` 排序)
- 关键字搜索(`ilike`)
- 添加车辆(RLS:只能操作自己的数据)
- 同路人聊天写入 + 读取(RLS + Realtime 表)

## 核心表

| 表 | 说明 |
| --- | --- |
| profiles | 匿名账号资料 + 邮箱绑定状态 |
| brands / models | 车型库(筛选主数据) |
| vehicles | 用户车库 |
| routes / checkpoints | 路线与打卡点 |
| ride_records / ride_points | 骑行记录与 GPS 轨迹 |
| ride_checkins | 骑行中的打卡记录 |
| route_chat_messages | 同路线骑友聊天(Realtime) |
| badges / user_badges | 徽章体系 |
| activities / activity_registrations | 活动(P2 预留) |

## 车型筛选 API 示例(PostgREST)

```http
# 按品牌 + 类型 + 排量筛选,按评分排序
GET /rest/v1/models?brand_id=eq.1&model_type=eq.跑车&displacement_cc=gte.400&order=rating.desc

# 关键字搜索
GET /rest/v1/models?name=ilike.*450*
```

## 常用 SQL 函数

- `public.recalculate_ride_stats(ride_id)` — 根据 GPS 点重算距离/时长/均速/极速
- `public.award_badge(user_id, badge_id, ride_id)` — 幂等发放徽章,返回是否新增
- 视图 `public.activities_current` — 活动状态(`upcoming/ongoing/ended`)实时计算

## 数据来源策略(商用)

- 不抓取第三方网站(如摩托范)的运营数据
- 车型名称、排量、类型属于公开事实,价格以品牌官方指导价为准
- 种子数据里的价格是示例,上线前必须人工核对
- 图片使用官方素材或自行拍摄,避免盗链
- 后续增加后台管理界面,由自己维护车型库

## 换一台电脑继续开发

1. 把整个仓库推到私有 Git 仓库(GitHub / Gitee)。
2. 新电脑上:

   ```bash
   git clone <你的仓库地址>
   cd backend
   cp .env.example .env   # 填入相同的 Supabase URL / Keys
   supabase link --project-ref YOUR_PROJECT_REF
   ```

3. 数据库本身在 Supabase 云端,换电脑不影响数据;schema 通过 migration 文件在任何机器都能重建。

## 后续 Roadmap

1. 车型库管理后台(增删改查 + 图片上传)
2. App 端登录 / 匿名账号(见 `ios/` 目录)
3. 车库:选品牌 / 选车型 / 添加车辆
4. 路线 + 骑行中 + 后台定位轨迹
5. 骑行总结 + 打卡 + 徽章
6. 首页 / 个人中心 / 设置页
7. iOS 原生(Swift)在 Mac 上接入同一后端
