# WELL WAY iOS App

iOS 原生客户端(SwiftUI + Supabase Swift SDK),最低支持 iOS 17。

## 环境要求

- macOS 14 及以上(推荐最新)
- Xcode 16 及以上(App Store 免费下载)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)(工程由 `project.yml` 生成)

## 首次运行

1. 配置后端地址:编辑 `WELLWAY/Resources/Info.plist` 里的两个占位值
   (或者等 `xcodegen` 生成工程后,在 Xcode 的 Info 页配置):

   ```xml
   SUPABASE_URL      https://YOUR_PROJECT.supabase.co
   SUPABASE_ANON_KEY YOUR_ANON_KEY
   ```

2. 生成工程并打开:

   ```bash
   cd ios
   xcodegen
   open WELLWAY.xcodeproj
   ```

3. Xcode 里选择模拟器或自己的 iPhone,直接 Run。
   首次拉取 Supabase SDK 依赖需要几分钟。

## 已实现功能

- 匿名账号自动登录 + 邮箱绑定(OTP 两步)
- P房:车辆列表、添加车辆(选品牌 → 选车型 → 昵称/颜色)、设默认、删除
- 路线:列表、详情、打卡点、同路人聊天(轮询,后续可换 Realtime 订阅)
- 个人中心:资料、昵称修改、邮箱绑定状态、退出

## 代码结构

```text
WELLWAY/
  App/      入口与根视图、Tab 框架
  Auth/     匿名登录、邮箱绑定
  Core/     配置、主题色、数据模型
  Garage/   P房服务与视图
  Routes/   路线与聊天
  Profile/  个人中心
  Resources/Info.plist、Assets
```

## 设计规范

UI 风格沿用 Figma `wellway` 设计稿:浅灰背景(`#F5F7FA`)、白卡片、
主色 `#4199FD`。设计稿接入后,样式统一在 `Core/Theme.swift` 调整。

## 下一步(等 UI 设计稿 + 真机)

- 骑行中:后台定位 + GPS 轨迹写入 `ride_points` + 打卡
- 骑行总结:调 `recalculate_ride_stats` 出统计 + 徽章
- 首页/权限状态页
