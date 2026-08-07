# WELL WAY 项目交接文档

> 本文件是给“下一台电脑上的 Codex”看的开工说明。读完这份文档后，新电脑上的 Codex 应当能直接继续开发，不需要用户重新解释需求。

## 1. 项目是什么

WELL WAY 是一个摩托车出行 App：匿名账号 + 邮箱绑定，核心功能是骑行路线、同目的地人群提醒（同路人聊天）、路线打卡与徽章、车辆车库（品牌/车型筛选）。

## 2. 当前进度

### 已完成（在 outputs 目录）

| 文件 | 内容 |
| --- | --- |
| `wellway-ui.html` | 18 屏 UI 稿（登录、P房、品牌/车型筛选、添加车辆、首页、路线、骑行中、总结、徽章、记录、个人中心、设置、活动预留） |
| `wellway-route-switch.html` | 路线切换动效原型（SVG 轨迹描线 + 打卡点亮 + 小摩托沿路线移动） |
| `spider-interactive.html` | 蜘蛛侠风格交互页（Canvas 蜘蛛跟随鼠标） |
| `spider-title-hover.html` | 双图流线笔刷蒙版显现效果（title.png + holland.png） |
| `title.png` / `holland.png` | 用户提供的两张图（标题底图 / 荷兰弟海报） |
| `wellway-backend/` | Supabase 后端骨架（见第 3 节） |

### 未完成

- Supabase 项目还没创建（需要用户注册并给出项目 URL / Keys）
- App 客户端还没写（计划 iOS 原生 Swift，在 Mac 上做）
- 车型库只有 12 条种子数据
- 后台管理界面没有

## 3. 后端骨架（wellway-backend/）

- `README.md`：技术选型、快速开始、API 示例
- `supabase/migrations/0001_initial_schema.sql`：全部表 + RLS 权限策略 + 匿名用户自动建档
- `supabase/seed.sql`：5 个品牌、12 款车型种子数据
- `.env.example`：环境变量模板
- `.gitignore`：已忽略 `.env`、`node_modules`、`work/` 等

关键表：profiles、brands、models、vehicles、routes、checkpoints、ride_records、ride_points、badges、user_badges、activities、activity_registrations。

## 4. 已经确定的技术决策（不要推翻）

1. 商用产品，目标至少 1000 用户
2. **不抓取摩托范等第三方网站数据**，车型库由官方公开信息 + 自己维护
3. 后端用 Supabase（Postgres + Auth + Storage + Realtime）
4. 客户端优先做 **iOS 原生（Swift）**，用户有 Mac；后端平台无关，以后可加 Android
5. UI 风格沿用 Figma `wellway` 设计稿：浅灰背景、白卡片、主色 `#4199FD`
6. 账号体系：匿名账号自动创建 + 邮箱绑定，不做游客/登录双身份

## 5. 下一步开发顺序（新 Codex 按这个顺序开工）

1. **建 Supabase 项目**：引导用户注册、新建项目、开启匿名登录和邮箱登录，把 URL / Keys 填进 `.env`
2. **应用数据库迁移**：`supabase db push`，或在 Supabase SQL Editor 里执行 migration + seed
3. **车型筛选 API 冒烟测试**：用 PostgREST 验证 `models` 筛选、品牌列表返回正常
4. **iOS 工程骨架（Swift + Xcode）**：
   - SwiftUI + Supabase Swift SDK
   - 包结构：Auth、Garage（品牌/车型/车辆）、Routes、Ride、Profile、Settings
   - 先做：匿名登录 + 我的P房 + 选品牌/选车型/添加车辆
5. **权限与后台定位**：Info.plist 位置后台模式、始终允许定位、前台服务通知说明
6. **路线 + 骑行中 + 轨迹记录**：把 `ride_points` 写入链路接通
7. **骑行总结 + 打卡 + 徽章**
8. **首页 / 个人中心 / 设置页**（含权限状态卡）
9. 后续：活动模块（P2）、管理后台维护车型库

## 6. 新 Codex 开工前必读

- 先读本文件、`wellway-backend/README.md`、`0001_initial_schema.sql`
- 打开 `wellway-ui.html` 看 UI 稿（Figma 设计参考为 `wellway` 文件，fileKey `Z5rf5IeC37grImInJxyUp6`）
- 不要重写 schema，除非有充分理由并说明
- 每次完成一个里程碑，更新本文件的“当前进度”

## 7. 需要用户提供

- Supabase 项目 URL、anon key、service_role key（填 `.env`，不要提交）
- Mac 上的 Xcode 环境（iOS 编译/真机测试）
- 车型库价格以官方指导价为准，种子数据里的价格是示例，需要核对

## 8. 换电脑/跨机器协作

- 整个项目（含本文件）推到私有 Git 仓库（GitHub / Gitee）
- 新电脑：`git clone` 仓库 → 打开目录启动 Codex → Codex 先读本文件继续
- Codex 对话记录不跨机，本文件就是跨机上下文
