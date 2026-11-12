import SwiftUI
import MapKit
import CoreLocation
import UserNotifications

/// 导航方式选择全局呈现状态：由 MainTabView 挂载覆盖层(盖住 Tab 栏),
/// 避开 iOS 26 浮动式 sheet 底部留白问题，保证面板贴底且完全不透明。
@Observable
@MainActor
final class NavChoiceCenter {
    var isPresented = false
    var route: Route?
    var onWellway: (() -> Void)?
    var startLat: Double?
    var startLng: Double?
    var endLat: Double?
    var endLng: Double?
    /// 用户当前定位(打开第三方导航时作为起点，实现「当前位置-起点-终点」三段同步)
    var currentLat: Double?
    var currentLng: Double?
    /// 定位请求是否在途(面板顶部显示「正在获取当前位置…」)
    var isLocating = false
    /// 已选择「先导航到路线起点」:回到 App 后检测是否已到达起点附近
    var awaitingArrivalAtStart = false
    /// 上次选择的第三方地图(起点段与终点段保持一致)
    var lastExternalKind: String?

    /// 距路线起点的公里数(nil=缺起点坐标或定位)
    var distanceToStartKm: Double? {
        guard let currentLat, let currentLng, let startLat, let startLng else { return nil }
        let here = CLLocation(latitude: currentLat, longitude: currentLng)
        let start = CLLocation(latitude: startLat, longitude: startLng)
        return here.distance(from: start) / 1000
    }

    private var fetcher = OneShotLocationFetcher()
    private(set) var locationTask: Task<Void, Never>?

    /// 单飞定位：已有在途请求时直接等待其完成，避免并发覆盖 continuation
    func fetchCurrentLocation() async {
        if isLocating {
            await locationTask?.value
            return
        }
        isLocating = true
        let task = Task {
            let loc = await fetcher.fetchLocation()
            isLocating = false
            if let loc {
                currentLat = loc.coordinate.latitude
                currentLng = loc.coordinate.longitude
            }
        }
        locationTask = task
        await task.value
    }

    /// 打开第三方地图。toStart=true 时只导航到路线起点，否则导航到路线终点；
    /// 起点判定后不再用多段停靠，避免第三方不支持。
    func openExternalMap(kind: String, toStart: Bool = false) {
        guard let route else { return }
        let currentLat = self.currentLat
        let currentLng = self.currentLng
        let startLat = self.startLat
        let startLng = self.startLng
        let endLat = self.endLat
        let endLng = self.endLng
        let fromLat = currentLat ?? startLat
        let fromLng = currentLng ?? startLng
        if kind == "amap" {
            // 高德：优先直接唤起已安装的 App(iosamap://),未安装时退回 uri.amap.com 网页跳转
            var legacy = URLComponents(string: "iosamap://path")
            var legacyItems = [
                URLQueryItem(name: "sourceApplication", value: "WELLWAY"),
                URLQueryItem(name: "t", value: "3"),
                // 我们传的全部是 WGS-84 原始坐标（GPS / GPX），dev 固定 1 让高德做
                // 火星坐标偏移；之前按「有没有定位」在 0/1 之间切，是没有 GPS 时
                // 点位会整体偏移约 500 米的根因。
                URLQueryItem(name: "dev", value: "1")
            ]
            if toStart, let startLat, let startLng {
                legacyItems.append(URLQueryItem(name: "dlat", value: "\(startLat)"))
                legacyItems.append(URLQueryItem(name: "dlon", value: "\(startLng)"))
                legacyItems.append(URLQueryItem(name: "dname", value: route.startName ?? "路线起点"))
            } else if let endLat, let endLng {
                legacyItems.append(URLQueryItem(name: "dlat", value: "\(endLat)"))
                legacyItems.append(URLQueryItem(name: "dlon", value: "\(endLng)"))
                legacyItems.append(URLQueryItem(name: "dname", value: route.endName ?? "路线终点"))
            } else {
                legacyItems.append(URLQueryItem(name: "dname", value: route.endName ?? route.name))
            }
            if let fromLat, let fromLng {
                // 去起点时若没有 App 定位，不要把自己的起点同时写成起终点；
                // 交给高德使用设备当前位置。
                if currentLat != nil || !toStart {
                    legacyItems.append(URLQueryItem(name: "slat", value: "\(fromLat)"))
                    legacyItems.append(URLQueryItem(name: "slon", value: "\(fromLng)"))
                    legacyItems.append(URLQueryItem(name: "sname", value: currentLat != nil ? "我的位置" : (route.startName ?? "路线起点")))
                }
            }
            legacy?.queryItems = legacyItems
            if let url = legacy?.url, UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
            // 高德 URI API 兜底(callnative=1 拉起 App)
            var comps = URLComponents(string: "https://uri.amap.com/navigation")
            var items: [URLQueryItem] = []
            if let currentLat, let currentLng {
                items.append(URLQueryItem(name: "from", value: "\(currentLng),\(currentLat),我的位置"))
            } else if !toStart, let fromLat, let fromLng {
                items.append(URLQueryItem(name: "from", value: "\(fromLng),\(fromLat),我的位置"))
            }
            if toStart, let startLat, let startLng {
                items.append(URLQueryItem(name: "to", value: "\(startLng),\(startLat),\(route.startName ?? "路线起点")"))
            } else if let endLat, let endLng {
                items.append(URLQueryItem(name: "to", value: "\(endLng),\(endLat),\(route.endName ?? "路线终点")"))
            } else {
                items.append(URLQueryItem(name: "to", value: route.endName ?? route.name))
            }
            items.append(URLQueryItem(name: "mode", value: "ride"))
            items.append(URLQueryItem(name: "callnative", value: "1"))
            items.append(URLQueryItem(name: "src", value: "wellway"))
            comps?.queryItems = items
            if let url = comps?.url {
                UIApplication.shared.open(url)
                return
            }
        }
        // 苹果地图：只传起点/终点两段(maps:// 直连避免网页跳转丢参数)
        var appleQuery = ""
        if let currentLat, let currentLng {
            appleQuery += "saddr=\(currentLat),\(currentLng)"
            if toStart, let startLat, let startLng {
                appleQuery += "&daddr=\(startLat),\(startLng)"
            } else if let endLat, let endLng {
                appleQuery += "&daddr=\(endLat),\(endLng)"
            }
        } else if let startLat, let startLng {
            if toStart {
                // 没有当前位置、但用户明确选择先到起点：不要把终点一起带进去。
                appleQuery += "daddr=\(startLat),\(startLng)"
            } else {
                appleQuery += "saddr=\(startLat),\(startLng)"
                if let endLat, let endLng {
                    appleQuery += "&daddr=\(endLat),\(endLng)"
                }
            }
        }
        let endName = route.endName ?? route.name
        if !appleQuery.contains("daddr") {
            // 坐标缺失时仍用名称预填目的地，避免只打开地图首页。
            let destination = toStart ? (route.startName ?? "路线起点") : endName
            let encoded = destination.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destination
            appleQuery += "\(appleQuery.isEmpty ? "" : "&")daddr=\(encoded)"
        }
        appleQuery += "\(appleQuery.isEmpty ? "" : "&")dirflg=d"
        if let url = URL(string: "maps://?\(appleQuery)") {
            UIApplication.shared.open(url)
        }
    }
}

/// 导航方式选择(Figma「导航方式选择」)
struct NavChoiceSheet: View {
    /// 面板阶段：选导航方式 / 不在起点附近的确认 / 定位失败
    enum Stage { case choice, confirmStart, locationError }

    @Binding var isPresented: Bool
    let route: Route
    var startLat: Double?
    var startLng: Double?
    var endLat: Double?
    var endLng: Double?
    var currentLat: Double?
    var currentLng: Double?
    var isLocating = false
    /// 数据源(挂载方传入):定位等异步更新后，按钮点击仍能读到最新值
    var center: NavChoiceCenter?
    /// 正在进行的定位任务(供入口等待定位完成后自动判定)
    var locationTask: Task<Void, Never>?
    /// 重新获取定位(由挂载方注入)
    var onRetryLocation: (() -> Void)?
    /// 调试入口：直接展示「不在起点附近」确认状态
    var autoConfirmGoToStart = false
    let onWellway: () -> Void

    @State private var stage: Stage = .choice
    /// 等待确认的第三方地图类型(amap / apple)
    @State private var pendingExternalKind: String?

    /// 距路线起点的公里数(nil=缺起点坐标或定位)
    private var distanceToStartKm: Double? {
        let curLat = center?.currentLat ?? currentLat
        let curLng = center?.currentLng ?? currentLng
        let sLat = center?.startLat ?? startLat
        let sLng = center?.startLng ?? startLng
        guard let curLat, let curLng, let sLat, let sLng else { return nil }
        let here = CLLocation(latitude: curLat, longitude: curLng)
        let start = CLLocation(latitude: sLat, longitude: sLng)
        return here.distance(from: start) / 1000
    }

    /// 是否已在路线起点附近(500m 内)。定位未知时不臆断，按「在起点」处理。
    private var atRouteStart: Bool {
        guard let d = distanceToStartKm else { return true }
        return d <= 0.5
    }

    /// 超出该距离视为异地路线：不再建议「先骑到起点」(100 km 内仍属正常接驳)
    private var isFarFromStart: Bool {
        (distanceToStartKm ?? 0) >= 100
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if stage == .choice { dismissPanel() } else { stage = .choice }
                }

            VStack(spacing: 0) {
                Capsule()
                    .fill(Theme.separator)
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)

                switch stage {
                case .choice: choiceContent
                case .confirmStart: confirmStartContent
                case .locationError: locationErrorContent
                }
            }
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .pageMark(52)
        .task {
            if autoConfirmGoToStart {
                pendingExternalKind = "amap"
                stage = .confirmStart
            }
        }
    }

    // MARK: - 选导航方式

    private var choiceContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择导航方式")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)

            if startLat != nil, startLng != nil {
                statusRow
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
            } else {
                Color.clear.frame(height: 12)
            }

            VStack(spacing: 0) {
                Button {
                    dismissPanel()
                    onWellway()
                } label: {
                    navRow(
                        title: "WellWay 骑行模式",
                        subtitle: atRouteStart
                            ? "记录轨迹与打卡"
                            : "从当前位置开始记录，可先骑到路线起点",
                        titleBold: true
                    )
                }
                Button {
                    handleExternalNavigation("amap")
                } label: {
                    navRow(title: "高德地图", subtitle: "跳转后在高德内切换摩托车路线")
                }
                Button {
                    handleExternalNavigation("apple")
                } label: {
                    navRow(title: "苹果地图", subtitle: "仅驾车导航，无摩托车模式")
                }
            }
            .padding(.horizontal, 20)

            Button {
                dismissPanel()
            } label: {
                Text("取消")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
        }
    }

    // MARK: - 不在起点附近

    private var confirmStartContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isFarFromStart ? "路线距离较远" : "你不在起点附近")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)

            Text(startDistanceCopy)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Button {
                guard let kind = pendingExternalKind else { return }
                pendingExternalKind = nil
                center?.lastExternalKind = kind
                center?.awaitingArrivalAtStart = true
                dismissPanel()
                center?.openExternalMap(kind: kind, toStart: true)
            } label: {
                Text("导航到该路线起点")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.top, 22)

            Button {
                guard let kind = pendingExternalKind else { return }
                pendingExternalKind = nil
                center?.lastExternalKind = kind
                dismissPanel()
                // 用户尚未到达路线起点：只做第三方导航，
                // 不把前往起点的路程计入本次路线骑行记录。
                center?.openExternalMap(kind: kind, toStart: false)
            } label: {
                Text("导航到该路线终点")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Theme.lightField)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.top, 12)

            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.top, 6)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { stage = .choice }
            } label: {
                Text("取消")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(RowPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    /// 距离未知或近到可以忽略时不再报「约 0.0 公里」，避免和「不在起点附近」自相矛盾
    private var startDistanceCopy: String {
        guard let km = distanceToStartKm, km >= 0.1 else {
            return "可先去起点，或直接前往终点。"
        }
        if isFarFromStart {
            return String(format: "该路线起点距你约 %.0f km。建议抵达当地后再开始骑行，也可让地图 App 先导航到起点。", km)
        }
        return String(format: "距路线起点约 %.1f km。可先去起点，或直接前往终点。", km)
    }

    // MARK: - 定位失败

    private var locationErrorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("无法获取你的位置")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 18)

            Text("可以重试，或让地图 App 使用自己的定位先导航到路线起点。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { stage = .choice }
                onRetryLocation?()
            } label: {
                Text("重新获取")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.top, 22)

            Button {
                guard let kind = pendingExternalKind else { return }
                pendingExternalKind = nil
                center?.lastExternalKind = kind
                center?.awaitingArrivalAtStart = true
                dismissPanel()
                center?.openExternalMap(kind: kind, toStart: true)
            } label: {
                Text("先导航到路线起点")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textPrimary.opacity(0.86))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(SolidPressStyle())
            .padding(.top, 12)

            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
                .padding(.top, 6)

            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { stage = .choice }
            } label: {
                Text("取消")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(RowPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func dismissPanel() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            isPresented = false
        }
    }

    /// 第三方地图入口：起点判定分流
    /// 已到达起点附近 → 直接导航到终点并开始记录；
    /// 未到达 → 先确认是否导航到起点(不开始记录，到达后回 App 再开始)。
    private func handleExternalNavigation(_ kind: String) {
        guard center?.currentLat != nil, center?.currentLng != nil else {
            if isLocating, let task = locationTask {
                // 定位仍在进行：等它完成后自动继续判定
                Task {
                    await task.value
                    handleExternalNavigation(kind)
                }
                return
            }
            pendingExternalKind = kind
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { stage = .locationError }
            return
        }
        if let d = distanceToStartKm, d > 0.5 {
            pendingExternalKind = kind
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { stage = .confirmStart }
        } else {
            dismissPanel()
            center?.openExternalMap(kind: kind)
            // 使用外部地图导航时同步开启 App 内计时/轨迹记录
            onWellway()
        }
    }

    /// 面板顶部状态行：距起点的距离 / 是否已到达 / 定位中
    @ViewBuilder
    private var statusRow: some View {
        if let d = distanceToStartKm {
            if d <= 0.5 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.success)
                        // 装饰图标：读屏会单独念出一个「Selected」，和下面的文案重复
                        .accessibilityHidden(true)
                    Text("已到达路线起点，可直接导航至终点")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "location")
                        .font(.system(size: 12))
                        .accessibilityHidden(true)
                    Text(isFarFromStart
                         ? String(format: "距起点 %.0f km，建议抵达当地后再出发", d)
                         : String(format: "距起点 %.1f km，先导航至起点", d))
                        .font(.system(size: 13))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Theme.textSecondary)
            }
        } else {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("正在获取当前位置…")
                    .font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func navRow(title: String, subtitle: String, titleBold: Bool = false) -> some View {
        HStack(spacing: 0) {
            // 三个选项都用纯文字：只有首行挂品牌标时，后两行会空出一整列，
            // 读起来像漏了图标；标题本身已经写明「WellWay 骑行模式」。
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: titleBold ? .semibold : .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.chevron)
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }
}

/// 骑行总结展示载体：通过 fullScreenCover(item:) 原子传值
struct RideSummaryItem: Identifiable {
    let id = UUID()
    let summary: RideSummary
}

/// 骑行中(Figma「骑行中」):速度 / 里程 / 时长 / 地图轨迹 / 暂停结束
struct RidingView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    /// 深色 HUD 期间把根视图外观压成深色(HUD 是全屏的,下层不可见)
    private var screenAppearance: ScreenAppearance { .shared }

    let route: Route
    let checkpoints: [Checkpoint]
    let vehicleId: UUID?
    let vehicleName: String?
    /// 设计自查入口专用：展示完整 HUD,但不启动定位/不写入骑行记录
    var demo: Bool = false
    /// 设计自查入口：直接展示「已到达终点」提示卡
    var demoArrival: Bool = false

    @State private var ride: RideService?
    @State private var showEndConfirm = false
    @State private var summaryItem: RideSummaryItem?
    @State private var ridersCount = 0
    @State private var showBanner = true
    @State private var didAnnounceArrival = false
    @State private var showTeamRiders = false
    @State private var showMapSwitch = false
    @State private var isEndingRide = false
    /// 总结页关闭后退出骑行：等全屏封面真正 dismiss 完再调用外层 dismiss，
    /// 避免两层 fullScreenCover 同时收起时外层请求被系统忽略。
    @State private var exitAfterSummaryDismiss = false
    /// 地图视野：默认自动，加载路线坐标后缩放到覆盖全程
    @State private var camera: MapCameraPosition = .automatic

    private var visibleRidersCount: Int { demo ? 7 : ridersCount }
    private var currentSpeedKmh: Double {
        if demo { return demoPaused ? 0 : 48 }
        return ride?.phase == .paused ? 0 : (ride?.speedKmh ?? 0)
    }

    /// 调试入口：`-ridingpaused` / `-ridingending` 在演示数据上静态展示暂停态与保存遮罩，
    /// 这两态要靠真实骑行才能触发，不做入口就只能读代码判断。
    private var demoPaused: Bool {
        demo && ProcessInfo.processInfo.arguments.contains("-ridingpaused")
    }
    private var demoEnding: Bool {
        demo && ProcessInfo.processInfo.arguments.contains("-ridingending")
    }
    private var riddenMeters: Double { demo ? (demoArrival ? Double(route.distanceM) : 8_200) : (ride?.distanceM ?? 0) }
    private var rideSeconds: Int { demo ? 2_138 : (ride?.durationS ?? 0) }

    /// 已接近/到达路线终点(短路线不触发，避免刚出发就提示)
    private var arrivalReached: Bool {
        !demo
            && ride?.phase == .riding
            && Double(route.distanceM) >= 500
            && remainingMeters <= 120
    }

    /// 顶部状态与到达提示共用同一个判断，避免「已到达」后仍显示骑行中
    private var hasArrived: Bool {
        demoArrival || arrivalReached
    }

    /// 路线规划线：按打卡点顺序连接(无轨迹时也能看到完整路线)
    private var routeCoords: [CLLocationCoordinate2D] {
        checkpoints
            .sorted { $0.seq < $1.seq }
            .compactMap { cp in
                guard let lat = cp.lat, let lng = cp.lng else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 700
            VStack(spacing: 0) {
                header
                // 已到达后「路线骑手」不再有行动意义，收起横幅把注意力留给停车
                if showBanner && visibleRidersCount > 0 && !hasArrived {
                    banner
                }
                if !demo && ride?.phase == .idle {
                    // 结束保存时先移除地图层，避免 MapKit 金属层与总结页 fullScreenCover 冲突导致内容空白
                    Color.clear
                        .frame(height: compact ? 190 : 280)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                } else {
                    mapArea(compact: compact)
                        .motionAppear(delay: 0.05)
                }
                statsPanel(compact: compact)
                    .motionAppear(delay: 0.15)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // 暂停时下面这层被覆盖，读屏不能再聚焦到看不见的地图和统计
            .accessibilityHidden(ride?.phase == .paused || demoPaused || isEndingRide || demoEnding)
            .overlay {
                if ride?.phase == .paused || demoPaused {
                    pauseOverlay(compact: compact)
                }
            }
        }
        .background(Theme.darkBackground.ignoresSafeArea())
        // 作为全屏 cover 呈现时,cover 自己的外观声明才决定状态栏颜色;根视图的 push 只是兜底
        .preferredColorScheme(.dark)
        .onAppear { screenAppearance.push(.dark) }
        .onDisappear { screenAppearance.pop(.dark) }
        .overlay {
            if isEndingRide || demoEnding {
                endingOverlay
            }
        }
        .onChange(of: arrivalReached) { _, reached in
            guard reached, !didAnnounceArrival else { return }
            didAnnounceArrival = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        .task {
            guard !demo, ride == nil else { return }
            let service = RideService(
                client: auth.client,
                route: route,
                checkpoints: checkpoints,
                userId: auth.user?.id ?? UUID(),
                vehicleId: vehicleId
            )
            ride = service
            await service.start()
            Task { await reportTripPlan() }
            await loadRiders()
            fitCameraToRoute()
        }
        // item 方式传值：总结数据随封面原子传入，避免 isPresented + @State 时序不同步导致空白/加载态
        .fullScreenCover(item: $summaryItem, onDismiss: {
            guard exitAfterSummaryDismiss else { return }
            exitAfterSummaryDismiss = false
            dismiss()
        }) { item in
            RideSummaryView(
                route: route,
                checkpoints: checkpoints,
                summary: item.summary,
                onFinish: {
                    // 等总结页关闭回调触发后，再退出整个骑行流程返回出发页
                    exitAfterSummaryDismiss = true
                    // 同步成功时给一次全局确认：否则「完成」之后回到出发页毫无反馈
                    if item.summary.saveWarning == nil {
                        let km = Double(item.summary.record?.distanceM ?? 0) / 1000
                        NotificationCenter.default.post(
                            name: .rideDidFinish,
                            object: km > 0
                                ? String(format: "骑行记录已保存 · %.1f km", km)
                                : "骑行记录已保存"
                        )
                    }
                    summaryItem = nil
                },
                onRetrySave: {
                    guard let ride else { return false }
                    return await ride.retryCompletion()
                }
            )
        }
        .wellwayDialog(
            isPresented: $showEndConfirm,
            title: "结束本次骑行？",
            message: "结束后将生成骑行总结，轨迹会保存到你的骑行记录",
            buttons: [
                WellwayDialogButton(title: "结束骑行", role: .destructive) {
                    Task { await finishRide() }
                }
            ]
        )
        .fullScreenCover(isPresented: $showMapSwitch) {
            MapSwitchView(route: route, checkpoints: checkpoints, ride: ride, riddenMeters: riddenMeters)
        }
        .fullScreenCover(isPresented: $showTeamRiders) {
            NavigationStack {
                RidersView(route: route, checkpoints: checkpoints)
            }
        }
        .pageMark(2)
    }

    /// 顶部：路线 / 车辆 + 当前状态
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.name)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(vehicleName ?? "未选择车辆")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.success)
                    .frame(width: 6, height: 6)
                // 到达后页面中央已经有一个大号「已到达」，胶囊再写一遍是重复；
                // 这里改成回答另一个问题：记录还在不在继续。
                Text(hasArrived ? "记录中" : "骑行中")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(.white.opacity(0.07))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    /// 暂停：沿用同一套信息层级，只把操作区切换为继续 / 结束
    private func pauseOverlay(compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(vehicleName ?? "未选择车辆")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 12)
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.white.opacity(0.55))
                        .frame(width: 6, height: 6)
                    Text("已暂停")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.white.opacity(0.07))
                .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, compact ? 8 : 20)

            if visibleRidersCount > 0 {
                HStack(spacing: 10) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.success)
                        .accessibilityHidden(true)
                    Text("正在这条路线骑行 \(visibleRidersCount) 位骑手")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Theme.darkCard)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .padding(.top, compact ? 12 : 18)
            }

            // 暂停时仍然保留地图上下文：骑手需要确认自己停在哪、离路线还有多远
            mapArea(compact: compact)
                .padding(.top, compact ? 12 : 18)

            // 短屏上固定 12pt 的最小间距会把底部两个按钮顶出屏幕，
            // 这里允许先压缩留白，保住底部 16pt 内边距
            Spacer(minLength: compact ? 0 : 12)

                // 短屏收紧：地图 + 速度 + 三格统计 + 剩余行 + 两个按钮刚好一屏
            VStack(spacing: compact ? 12 : 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(currentSpeedKmh, format: .number.precision(.fractionLength(0)))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        // 暂停时速度恒为 0，别让这个 0 抢走注意力
                        .foregroundStyle(.white.opacity(0.38))
                    Text("km/h")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                }

                MetricRowLayout {
                    pauseStatBlock("里程", value: String(format: "%.1f km", riddenMeters / 1000))
                    dividerOnDark
                    pauseStatBlock("时长", value: formatDuration(rideSeconds))
                    dividerOnDark
                    pauseStatBlock("均速", value: averageSpeed + " km/h")
                }
                .padding(.vertical, 18)
                .background(Theme.darkCard)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
                .padding(.horizontal, 16)
            }

            // 停下来了更要判断「继续还是结束」：剩余里程和打卡进度不能只在骑行态出现
            Text(pauseRemainingText)
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .accessibilityLabel(pauseRemainingAccessibilityLabel)

            Spacer(minLength: compact ? 0 : 12)

            VStack(spacing: 10) {
                Button {
                    ride?.resume()
                } label: {
                    Text("继续骑行")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white)
                        .foregroundStyle(Theme.darkBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())

                Button {
                    showEndConfirm = true
                } label: {
                    Text("结束骑行")
                        .font(.system(size: 16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(.white.opacity(0.06))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                }
                .buttonStyle(SolidPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.darkBackground.ignoresSafeArea())
    }

    /// 结束请求涉及轨迹上传、统计重算和徽章发放。网络慢时必须有明确反馈，
    /// 同时用全屏遮罩阻止重复点击“结束骑行”。
    private var endingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .accessibilityHidden(true)
                Text("正在保存骑行记录")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text("请稍候，不要退出 App")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
            .background(Theme.darkCard)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            // 保存期间整块遮罩只作为一个元素，读屏一句话说清状态
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("正在保存骑行记录，请稍候，不要退出 App")
        }
        .zIndex(100)
    }

    private func mapArea(compact: Bool) -> some View {
        Map(position: $camera) {
            if let ride, let lat = ride.lastLat, let lng = ride.lastLng {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                    // 底图固定深色：黑点/黑线落在近黑图上等于没有。当前位置沿用品牌绿，
                    // 与对向页「你的位置」一致。
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let ride, ride.track.count >= 2 {
                // 实际轨迹用纯白实线，和骑行记录详情同一套；
                // 规划路线是白色虚线且压到 55% 不透明度，实线/虚线一眼可分。
                MapPolyline(coordinates: ride.track)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            // 规划路线(打卡点连线，虚线白):即使 GPS 轨迹还没画出来也能看到整条路线
            if routeCoords.count >= 2 {
                MapPolyline(coordinates: routeCoords)
                    .stroke(
                        Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 6])
                    )
            }
            ForEach(checkpoints) { cp in
                if let lat = cp.lat, let lng = cp.lng {
                    // 名称放到图钉上方：MapKit 默认把标题压在坐标下方，
                    // 点位靠近地图下沿时会和「高德地图」标注叠在一起。
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .bottom) {
                        VStack(spacing: 3) {
                            Text(cp.name)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.black.opacity(0.62)))
                            ZStack {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 26, height: 26)
                                Group {
                                    if let glyph = routeCheckpointGlyph(cp, in: checkpoints) {
                                        Text(glyph)
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(Theme.darkBackground)
                                    } else {
                                        Image(systemName: "mappin")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(Theme.darkBackground)
                                    }
                                }
                            }
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 190 : 280)
        // MapKit 把 "Legal / 高德地图" 画在底边 0pt 处，14pt 圆角会把标注下沿切掉；
        // 留 6pt 安全区后标注完整可见，深色底和地图边缘几乎无缝。
        .padding(.bottom, 6)
        .background(Theme.darkBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .overlay(alignment: .topTrailing) {
            Button {
                showMapSwitch = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(.black.opacity(0.52))
                    .clipShape(Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.16), lineWidth: 1)
                    }
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle(scale: 0.94))
            .accessibilityLabel("全屏查看路线")
            .padding(.trailing, 24)
            .padding(.top, 8)
        }
    }

    /// 同路提示：只保留一条轻量信息，不再叠标题/关闭等多层操作
    private var banner: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("路线骑手")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("正在这条路线骑行 \(visibleRidersCount) 位骑手")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("路线骑手，正在这条路线骑行 \(visibleRidersCount) 位")

            Spacer(minLength: 8)

            Button {
                showTeamRiders = true
            } label: {
                // 行内跳转用「文字 + 细箭头」，不再给胶囊底：
                // 同一行已经有 ×，再加一个带底的胶囊就是两种按钮语言
                HStack(spacing: 2) {
                    Text("查看")
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle(pressedOpacity: 0.5))

            Button {
                showBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("关闭路线骑手提示")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(Theme.darkCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    /// 数据面板(Figma 骑行中):白卡 16 圆角 + 大速度 + 里程/时长/平均 + 暂停/结束
    /// 沿途匿名统计：只给聚合数字，不含任何骑手信息
    private func nearbyRidersStrip(_ counts: RiderNearbyCounts) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 12) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.darkMeta)
                if counts.hasDirection {
                    if let behind = counts.behindSameDirection, behind > 0 {
                        nearbyRidersItem("后方同向", behind)
                    }
                    if let oncoming = counts.oncoming, oncoming > 0 {
                        nearbyRidersItem("对向驶来", oncoming)
                    }
                } else {
                    nearbyRidersItem("附近骑手", counts.total)
                }
            }
            Text("仅匿名汇总数字，不可作为会车、避险判断依据")
                .font(.system(size: 11))
                .foregroundColor(Theme.listGray)
        }
        .padding(.top, 14)
        .padding(.horizontal, 24)
    }

    private func nearbyRidersItem(_ label: String, _ value: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.darkMeta)
            Text("\(value)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
        }
    }

    private func statsPanel(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Group {
                if hasArrived {
                    // 状态胶囊已经写了「已到达」，这里只保留一次大字状态 + 一句行动指引，
                    // 不再额外叠一条同样标题的提示卡。
                    VStack(spacing: 8) {
                        Text("已到达")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("请就近安全停车，再结束骑行")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.55))
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(currentSpeedKmh, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: compact ? 62 : 76, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                        Text("km/h")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    // 读数会被拆成「48」「km/h」两段，听不出是时速
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("当前时速 \(Int(currentSpeedKmh.rounded())) 公里每小时")
                }
            }
            .padding(.top, hasArrived ? 24 : (compact ? 12 : 28))
            .padding(.bottom, hasArrived ? 10 : (compact ? 10 : 20))

            MetricRowLayout {
                statCell("里程", value: String(format: "%.1f km", riddenMeters / 1000))
                dividerOnLight
                statCell("时长", value: formatDuration(rideSeconds))
                dividerOnLight
                statCell("均速", value: averageSpeed + " km/h")
            }
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            // 三格按布局顺序会念成「8.2 km、35:38、13.8 km/h、里程、时长、均速」
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "里程 " + String(format: "%.1f", riddenMeters / 1000) + " 公里，"
                    + "时长 \(spokenDuration(rideSeconds))，均速 \(averageSpeed) 公里每小时"
            )

            if !hasArrived {
                tripProgressStrip(compact: compact)
            }

            if hasArrived && !checkpoints.isEmpty {
                checkpointReviewCard
                    .padding(.top, 14)
            }

            if let counts = ride?.nearbyRiders, counts.total > 0 {
                nearbyRidersStrip(counts)
            }

            // 已到达态比骑行态多出打卡卡与提示行：短屏上内容刚好超出面板高度，
            // 溢出的几 pt 会把底部 12pt 内边距顶掉（实测只剩 7.5pt）。
            // 这里让伸缩垫在短屏上完全收起，把安全距离还给按钮。
            Spacer(minLength: compact ? (hasArrived ? 0 : 4) : 12)

            if hasArrived {
                Text(arrivalFooterNote)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, compact ? 8 : 10)
            }

            HStack(spacing: 10) {
                if !hasArrived {
                    Button {
                        if ride?.phase == .riding {
                            ride?.pause()
                        } else if ride?.phase == .paused {
                            ride?.resume()
                        }
                    } label: {
                        Image(systemName: ride?.phase == .paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .semibold))
                            // 骑行中最容易误触的是「结束」：实心白留给暂停/继续，
                            // 结束降为描边次级。和暂停页「继续骑行实心 / 结束描边」保持一致。
                            .foregroundColor(Theme.darkBackground)
                            .frame(width: 52, height: 52)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(SolidPressStyle())
                    .accessibilityLabel(ride?.phase == .paused ? "继续骑行" : "暂停骑行")
                }

                Button {
                    showEndConfirm = true
                } label: {
                    Text("结束骑行")
                        // 已到达时结束是这一页唯一的主行动，必须是实心白；
                        // 骑行中暂停才是主行动，结束保持描边次级。
                        .font(.system(size: 16, weight: hasArrived ? .semibold : .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundColor(hasArrived ? Theme.darkBackground : .white)
                        .background(hasArrived ? Color.white : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            if !hasArrived {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            }
                        }
                }
                .buttonStyle(SolidPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, compact ? 12 : 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var dividerOnLight: some View {
        Rectangle()
            .fill(.white.opacity(0.09))
            .frame(width: 1, height: 34)
            .metricRowFixed()
    }

    private var dividerOnDark: some View {
        Rectangle()
            .fill(.white.opacity(0.09))
            .frame(width: 1, height: 34)
            .metricRowFixed()
    }

    private func pauseStatBlock(_ title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    /// 白卡内统计格
    private func statCell(_ title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var averageSpeed: String {
        let duration = Double(rideSeconds) / 3600
        guard duration > 0 else { return "0.0" }
        let avg = riddenMeters / 1000 / duration
        return String(format: "%.1f", avg)
    }

    private var remainingMeters: Double {
        max(0, Double(route.distanceM) - riddenMeters)
    }

    /// 三格按布局顺序会被念成「剩余里程、预计到达、打卡、4.4 km、21:13、0/2」，
    /// 数值和标签全部错位，必须合成一句
    private var tripProgressAccessibilityLabel: String {
        var parts = [
            "剩余里程 " + String(format: "%.1f", remainingMeters / 1000) + " 公里",
            "预计到达 \(estimatedArrival)"
        ]
        if !checkpoints.isEmpty {
                parts.append("打卡 \(checkedCheckpointCount) 个，共 \(checkpoints.count) 个")
        }
        return parts.joined(separator: "，")
    }


    /// 暂停时也要能判断「继续还是结束」：把剩余里程、预计到达、打卡进度压成一行。
    private var pauseRemainingText: String {
        var parts = ["剩余 " + String(format: "%.1f km", remainingMeters / 1000),
                     "预计到达 \(estimatedArrival)"]
        if !checkpoints.isEmpty {
            parts.append("打卡 \(checkedCheckpointCount)/\(checkpoints.count)")
        }
        return parts.joined(separator: " · ")
    }

    /// 读屏版本：单位念中文，打卡不念成「0/2」。
    private var pauseRemainingAccessibilityLabel: String {
        var parts = ["剩余 " + String(format: "%.1f", remainingMeters / 1000) + " 公里",
                     "预计到达 \(estimatedArrival)"]
        if !checkpoints.isEmpty {
            parts.append("打卡 \(checkedCheckpointCount) 个，共 \(checkpoints.count) 个")
        }
        return parts.joined(separator: "，")
    }

    /// 到达页页脚：打卡没打全时先说清「结束后不再补打卡」，
    /// 只写「会保存本次记录」等于把最重要的信息藏起来。
    private var arrivalFooterNote: String {
        let total = sortedCheckpoints.count
        let done = checkedCheckpointCount
        if total > 0, done < total {
            return "还有 \(total - done) 个打卡点未完成，结束后本次不再补打卡"
        }
        return "结束骑行后会保存本次记录，可在车库查看"
    }

    /// 到达后回看打卡：这趟到底打全了没有，逐个点位给结论
    private var checkpointReviewCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("打卡记录")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 8)
                Text("\(checkedCheckpointCount)/\(sortedCheckpoints.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(checkedCheckpointCount >= sortedCheckpoints.count
                                     ? Theme.success
                                     : .white.opacity(0.55))
            }
            .padding(.top, 12)
            .padding(.bottom, 4)

            ForEach(Array(sortedCheckpoints.enumerated()), id: \.element.id) { index, cp in
                let done = ride?.checkedCheckpointIds.contains(cp.id) ?? false
                HStack(spacing: 10) {
                    // 空心圈在 App 里是「勾选协议」的手势语言，这里只是状态回看，
                    // 换成和「记录详情 · 打卡明细」同一套序号徽章，避免读成可以点。
                    ZStack {
                        Circle().fill(done ? Theme.success : .white.opacity(0.14))
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(done ? Color.white : .white.opacity(0.55))
                    }
                    .frame(width: 20, height: 20)
                    Text(cp.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(done ? 0.9 : 0.6))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(done ? "已打卡" : "未打卡")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(done ? Theme.success : .white.opacity(0.55))
                }
                .frame(height: 42)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(cp.name)，\(done ? "已打卡" : "未打卡")")

                if index < sortedCheckpoints.count - 1 {
                    Rectangle()
                        .fill(.white.opacity(0.07))
                        .frame(height: 1)
                        .padding(.leading, 25)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var sortedCheckpoints: [Checkpoint] {
        checkpoints.sorted { $0.seq < $1.seq }
    }

    private func tripProgressStrip(compact: Bool) -> some View {
        VStack(spacing: 5) {
            // 剩余里程 / 预计到达 / 打卡：三项都是「骑行中现在需要看」的数据，同一行并列。
            // 打卡数此前挂在预计到达下方，会被读成「预计到达 17:35 打卡 0/2」的一整句。
            HStack(alignment: .top, spacing: 12) {
                progressCell("剩余里程", value: String(format: "%.1f km", remainingMeters / 1000), alignment: .leading)
                progressCell("预计到达", value: estimatedArrival, alignment: .center)
                if !checkpoints.isEmpty {
                    progressCell("打卡", value: "\(checkedCheckpointCount)/\(checkpoints.count)", alignment: .trailing)
                }
            }
            .padding(.horizontal, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tripProgressAccessibilityLabel)

            // 已到达后剩余里程恒为 0，估算说明已无意义
            if !hasArrived {
                Text("按当前均速估算，实际以道路与休息情况为准")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }
        }
        .padding(.top, compact ? 8 : 18)
        .padding(.bottom, compact ? 4 : 10)
    }

    /// HUD 底部三栏数据单元：标签在上、数值在下，labels 与数值共用同一套白色层级
    private func progressCell(_ label: String, value: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity,
               alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
    }

    private var checkedCheckpointCount: Int {
        demo ? 0 : (ride?.checkedCheckpointIds.count ?? 0)
    }

    private var estimatedArrival: String {
        guard remainingMeters > 1 else { return "已到达" }
        let averageMps = riddenMeters / Double(max(rideSeconds, 1))
        let secondsLeft: Double
        if averageMps > 1 {
            secondsLeft = remainingMeters / averageMps
        } else {
            let totalMeters = max(Double(route.distanceM), 1)
            let totalSeconds = Double(route.durationMin ?? 0) * 60
            guard totalSeconds > 0 else { return "—" }
            secondsLeft = totalSeconds * remainingMeters / totalMeters
        }
        let now = Date()
        let arrival = now.addingTimeInterval(secondsLeft)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        // 夜骑跨零点时只写 00:55 会被读成「马上就到」，加一个「次日」前缀。
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: arrival)
        ).day ?? 0
        let time = formatter.string(from: arrival)
        switch days {
        case 0: return time
        case 1: return "次日 \(time)"
        default: return "\(days) 天后 \(time)"
        }
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// 读屏用时：「2 小时 8 分 5 秒」。
    private func spokenDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) 小时") }
        if m > 0 { parts.append("\(m) 分") }
        if s > 0 || parts.isEmpty { parts.append("\(s) 秒") }
        return parts.joined(separator: " ")
    }

    /// 出发时上报行程计划(POST /api/trip/plan):仅用于匿名统计，失败静默
    @MainActor
    private func reportTripPlan() async {
        guard TripSession.shared.tripId == nil, let dest = routeCoords.last else { return }
        let here = await OneShotLocationFetcher().fetchLocation()
        let tripId = await TripService.createPlan(
            auth.client,
            destLat: dest.latitude,
            destLon: dest.longitude,
            destName: route.name,
            startLat: here?.coordinate.latitude,
            startLon: here?.coordinate.longitude
        )
        TripSession.shared.tripId = tripId
        if let tripId {
            _ = await TripService.updateStatus(auth.client, tripId: tripId, status: "riding")
        }
    }

    private func loadRiders() async {
        guard let count = await TripService.ridersOnRoute(auth.client, routeId: route.id) else {
            ridersCount = 0
            return
        }
        ridersCount = count
        if ridersCount > 0 && !NotificationHelper.isForeground && NotificationHelper.isEnabled("notifySameway") {
            NotificationHelper.post(
                title: "路线骑手",
                body: "正在这条路线骑行 \(ridersCount) 位骑手，点按查看",
                identifier: "sameway-\(route.id)"
            )
        }
    }

    /// 地图视野缩放到覆盖整条路线(含终点打卡点)
    private func fitCameraToRoute() {
        var coords = routeCoords
        if let ride, let lat = ride.lastLat, let lng = ride.lastLng {
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.8),
            longitudeDelta: max(0.02, (maxLng - minLng) * 1.8)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func finishRide() async {
        guard !isEndingRide else { return }

        guard let ride else {
            let fallback = RideSummary(
                record: nil,
                checkedCheckpointIds: [],
                awardedBadge: nil,
                allCheckpointsDone: false,
                track: [],
                saveWarning: demo ? nil : "本次骑行未能建立记录，轨迹未保存"
            )
            summaryItem = RideSummaryItem(summary: fallback)
            return
        }

        isEndingRide = true
        let result = await ride.end()
        isEndingRide = false
        summaryItem = RideSummaryItem(summary: result)
    }
}

/// 全屏路线地图：地图铺满，信息与切换集中在底部浮层
struct MapSwitchView: View {
    @Environment(\.dismiss) private var dismiss
    let route: Route
    let checkpoints: [Checkpoint]
    let ride: RideService?
    /// 与 HUD 使用同一个里程源；demo 骑行为 nil 时也能显示正确的剩余里程
    var riddenMeters: Double? = nil

    @State private var stateB = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var showExternalChoice = false
    @State private var externalKind: String?
    @State private var mapLauncher = NavChoiceCenter()

    /// 规划路线(打卡点连线):全览地图上也显示完整路线
    private var routeCoords: [CLLocationCoordinate2D] {
        checkpoints
            .sorted { $0.seq < $1.seq }
            .compactMap { cp in
                guard let lat = cp.lat, let lng = cp.lng else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
    }

    var body: some View {
        ZStack {
            Map(position: $camera) {
                if let ride, let lat = ride.lastLat, let lng = ride.lastLng {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let ride, ride.track.count >= 2 {
                    MapPolyline(coordinates: ride.track)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                if routeCoords.count >= 2 {
                    MapPolyline(coordinates: routeCoords)
                        .stroke(
                            Color.white.opacity(0.55),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [8, 6])
                        )
                }
                ForEach(checkpoints) { cp in
                    if let lat = cp.lat, let lng = cp.lng {
                        // 名称放到图钉上方：MapKit 默认把标题压在坐标下方，
                        // 点位靠近地图下沿时会和「高德地图」标注叠在一起。
                        Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .bottom) {
                            VStack(spacing: 3) {
                                Text(cp.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.black.opacity(0.62)))
                                ZStack {
                                    Circle()
                                        .fill(.white)
                                        .frame(width: 26, height: 26)
                                    Group {
                                        if let glyph = routeCheckpointGlyph(cp, in: checkpoints) {
                                            Text(glyph)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundStyle(Theme.darkBackground)
                                        } else {
                                            Image(systemName: "mappin")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(Theme.darkBackground)
                                        }
                                    }
                                }
                                .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.42), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 150)
                .allowsHitTesting(false)

                Spacer()

                LinearGradient(
                    colors: [.clear, .black.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 180)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.62))
                            .clipShape(Circle())
                            .overlay {
                                Circle().stroke(.white.opacity(0.26), lineWidth: 1)
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle(scale: 0.94))
                    .accessibilityLabel("返回")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(route.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("爬升 \(route.elevationM) m · 难度 \(route.difficulty)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("剩余")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.45))
                            Text("\(remainingKm) km")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("剩余 \(remainingKm) 公里")
                    }

                    HStack(spacing: 4) {
                        segmentButton("骑行模式", active: !stateB) {
                            withAnimation(.easeInOut(duration: 0.2)) { stateB = false; externalKind = nil }
                        }
                        segmentButton("外部地图", active: stateB) {
                            showExternalChoice = true
                        }
                    }
                    .padding(4)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                    HStack(spacing: 7) {
                        Circle()
                            .fill(stateB ? Color.white.opacity(0.45) : Theme.success)
                            .frame(width: 6, height: 6)
                        Text(externalStatusText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.52))
                    }
                }
                .padding(16)
                // 0.88 时路网线条仍会隐约透到标题区，压到 0.92 让文字区彻底干净
                .background(Color.black.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 1)
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 22)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { ScreenAppearance.shared.push(.dark) }
        .onDisappear { ScreenAppearance.shared.pop(.dark) }
        .wellwayDialog(
            isPresented: $showExternalChoice,
            title: "选择地图导航",
            message: "将在第三方地图中继续本次骑行；高德内请手动切换摩托车路线。返回 App 后自动继续记录。",
            buttons: [
                WellwayDialogButton(title: "高德地图", role: .primary) { openExternal("amap") },
                WellwayDialogButton(title: "苹果地图", role: .plain) { openExternal("apple") }
            ]
        )
        .task {
            fitCameraToRoute()
            guard ProcessInfo.processInfo.arguments.contains("-mapchoice") else { return }
            try? await Task.sleep(for: .milliseconds(600))
            showExternalChoice = true
        }
        .pageMark(stateB ? 62 : 61)
    }

    private func segmentButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                // 0.62 在 0.08 白的深色分段条上偏虚，提到 0.72 才和选中态形成清晰对比
                .foregroundColor(active ? .black : .white.opacity(0.72))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(active ? Color.white : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(CardPressStyle(scale: 0.97))
    }

    private var remainingKm: String {
        let total = Double(route.distanceM) / 1000
        let ridden = (riddenMeters ?? Double(ride?.distanceM ?? 0)) / 1000
        return String(format: "%.1f", max(0, total - ridden))
    }

    private var externalStatusText: String {
        guard stateB else { return "WellWay 正在记录本次骑行" }
        switch externalKind {
        case "amap": return "高德地图导航中，返回 App 继续记录"
        case "apple": return "苹果地图导航中，返回 App 继续记录"
        default: return "选择地图后继续导航"
        }
    }

    private func openExternal(_ kind: String) {
        let sorted = checkpoints.sorted { $0.seq < $1.seq }
        mapLauncher.route = route
        mapLauncher.startLat = sorted.first?.lat
        mapLauncher.startLng = sorted.first?.lng
        mapLauncher.endLat = sorted.last?.lat
        mapLauncher.endLng = sorted.last?.lng
        mapLauncher.currentLat = ride?.lastLat
        mapLauncher.currentLng = ride?.lastLng
        mapLauncher.lastExternalKind = kind
        externalKind = kind
        stateB = true
        mapLauncher.openExternalMap(kind: kind, toStart: false)
    }

    private func fitCameraToRoute() {
        var coords = routeCoords
        if let ride, let lat = ride.lastLat, let lng = ride.lastLng {
            coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        guard !coords.isEmpty else { return }
        let lats = coords.map(\.latitude)
        let lngs = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.8),
            longitudeDelta: max(0.02, (maxLng - minLng) * 1.8)
        )
        camera = .region(MKCoordinateRegion(center: center, span: span))
    }
}


/// 全屏地图与骑行地图共用：同款白圈图钉无法一眼分出起点和终点，
/// 起点画「起」、终点画「终」，中间打卡点保留图钉；只有一个打卡点时仍用图钉。
private func routeCheckpointGlyph(_ cp: Checkpoint, in checkpoints: [Checkpoint]) -> String? {
    let sorted = checkpoints.sorted { $0.seq < $1.seq }
    guard sorted.count >= 2 else { return nil }
    if cp.id == sorted.first?.id { return "起" }
    if cp.id == sorted.last?.id { return "终" }
    return nil
}
