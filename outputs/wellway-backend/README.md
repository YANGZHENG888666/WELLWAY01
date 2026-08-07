# WELL WAY Backend

WELL WAY（摩托车出行 App）的后端骨架，基于 Supabase（Postgres + Auth + Storage）。

## 目录

```text
supabase/
  migrations/0001_initial_schema.sql   # 数据库表 + 权限策略
  seed.sql                              # 初始品牌/车型种子数据
.env.example                            # 环境变量模板
```

## 技术选型

- 数据库：PostgreSQL（Supabase 托管）
- 鉴权：Supabase Auth（匿名账号 + 邮箱绑定）
- API：PostgREST（Supabase 自带 REST）
- 实时：Supabase Realtime（同路提示可后置）
- 文件：Supabase Storage（车辆照片、路线图片）

## 快速开始

1. 在 [supabase.com](https://supabase.com) 创建项目
2. 安装 Supabase CLI 并链接项目：

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

   也可以把 `migrations/0001_initial_schema.sql` 和 `seed.sql` 直接贴进 Supabase SQL Editor 执行。

3. 开启匿名登录：
   - Authentication > Providers > Email 开启
   - Authentication > Sign In > Anonymous Sign-Ins 开启
   - Authentication > Email > 配置邮箱模板（绑定邮箱用 OTP）

4. 复制 `.env.example` 为 `.env` 并填入项目 URL / Keys。

## 核心表

| 表 | 说明 |
| --- | --- |
| profiles | 匿名账号资料 + 邮箱绑定状态 |
| brands / models | 车型库（筛选主数据） |
| vehicles | 用户车库 |
| routes / checkpoints | 路线与打卡点 |
| ride_records / ride_points | 骑行记录与 GPS 轨迹 |
| badges / user_badges | 徽章体系 |
| activities | 活动（P2 预留） |

## 车型筛选 API 示例（PostgREST）

```http
# 按品牌 + 类型 + 排量筛选，按评分排序
GET /rest/v1/models?brand_id=eq.1&model_type=eq.跑车&displacement_cc=gte.400&order=rating.desc

# 关键字搜索
GET /rest/v1/models?name=ilike.*450*
```

## 数据来源策略（商用）

- 不抓取第三方网站（如摩托范）的运营数据
- 车型名称、排量、类型属于公开事实，价格以品牌官方指导价为准
- 图片使用官方素材或自行拍摄，避免盗链
- 后续增加后台管理界面，由自己维护车型库

## 换一台电脑继续开发

1. 把整个仓库推到私有 Git 仓库（GitHub / Gitee）：

   ```bash
   git init
   git add .
   git commit -m "init: wellway backend scaffold"
   git remote add origin <你的仓库地址>
   git push -u origin main
   ```

2. 新电脑上：

   ```bash
   git clone <你的仓库地址>
   cd wellway-backend
   cp .env.example .env   # 填入相同的 Supabase URL / Keys
   supabase link --project-ref YOUR_PROJECT_REF
   ```

3. 数据库本身在 Supabase 云端，换电脑不影响数据；schema 通过 migration 文件在任何机器都能重建。
4. Codex 的对话记录在本机，不会自动跨设备；把本 README 和代码推上仓库后，新电脑上让 Codex 打开这个仓库，就能从文档和代码继续。

## 后续 Roadmap

1. 车型库管理后台（增删改查 + 图片上传）
2. App 端登录 / 匿名账号
3. 车库：选品牌 / 选车型 / 添加车辆
4. 路线 + 骑行中 + 后台定位轨迹
5. 骑行总结 + 打卡 + 徽章
6. 首页 / 个人中心 / 设置页
7. iOS 原生（Swift）在 Mac 上接入同一后端
