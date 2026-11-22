import SwiftUI
import UIKit
import Observation

/// WELL WAY 设计规范(Figma `wellway` 稿):浅灰背景、白卡片、黑白主色(无蓝色)
// MARK: - 触觉反馈

/// 主行动、选择、成功三类触觉集中在一处：
/// 之前只有收藏和选车调了 selection，开始骑行、添加到出发页这些
/// 真正"重"的动作反而没有反馈，点下去像点了个图片。
enum Haptics {
    /// 主行动（开始骑行 / 添加车辆 / 添加到出发页）
    static func tap() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// 单选、收藏这类轻量状态切换
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}


enum Theme {
    static let primary = Color.black
    static let background = Color(red: 0xF5 / 255, green: 0xF7 / 255, blue: 0xFA / 255)
    static let card = Color.white
    static let textPrimary = Color(red: 0x0F / 255, green: 0x11 / 255, blue: 0x15 / 255)
    static let textSecondary = Color(red: 0x6F / 255, green: 0x76 / 255, blue: 0x83 / 255)
    /// 第三层级文字：只用于说明、占位和未选中项，不用于正文或主数据。
    static let textTertiary = Color(red: 0x7C / 255, green: 0x82 / 255, blue: 0x8C / 255)
    static let separator = Color(red: 0xE6 / 255, green: 0xE9 / 255, blue: 0xEF / 255)
    /// 列表右侧箭头(比分隔线更深一档，保证可见)
    static let chevron = Color(red: 0xC2 / 255, green: 0xC7 / 255, blue: 0xD0 / 255)
    static let success = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x7E / 255)
    /// 白底上的成功色文字：品牌绿 #22C57E 对白底只有约 2.1:1，
    /// 只用于填充 / 图标；「已打卡」「已完成」这类文字改用这一档，约 5:1。
    static let successText = Color(red: 0x0B / 255, green: 0x7F / 255, blue: 0x52 / 255)
    /// 危险色同时用于文字（删除记录 / 移除 / 未开启）和填充。
    /// #E53939 对白底只有 4.2:1，16pt 常规字重不达标，压到 #C9281F（5.5:1）。
    static let danger = Color(red: 0xC9 / 255, green: 0x28 / 255, blue: 0x1F / 255)


    // 路线页深色 HUD 与浅色列表共用色板
    static let darkBackground = Color(red: 0x14 / 255, green: 0x15 / 255, blue: 0x1A / 255)
    static let darkCard = Color(red: 0x24 / 255, green: 0x26 / 255, blue: 0x2B / 255)
    static let darkMeta = Color(red: 0xDA / 255, green: 0xDA / 255, blue: 0xDA / 255)
    static let listGray = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0x9A / 255)
    static let lightField = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF2 / 255)
    static let chipBackground = Color(red: 0xF7 / 255, green: 0xF7 / 255, blue: 0xF7 / 255)
    static let ink = Color(red: 0x24 / 255, green: 0x26 / 255, blue: 0x2B / 255)
    static let cardStroke = Color(red: 0xE9 / 255, green: 0xE9 / 255, blue: 0xEB / 255)

    // 车库首页的数据带、发丝线与轮播点；v6 只允许从这里取中性色。
    static let bandBackground = Color(red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xFA / 255)
    static let hairline = Color(red: 0xF1 / 255, green: 0xF3 / 255, blue: 0xF5 / 255)
    static let hairlineStrong = Color(red: 0xE7 / 255, green: 0xEA / 255, blue: 0xEE / 255)
    static let dotIdle = Color(red: 0xB8 / 255, green: 0xBE / 255, blue: 0xC8 / 255)
    /// 真实轨迹与路线信号的专用色，不随文字灰阶变化。
    static let routeSignal = Color(red: 0x00 / 255, green: 0xA9 / 255, blue: 0x9D / 255)

    /// 车辆空态统一使用两轮车图标；iOS 18 起系统提供摩托车，旧系统回退到自行车。
    static var vehicleSymbol: String {
        if #available(iOS 18.0, *) { return "motorcycle" }
        return "bicycle"
    }

    /// 通用卡片样式
    static func cardStyle(_ view: some View) -> some View {
        view
            .background(card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 全站搜索框共用外观：44pt 高、14pt 内边距、浅灰全圆角胶囊（v6）。
/// 焦点、提交和清除按钮仍由页面自己处理，避免各页复制出不同的内边距或圆角。
private struct WellwaySearchFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Theme.lightField)
            .clipShape(Capsule())
    }
}

extension View {
    func wellwaySearchFieldStyle() -> some View {
        modifier(WellwaySearchFieldStyle())
    }
}

/// 通用空态：裸图标 + 16 semibold 标题 + 13 说明(全站统一，不用系统 ContentUnavailableView)
struct DesignEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                // 空态图标是装饰：读屏会念出 SF Symbol 的英文名（motorcycle / bell）
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 14)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 二级页隐藏 Tab 栏

extension View {
    /// 二级页统一隐藏底部 Tab 栏。
    /// iOS 26 的悬浮 Tab 栏由系统绘制，连 UIKit 的 tabBar.isHidden 也会被覆盖，
    /// 因此这里只声明意图；页面自身仍要留出底部安全间距，避免内容被悬浮栏压住。
    @ViewBuilder
    func hidesAppTabBar() -> some View {
        if #available(iOS 18.0, *) {
            self.toolbarVisibility(.hidden, for: .tabBar)
        } else {
            self.toolbar(.hidden, for: .tabBar)
        }
    }
}

/// 面向用户的错误文案：不把 URLSession / PostgREST 的英文原文直接暴露在界面里。
extension Error {
    var wellwayUserMessage: String {
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "网络连接不可用，请检查网络后重试"
            case .timedOut:
                return "请求超时，请稍后重试"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "服务暂时不可用，请稍后重试"
            default:
                break
            }
        }

        let raw = localizedDescription.lowercased()
        if raw.contains("network") || raw.contains("internet") || raw.contains("offline") {
            return "网络连接不可用，请检查网络后重试"
        }
        if raw.contains("timeout") || raw.contains("timed out") {
            return "请求超时，请稍后重试"
        }
        if raw.contains("permission") || raw.contains("denied") || raw.contains("row-level security") {
            return "当前操作没有权限"
        }
        return "操作未完成，请稍后重试"
    }
}

/// 网络错误页(Figma「网络错误」)
struct NetworkErrorView: View {
    @Environment(AuthManager.self) private var auth
    @State private var isSigningOut = false

    let message: String?
    let retry: () -> Void

    private var rawMessage: String {
        (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 标题已经写了「网络连接失败」，正文不能再从「网络连接不可用」开头：
    /// 两行连起来读就是同一句话说了两遍（各页把 URLError 的兜底文案直接传进来时必然触发）。
    private var displayMessage: String {
        if rawMessage.isEmpty { return "请检查网络设置" }
        if rawMessage.hasPrefix("网络连接不可用") || rawMessage.hasPrefix("网络连接失败") {
            return "请检查网络设置"
        }
        // 标题已经写「请求超时」，正文再重复一遍会把两行读成同一句话。
        if rawMessage.hasPrefix("请求超时") {
            return "服务器响应较慢"
        }
        // 同理：标题是「没有操作权限」，正文别再重复「没有权限」，也不再承诺一个「重试」做不到的重登。
        if rawMessage.hasPrefix("当前操作没有权限") {
            return "当前账号无权访问该内容"
        }
        return rawMessage
    }

    /// 只有真正连不上网才配 wifi.slash +「网络连接失败」。
    /// 服务端 5xx、表缺失（PGRST205）、RLS 拒绝都会走到这里，
    /// 一律套上「请检查网络设置」会让用户去查自己的 Wi-Fi，问题却在我们这边。
    private enum Kind { case network, timeout, permission, generic }

    private var kind: Kind {
        if rawMessage.isEmpty { return .network }
        if rawMessage.contains("网络") { return .network }
        if rawMessage.contains("超时") { return .timeout }
        if rawMessage.contains("权限") || rawMessage.contains("登录") { return .permission }
        return .generic
    }

    private var title: String {
        switch kind {
        case .network: return "网络连接失败"
        case .timeout: return "请求超时"
        case .permission: return "没有操作权限"
        case .generic: return "加载失败"
        }
    }

    private var icon: String {
        switch kind {
        case .network: return "wifi.slash"
        case .timeout: return "clock"
        case .permission: return "lock"
        case .generic: return "exclamationmark.triangle"
        }
    }

    /// 权限错误重试同一个请求不会恢复权限；这里必须真的清掉会话回登录页。
    private var actionTitle: String {
        guard kind == .permission else { return "重试" }
        return isSigningOut ? "正在退出…" : "重新登录"
    }

    private func performAction() {
        guard kind == .permission else {
            retry()
            return
        }
        guard !isSigningOut else { return }
        isSigningOut = true
        Task {
            await auth.signOut()
            isSigningOut = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignEmptyState(
                icon: icon,
                title: title,
                message: displayMessage
            )
            Button(action: performAction) {
                Text(actionTitle)
                    // 与全站空态主行动同一档：16pt / 52pt / 通栏。
                    // 200×46 的小黑块是旧规格，错误态会被读成次要操作。
                    // 组件自己留 20pt 边距：它既会出现在已带 20pt 内边距的页面里，
                    // 也会直接铺在根容器上，不能指望调用方补边距。
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .disabled(isSigningOut)
            .accessibilityHint(kind == .permission ? "退出当前账号并返回登录页" : "重新加载当前内容")
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

/// 刷新失败但仍有上次数据时的轻量提示：不打断当前内容，只提示并允许重试。
struct InlineRefreshNotice: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.danger)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(action: retry) {
                Text("重试")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    // 12pt 文字自身只有十几点高，热区必须由内容补齐到 44pt，
                    // 否则提示条右侧成了一个看得见、点不准的小角落。
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 12)
        // 固定 42pt 会把重试按钮的 44pt 热区裁掉，改成只给下限。
        .frame(minHeight: 44)
        .background(Theme.danger.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 行内文字动作（重试、返回等）：视觉仍保持 12–14pt，
/// 但点击区域必须补齐 44pt，避免小字看得见、点不准。
struct InlineActionButton: View {
    let title: String
    var fontSize: CGFloat = 13
    var alignment: Alignment = .center
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 44, minHeight: 44, alignment: alignment)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
    }
}

/// 设计稿子页头部：返回箭头(中心 28,74) + 左对齐标题 20 Bold(文字起点 x=52,中心 y=74)
/// 固定坐标，不依赖 safeAreaInsets,保证所有页面(含 ignoresSafeArea 的空态页)位置完全一致
/// compact:Tab 根页面使用(容器从安全区顶部开始),标题上移到状态栏正下方(中心 y≈70),头部高度 72
/// 固定底部主按钮栏的统一底：白底铺到屏幕底部 + 顶部发丝线 + 18pt 白→透明渐变。
/// 渐变让被按钮栏齐边切断的滚动内容读成「滑到栏下」，而不是卡片被裁坏。
struct WellwayBottomBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color.white
                    .ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
            )
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 18)
                .offset(y: -18)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func wellwayBottomBar() -> some View { modifier(WellwayBottomBarModifier()) }
}

struct DesignPageHeader: View {
    let title: String
    /// Tab 根页面(无上级可返回)传 false,不显示返回箭头，标题位置保持不变
    var showsBack: Bool = true
    /// Tab 根页面传 true:标题中心 y≈70,内容起始 y≈131(与参考图一致)
    var compact: Bool = false
    /// 覆盖默认的 dismiss 行为：全屏覆盖层用 onClose 回调关闭时传它
    var onBack: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    /// Tab 根页标题从所在容器顶部起算，小屏(状态栏仅 20pt)会顶到状态栏上，
    /// 因此按真实安全区兜一个下限：标题中心距屏幕顶部至少 48pt。
    /// compact 页头里标题中心距容器顶部的距离。
    /// 页面若要在标题同一行挂右侧控件（关闭/更多），必须用这个值定位，
    /// 否则控件会落到 48pt 页头的正中，比标题低 12–15pt。
    static var compactTitleCenterY: CGFloat {
        let safeTop = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.top ?? 20
        return max(9, 48 - safeTop)
    }
    private var compactTitleY: CGFloat { Self.compactTitleCenterY }
    private var titleY: CGFloat { compact ? compactTitleY : 74 }
    // 标题 frame 240 宽左对齐：文字起点 = titleX-120。
    // 非 compact(子页)文字起点 x=48,更靠近返回键；compact(Tab 根页)文字起点 x=20,
    // 与页面 20pt 内容边距对齐（此前 16pt 会让标题比正文明显左移）。
    private var titleX: CGFloat { compact ? 140 : 168 }
    private var headerHeight: CGFloat { compact ? max(48, titleY + 24) : 86 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsBack {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    BackChevron()
                        .frame(width: 24, height: 24)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel("返回")
                .position(x: 28, y: titleY)
            }

            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 240, height: 24, alignment: .leading)
                .position(x: titleX, y: titleY)
        }
        // 头部用全宽 + 左对齐，避免 375 设计稿宽度在 402pt 屏上居中导致整体右移 13.5pt
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: headerHeight, alignment: .topLeading)
        // 固定页头必须有实底：协议页等内容会在下方滚动，
        // 透明页头会让正文从标题和返回箭头上穿过去，形成两层文字重叠。
        .background(Color.white)
    }
}

/// 加载中(Figma「加载中」158:2182):返回键 + 标题 + 圆环 + 加载文案
struct LoadingPageView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("返回")
            .position(x: 28, y: 74)

            Text("加载中")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.black)
                .position(x: 97, y: 74)

            ZStack {
                Circle()
                    .stroke(Color(red: 0xf2/255, green: 0xf2/255, blue: 0xf2/255), lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                Circle()
                    .fill(Color.black)
                    .frame(width: 12, height: 12)
                    .offset(x: 28, y: 0)
            }
            .position(x: 187.5, y: 280)

            Text("加载中...")
                .font(.system(size: 14))
                .foregroundColor(Color(red: 0x9a/255, green: 0x9a/255, blue: 0x9a/255))
                .position(x: 187.5, y: 388.5)
        }
        .frame(width: 375, height: 812)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        .pageMark(42)
    }
}

// MARK: - 日期解析

extension ISO8601DateFormatter {
    /// 解析 Supabase timestamptz(带小数秒),默认格式失败时回退带小数秒格式
    static func wellwayDate(from iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso)
    }
}

// MARK: - 黑白分享按钮

/// 分享/保存按钮(Figma 黑白主题):普通 Button 呈现，点击弹出系统分享面板。
/// 不用 ShareLink —— 它在 iOS 26 上会套用系统 Liquid Glass 蓝色样式，破坏黑白主题。
struct ShareButton: View {
    let title: String
    let items: [String]
    @State private var showShare = false

    var body: some View {
        Button {
            showShare = true
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .sheet(isPresented: $showShare) {
            ShareSheet(items: items)
        }
    }
}

/// 与主行动并排的次要分享按钮：52pt 方形、浅灰底、黑色图标，
/// 不跟主按钮抢注意力，也不用系统蓝。
struct ShareIconButton: View {
    let items: [String]
    var accessibilityLabel: String = "分享"
    @State private var showShare = false

    var body: some View {
        Button {
            showShare = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 52, height: 52)
                .background(Theme.lightField)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(CardPressStyle(scale: 0.94))
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $showShare) {
            ShareSheet(items: items)
        }
    }
}

/// 列表里的分享行：与「重命名」等操作行同高，右侧用分享图标代替 chevron
struct ShareRowButton: View {
    let title: String
    let items: [String]
    @State private var showShare = false

    var body: some View {
        Button {
            showShare = true
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .sheet(isPresented: $showShare) {
            ShareSheet(items: items)
        }
    }
}

/// 系统分享面板封装；字符串和图片可以一起交给系统，由用户选择存图或分享。
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var fileName: String = "WELLWAY 分享卡"

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: ShareExport.items(from: items, fileName: fileName), applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// 分享载荷：用 `sheet(item:)` 承载，避免 `items` 数组与 `isPresented`
/// 在同一次状态更新里被 SwiftUI 读到旧值、弹出空面板。
struct SharePayload: Identifiable {
    let id = UUID()
    var items: [Any]
    var fileName: String = "WELLWAY 分享卡"
}

/// 分享载荷整理：`ImageRenderer` 产出的内存位图直接交给分享面板时，
/// 缩略图会显示为空白棋盘格；落成临时 PNG 文件、改传文件 URL 则可以正常预览。
enum ShareExport {
    static func items(from items: [Any], fileName: String) -> [Any] {
        return items.map { item in
            guard let image = item as? UIImage else { return item }
            return pngFile(for: image, fileName: fileName) ?? image
        }
    }

    private static func pngFile(for image: UIImage, fileName: String) -> URL? {
        guard let data = pngData(for: image) else { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WellwayShare", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("\(sanitized(fileName))-\(Self.stamp()).png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func pngData(for image: UIImage) -> Data? {
        if let data = image.pngData() { return data }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    private static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "WELLWAY 分享卡" : cleaned
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMdd-HHmm"
        return formatter.string(from: Date())
    }
}

/// 车型真图下载器(内存缓存 + 失败重试),替代 `AsyncImage`。
///
/// 不用 `AsyncImage` 的原因：请求一旦被取消(视图重建/转场)它会把状态永久钉在 `.failure`
/// 且**不会重试**,「添加车辆」页的已选卡片正好在导航返回的转场里重建，于是照片区永远只剩插画回落。
/// 这里自己做：同一 URL 全程只下载一份、失败退避重试，下载与解码都在主线程之外。
@MainActor
@Observable
final class ModelPhotoLoader {
    static let shared = ModelPhotoLoader()

    /// 已下载完成的真图。视图 body 直接读它(观察追踪),所以图片到货后会自动刷新 ——
    /// 不依赖发起下载的那个 `.task` 是否已经被取消。
    private(set) var images: [URL: UIImage] = [:]
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    func cached(_ url: URL) -> UIImage? { images[url] }

    /// 取图：命中缓存直接返回；同一个 URL 的并发调用共用同一次下载
    func image(for url: URL) async -> UIImage? {
        if let image = images[url] { return image }
        if let running = inflight[url] { return await running.value }
        let task = Task<UIImage?, Never> { [weak self] in
            let image = await ModelPhotoLoader.download(url)
            if let image { self?.images[url] = image }
            self?.inflight[url] = nil
            return image
        }
        inflight[url] = task
        return await task.value
    }

    private static func download(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            for attempt in 0..<3 {
                if let data = try? await URLSession.shared.data(from: url).0,
                   let image = UIImage(data: data) {
                    return trimmed(image)
                }
                try? await Task.sleep(nanoseconds: 400_000_000 * UInt64(attempt + 1))
            }
            return nil
        }.value
    }

    /// 云端抠图四周留白并不统一(实测内容只占画布的 57%~100%,中位 81%),
    /// 直接用会在卡片里显得又小又空。这里按 alpha 把四周透明边裁掉、只留 4% 呼吸位，
    /// 让每个车型在框里都尽量"填满",尺寸/构图也统一。
    nonisolated private static func trimmed(_ image: UIImage) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let width = cg.width
        let height = cg.height
        guard width > 0, height > 0, cg.bitsPerPixel == 32 else { return image }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            // 不要在这里加 translate/scale 翻转：位图上下文画完后，**缓冲区第 0 行本来就是图片顶行**
            // (已用 2x2 红蓝图实测)。之前多翻了一次，车是倒着的。
            context.draw(cg, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard drawn else { return image }

        var minX = width, minY = height, maxX = -1, maxY = -1
        pixels.withUnsafeBufferPointer { buffer in
            for y in 0..<height {
                let row = y * width * 4
                for x in 0..<width where buffer[row + x * 4 + 3] > 12 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }

        let contentWidth = maxX - minX + 1
        let contentHeight = maxY - minY + 1
        let pad = Int((Double(max(contentWidth, contentHeight)) * 0.04).rounded())
        let outWidth = contentWidth + pad * 2
        let outHeight = contentHeight + pad * 2
        // 本来就贴边(没留白)的图不折腾
        guard outWidth < width || outHeight < height else { return image }

        var out = [UInt8](repeating: 0, count: outWidth * outHeight * 4)
        let rendered: CGImage? = out.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: outWidth,
                height: outHeight,
                bitsPerComponent: 8,
                bytesPerRow: outWidth * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            context.interpolationQuality = .high
            // 同上：不翻转，扫描出来的行号才能直接当裁剪/绘制坐标用
            context.draw(cg, in: CGRect(
                x: CGFloat(pad - minX),
                y: CGFloat(pad - minY),
                width: CGFloat(width),
                height: CGFloat(height)
            ))
            return context.makeImage()
        }
        guard let rendered else { return image }
        return UIImage(cgImage: rendered)
    }
}

/// 路线封面下载器：后台封面常见 7000px 级原图，直接交给 AsyncImage 会按原尺寸解码。
/// 这里统一下载、降采样到展示所需尺寸并缓存，避免列表滚动时内存暴涨。
@MainActor
@Observable
final class RouteCoverPhotoLoader {
    static let shared = RouteCoverPhotoLoader()

    private(set) var images: [URL: UIImage] = [:]
    private var inflight: [URL: Task<UIImage?, Never>] = [:]

    func cached(_ url: URL) -> UIImage? { images[url] }

    func image(for url: URL) async -> UIImage? {
        if let image = images[url] { return image }
        if let running = inflight[url] { return await running.value }
        let task = Task<UIImage?, Never> { [weak self] in
            let image = await RouteCoverPhotoLoader.download(url)
            if let image { self?.images[url] = image }
            self?.inflight[url] = nil
            return image
        }
        inflight[url] = task
        return await task.value
    }

    private static func download(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .utility) {
            for attempt in 0..<2 {
                if let data = try? await URLSession.shared.data(from: url).0,
                   let image = UIImage(data: data) {
                    return downscaled(image, maxDimension: 1_600)
                }
                try? await Task.sleep(nanoseconds: 350_000_000 * UInt64(attempt + 1))
            }
            return nil
        }.value
    }

    nonisolated private static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// 车型图片本体：云端 `image_url` 有真图就用真图（透明底整车抠图，4:3，用 fit 不裁切），
/// 没有(或没下下来)就回落到按分类的线稿插画。调用方负责给深色底和圆角。
struct ModelImage: View {
    let model: VehicleModel?
    /// 插画四周留白(真图有自己的透明留白，不额外加)
    var artPadding: CGFloat = 0
    /// 下载完成后必须落到本视图状态里，SwiftUI 才会重新渲染；
    /// ModelPhotoLoader 的缓存不是 Observable，仅读缓存会让冷启动停在占位图。
    @State private var loadedPhoto: UIImage?

    private var remoteURL: URL? {
        guard let raw = model?.imageUrl?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    var body: some View {
        Group {
            if let photo = loadedPhoto ?? cachedPhoto {
                // 真车抠图常贴着画布边缘，留一点呼吸位，避免轮胎被卡片边切到
                Image(uiImage: photo).resizable().scaledToFit().padding(artPadding)
            } else {
                art
            }
        }
        .task(id: remoteURL) {
            guard let url = remoteURL else {
                loadedPhoto = nil
                return
            }
            if let cached = ModelPhotoLoader.shared.cached(url) {
                loadedPhoto = cached
                return
            }
            loadedPhoto = await ModelPhotoLoader.shared.image(for: url)
        }
    }

    /// 已经下载好的真图：先读缓存，保证列表滚动回来时首帧就是真图
    private var cachedPhoto: UIImage? {
        guard let url = remoteURL else { return nil }
        return ModelPhotoLoader.shared.cached(url)
    }

    private var art: some View {
        // 没有实车图时用系统摩托车实心图形占位：线稿在 68pt 下容易被看成自行车，
        // 与产品语境不符。实心轮廓在列表缩略图尺寸下更清楚。
        GeometryReader { geo in
            Image(systemName: "motorcycle.fill")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .fontWeight(.semibold)
                .foregroundStyle(Theme.listGray.opacity(0.50))
                .frame(width: geo.size.width * 0.62, height: geo.size.height * 0.62)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .padding(artPadding)
    }
}

/// 车型缩略图。
///
/// 原来是一块 72x72 的深色方块、图缩在中间 —— 抠图是 4:3 横构图，塞进正方形上下会空掉一大半，
/// 所以改成和抠图同比例的框(默认 96x72),并且**不再垫任何不透明底色**:真车抠图是透明 PNG,
/// 直接落在行的白卡片上即可，车也就真正"填满"了整个框。
struct ModelThumbnail: View {
    let model: VehicleModel?
    /// 框高(与原来一致，行高不变)
    var size: CGFloat = 72
    /// 框宽高比：贴近真车抠图的 4:3 横构图，才能贴边填满(纯 4:3 会挤掉车名的宽度)
    var aspectRatio: CGFloat = 1.25

    var body: some View {
        ModelImage(model: model, artPadding: size * 0.06)
            .frame(width: size * aspectRatio, height: size)
    }
}


// MARK: - 时长文案

/// 路线预计用时：不再把 180 分钟直接怼给用户
enum RideDurationText {
    static func parts(minutes: Int) -> (value: String, unit: String?) {
        let total = max(0, minutes)
        guard total >= 60 else { return ("\(total)", "分钟") }
        let hours = total / 60
        let rest = total % 60
        return rest == 0 ? ("\(hours)", "小时") : ("\(hours) 小时 \(rest)", "分")
    }

    /// 指标行用的紧凑时长：把「2 小时 30 分」拆成大字「2」和小字「小时 30 分」，
    /// 四列 20pt 指标行里不会再被截成「2…」。
    static func metricParts(minutes: Int) -> (value: String, unit: String?) {
        let total = max(0, minutes)
        guard total >= 60 else { return ("\(total)", "分钟") }
        let hours = total / 60
        let rest = total % 60
        return rest == 0 ? ("\(hours)", "小时") : ("\(hours)", "小时 \(rest) 分")
    }

    static func inline(minutes: Int) -> String {
        let part = parts(minutes: minutes)
        return part.unit.map { "\(part.value) \($0)" } ?? part.value
    }

    
    /// 记录列表用的中文时长：8 秒 / 10 分 8 秒 / 1 小时 2 分 8 秒
    static func words(seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 60 { return "\(total) 秒" }
        let h = total / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) 小时") }
        if m > 0 { parts.append("\(m) 分") }
        if s > 0 { parts.append("\(s) 秒") }
        return parts.joined(separator: " ")
    }
    /// 读屏用：屏幕上的「1 小时 8 分」在这里补成「1 小时 8 分钟」，
    /// 单念「分」容易被听成「八分」这种分数。
    static func spoken(seconds: Int) -> String {
        let text = words(seconds: seconds)
        if text.hasSuffix(" 分") { return String(text.dropLast(2)) + " 分钟" }
        return text
    }

    /// 单次骑行时长：不足 1 分钟用「18 秒」，其余用 m:ss / h:mm:ss
    static func elapsed(seconds: Int) -> String {
        let total = max(0, seconds)
        if total < 60 { return "\(total) 秒" }
        let h = total / 3_600
        let m = (total % 3_600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - 底部面板按内容贴合

/// 面板内容高度实测值。
struct SheetFitHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 让底部面板按内容高度贴合。
/// 固定高度的 detent 在内容比预设更短时，会把多余高度留在面板底部，
/// 看起来像「没加载完」。这里实测内容高度；空态/未加载时退回 fallback。
private struct FittedSheetHeight: ViewModifier {
    let fallback: CGFloat
    let maxHeight: CGFloat
    @State private var measured: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: SheetFitHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(SheetFitHeightKey.self) { height in
                guard height > 0, abs(height - measured) > 0.5 else { return }
                measured = min(height, maxHeight)
            }
            .presentationDetents([.height(measured > 0 ? measured : fallback)])
    }
}

extension View {
    /// - Parameters:
    ///   - fallback: 内容还没量出来（或为空态）时使用的高度
    ///   - maxHeight: 上限，文字放大到撑满屏幕时不让面板超过可读高度
    func fittedSheetHeight(fallback: CGFloat, maxHeight: CGFloat = 620) -> some View {
        modifier(FittedSheetHeight(fallback: fallback, maxHeight: maxHeight))
    }
}

// MARK: - 分段控件

/// v6 分段控件：浅灰胶囊底 + 黑色选中片，44pt 热区。
/// 记录页的「全部 / 已完成」与统计页的「本周 / 本月」共用同一套比例，
/// 避免同一个 App 里出现两种高度或两种选中样式。
struct DesignSegmentedControl: View {
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(option)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                        .frame(width: 76, height: 30)
                        .background(isSelected ? Theme.textPrimary : Color.clear)
                        .clipShape(Capsule())
                        .frame(width: 76, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(CardPressStyle(scale: 0.96))
                // 选中态只靠黑底白字表达时，旁白读不出当前筛选；补上系统选中特征。
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.horizontal, 3)
        .frame(height: 44)
        .background {
            Capsule()
                .fill(Theme.lightField)
                .frame(height: 36)
        }
    }
}

// MARK: - 等宽指标行

/// 指标行里「不参与等分」的子视图（分隔线）标记：宽度按自身固定，其余列严格等分。
private struct MetricRowFixedKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    /// 标记指标行里的分隔线：不参与等分，保留自身固定宽度。
    func metricRowFixed() -> some View {
        layoutValue(key: MetricRowFixedKey.self, value: true)
    }
}

/// 指标行的等宽列：每列分到的宽度完全一样。
/// 直接用 HStack 时，SwiftUI 会把剩余空间让给理想宽度更大的列，数字长短一变，
/// 竖向分隔线就跟着漂（骑行总结四列实测漂 8–19pt，同一个组件在四个页面各漂各的）。
struct MetricRowLayout: Layout {
    var spacing: CGFloat = 0

    private func columnWidth(total: CGFloat, subviews: Subviews) -> CGFloat {
        var fixed: CGFloat = 0
        var flexible = 0
        for view in subviews {
            if view[MetricRowFixedKey.self] {
                fixed += view.sizeThatFits(.unspecified).width
            } else {
                flexible += 1
            }
        }
        guard flexible > 0 else { return 0 }
        let gaps = spacing * CGFloat(max(0, subviews.count - 1))
        return max(0, (total - fixed - gaps) / CGFloat(flexible))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let column = columnWidth(total: width, subviews: subviews)
        var height: CGFloat = 0
        for view in subviews {
            let w = view[MetricRowFixedKey.self] ? view.sizeThatFits(.unspecified).width : column
            height = max(height, view.sizeThatFits(ProposedViewSize(width: w, height: nil)).height)
        }
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let column = columnWidth(total: bounds.width, subviews: subviews)
        var x = bounds.minX
        for view in subviews {
            let isFixed = view[MetricRowFixedKey.self]
            let w = isFixed ? view.sizeThatFits(.unspecified).width : column
            view.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: w, height: bounds.height)
            )
            x += w + spacing
        }
    }
}
