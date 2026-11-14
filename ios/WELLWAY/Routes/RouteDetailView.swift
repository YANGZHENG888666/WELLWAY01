import SwiftUI
import UIKit
import CoreLocation
import MapKit

/// 路线详情：地图主视觉 + 数据卡 + 海拔剖面 + 途经点
/// 统一设计语言：白底、20pt 边距、发丝线分组、无装饰性小字
enum RouteDetailElevationPreview {
    case live
    case slow
    case failed
    case missingCoordinates
}

struct RouteDetailView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(NavChoiceCenter.self) private var navChoice
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    let route: Route
    let checkpoints: [Checkpoint]
    var ridersCount = 0
    var pageNumber = 1
    /// 由 P房「选择目的地」进入时为 true:底部按钮变为「添加到出发页」
    var pickDestinationMode = false
    /// 路线列表已加载的收藏仓库；列表进入详情时必须共用同一实例，
    /// 否则详情点亮星标后，返回列表的「只看收藏」仍读旧内存。
    var favoritesStore: FavoritesStore? = nil
    /// 仅调试入口使用：把海拔卡固定到慢加载 / 失败 / 缺坐标态，便于截图评审。
    var elevationPreview: RouteDetailElevationPreview = .live

    @State private var showRiding = false
    @State private var showFullscreenMap = false
    @State private var checkedCheckpointIds: Set<Int> = []
    @State private var checkinsLoading = true
    @State private var checkinLoadFailed = false
    @State private var hasVehicle = true
    @State private var showNoVehicleGuide = false
    @State private var showArrivedAtStart = false
    @State private var showLocationRequired = false
    @State private var showRouteCoordinatesUnavailable = false
    @State private var showGarage = false
    @State private var defaultVehicle: (id: UUID, name: String)?
    @State private var favorites: FavoritesStore?
    /// 当前路线的匿名在场骑手数：只取聚合数字，不读取任何个人位置或身份
    @State private var activeRiderCount: Int?
    @State private var elevationData: ElevationData?
    @State private var elevationLoading = true
    @State private var elevationFailed = false
    @State private var elevationSlow = false
    /// 路线本身缺少可用的途经点坐标:重试也不会成功,不能再给一个无效的「重试」入口
    @State private var elevationMissingCoordinates = false
    @State private var elevationAttempt = UUID()

    private struct ElevationData {
        let samples: [CGFloat]
        let low: Int
        let high: Int
        /// 真实地形只负责海拔曲线；爬升统一采用后台路线数据，避免列表、详情和骑行地图出现三个口径。
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "路线详情")

            GeometryReader { proxy in
                let contentWidth = max(proxy.size.width - 40, 280)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        hero(width: contentWidth)
                            .padding(.top, 8)
                            .motionAppear(delay: 0.06)

                        titleBlock
                            .padding(.top, 18)
                            .motionAppear(delay: 0.12)

                        statCard
                            .padding(.top, 18)
                            .motionAppear(delay: 0.18)

                        elevationCard
                            .padding(.top, 24)
                            .motionAppear(delay: 0.24)

                        checkpointsSection
                            .padding(.top, 24)
                            .motionAppear(delay: 0.30)

                        Color.clear.frame(height: 88)
                    }
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .pageMark(pageNumber)
        .task {
            if favorites == nil, let favoritesStore {
                favorites = favoritesStore
            } else if favorites == nil, let uid = auth.user?.id {
                let store = FavoritesStore(client: auth.client, userId: uid)
                favorites = store
                await store.load()
            }
            await loadMyCheckins()
            await checkVehicle()
        }
        .task { await loadDefaultVehicle() }
        .task { await loadActiveRiders() }
        .task { await loadElevationProfile() }
        .wellwayDialog(
            isPresented: $showNoVehicleGuide,
            title: "请先添加车辆",
            message: "添加后骑行记录会关联到你的车辆（可跳过）",
            buttons: [
                WellwayDialogButton(title: "去添加车辆", role: .primary) {
                    showGarage = true
                },
                WellwayDialogButton(title: "暂时跳过", role: .plain) {
                    PermissionHelper.requestRidePermissions()
                    presentNavChoice()
                }
            ]
        )
        .wellwayDialog(
            isPresented: $showArrivedAtStart,
            title: "已到达起点附近",
            message: "您已到达\(navChoice.route?.name ?? "该路线")附近，是否需要从路线起点导航到路线终点？",
            buttons: [
                WellwayDialogButton(title: "导航到路线终点", role: .primary) {
                    let kind = navChoice.lastExternalKind ?? "amap"
                    navChoice.openExternalMap(kind: kind, toStart: false)
                    navChoice.onWellway?()
                }
            ],
            onCancel: {
                navChoice.awaitingArrivalAtStart = false
            }
        )
        .wellwayDialog(
            isPresented: $showLocationRequired,
            title: "定位权限未开启",
            message: "WellWay 需要定位来记录骑行轨迹和路线打卡。你仍可以使用高德或苹果地图导航。",
            buttons: [
                WellwayDialogButton(title: "去设置开启", role: .primary) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                },
                WellwayDialogButton(title: "取消", role: .plain) {}
            ]
        )
        .wellwayDialog(
            isPresented: $showRouteCoordinatesUnavailable,
            title: "路线坐标未就绪",
            message: pickDestinationMode
                ? "这条路线缺少起点或终点坐标，暂时无法添加到出发页。请返回刷新路线后再试。"
                : "这条路线缺少起点或终点坐标，暂时无法开始导航。请返回刷新路线后再试。",
            buttons: [WellwayDialogButton(title: "知道了", role: .plain) {}]
        )
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            handleReturnFromExternalNavigation()
        }
        .fullScreenCover(isPresented: $showGarage) {
            NavigationStack {
                GarageView(showsBackButton: true)
            }
        }
        .fullScreenCover(isPresented: $showRiding) {
            RidingView(
                route: route,
                checkpoints: checkpoints,
                vehicleId: defaultVehicle?.id,
                vehicleName: defaultVehicle?.name
            )
        }
        .fullScreenCover(isPresented: $showFullscreenMap) {
            RouteMapFullscreenView(route: route, checkpoints: checkpoints)
        }
    }

    // MARK: - 主视觉

    private func hero(width: CGFloat) -> some View {
        ZStack(alignment: .bottomTrailing) {
            RouteMapAnimationView(isPlaying: true, width: width)
                .onTapGesture { showFullscreenMap = true }

            Button {
                showFullscreenMap = true
            } label: {
                Text("全览")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Capsule())
                    // 视觉胶囊保持 28pt 高，外层补足 44pt 命中区；否则地图上很难点准。
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle(scale: 0.96))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                toggleFavorite()
            } label: {
                Image(systemName: favorites?.isFavorite(route.id) == true ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    // 深色地图上白色实心圆最干净：缩小到 30pt，避免抢掉路线本体的注意力
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.94))
                    .clipShape(Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle(scale: 0.94))
            .accessibilityLabel(favorites?.isFavorite(route.id) == true ? "取消收藏" : "收藏路线")
            .padding(8)
        }
    }

    // MARK: - 标题

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(route.name)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let endpoints = routeEndpoints {
                Text(endpoints)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(0.78))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                // 里程在下方数据卡里已经是大字号主指标，这里再写一遍
                // 等于同一屏把同一个数字看两次；有省市就只写省市。
                if let region = regionText {
                    Text(region)
                } else {
                    Text(String(format: "%.1f km", Double(route.distanceM) / 1000))
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            // 不合成一句会被读成「上海，点，20.0 km」——中间那个分隔点没有语义
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(metaAccessibilityLabel)

            if (activeRiderCount ?? 0) > 0 || ridersCount > 0 {
                NavigationLink {
                    RidersView(route: route, checkpoints: checkpoints)
                } label: {
                    HStack(spacing: 4) {
                        Text(ridersText)
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Theme.successText)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
            }
        }
    }

    private var ridersText: String {
        if let activeRiderCount, activeRiderCount > 0 {
            return "正在这条路线骑行 \(activeRiderCount) 位骑手"
        }
        if ridersCount > 0 {
            return "今天有 \(ridersCount) 位骑手骑行"
        }
        return "今天暂无骑手骑行"
    }

    private var routeEndpoints: String? {
        let start = route.startName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let end = route.endName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !start.isEmpty, !end.isEmpty else { return nil }
        return start == end ? start : "\(start) → \(end)"
    }

    private var regionText: String? {
        let parts = [route.province, route.city].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        guard !parts.isEmpty else { return nil }
        let unique = parts.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        return unique.joined(separator: " · ")
    }

    // MARK: - 数据卡

    private var statCard: some View {
        MetricRowLayout {
            statColumn("里程", value: String(format: "%.1f", Double(route.distanceM) / 1000), unit: "km")
            statDivider
            statColumn("爬升", value: "\(route.elevationM)", unit: "m")
            statDivider
            statColumn("预计用时", value: route.durationMin.map { RideDurationText.parts(minutes: $0).value } ?? "-", unit: route.durationMin.flatMap { RideDurationText.parts(minutes: $0).unit })
            statDivider
            statColumn("难度", value: route.difficulty, unit: nil)
        }
        .frame(height: 72)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        // 四列按布局顺序念出来是「里程、爬升、用时、难度、20.0、km、120、m」，
        // 标签和数值完全错位，必须合成一句
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statCardAccessibilityLabel)
    }

    private var metaAccessibilityLabel: String {
        let distance = String(format: "%.1f 公里", Double(route.distanceM) / 1000)
        return regionText ?? distance
    }

    private var statCardAccessibilityLabel: String {
        var parts = [
            "里程 " + String(format: "%.1f 公里", Double(route.distanceM) / 1000),
            "爬升 \(route.elevationM) 米"
        ]
        if let minutes = route.durationMin {
            let duration = RideDurationText.parts(minutes: minutes)
            let unit = duration.unit ?? ""
            parts.append("预计用时 \(duration.value)\(unit.isEmpty ? "" : " " + unit)")
        }
        parts.append("难度 \(route.difficulty)")
        return parts.joined(separator: "，")
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 34)
            .padding(.horizontal, 12)
            .metricRowFixed()
    }

    private func statColumn(_ label: String, value: String, unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 海拔剖面

    private var elevationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("海拔剖面")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if let elevationData {
                    Text("\(elevationData.low)–\(elevationData.high) m")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let elevationData {
                ElevationProfileView(
                    samples: elevationData.samples,
                    startLabel: "0 km",
                    endLabel: String(format: "%.1f km", Double(route.distanceM) / 1000)
                )
                .frame(height: 104)
            } else if elevationLoading {
                VStack(alignment: .leading, spacing: 10) {
                    ElevationLoadingChart()
                    Text(elevationSlow ? "地形数据读取较慢，仍在计算…" : "正在读取地形数据")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "mountain.2")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("海拔数据暂不可用")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(elevationMissingCoordinates ? "路线缺少途经点坐标" : "不影响路线与打卡信息")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    if !elevationMissingCoordinates {
                        Button("重试") {
                            Task { await loadElevationProfile() }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 16)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 真实海拔数据

    private struct ElevationResponse: Decodable {
        let elevation: [Double]
    }

    private func loadElevationProfile() async {
        guard elevationData == nil else { return }
        switch elevationPreview {
        case .live:
            break
        case .slow:
            elevationLoading = true
            elevationFailed = false
            elevationSlow = true
            elevationMissingCoordinates = false
            return
        case .failed:
            elevationLoading = false
            elevationFailed = true
            elevationSlow = false
            elevationMissingCoordinates = false
            return
        case .missingCoordinates:
            elevationLoading = false
            elevationFailed = true
            elevationSlow = false
            elevationMissingCoordinates = true
            return
        }
        let attempt = UUID()
        elevationAttempt = attempt
        let coordinates = checkpoints
            .sorted { $0.seq < $1.seq }
            .compactMap { checkpoint -> CLLocationCoordinate2D? in
                guard let lat = checkpoint.lat, let lng = checkpoint.lng else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        guard coordinates.count >= 2 else {
            elevationLoading = false
            elevationFailed = true
            elevationMissingCoordinates = true
            return
        }

        elevationLoading = true
        elevationFailed = false
        elevationSlow = false
        elevationMissingCoordinates = false
        scheduleElevationWatchdog(attempt)
        defer {
            if elevationAttempt == attempt {
                elevationLoading = false
                elevationSlow = false
            }
        }

        do {
            // 途经点之间逐段算路再拼接。只算首尾会在地形图上画出与实际路线不符的剖面。
            var routeCoordinates: [CLLocationCoordinate2D] = []
            for index in 0..<(coordinates.count - 1) {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: coordinates[index]))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinates[index + 1]))
                request.transportType = .automobile
                request.requestsAlternateRoutes = false

                let response = try await MKDirections(request: request).calculate()
                guard let directionsRoute = response.routes.first,
                      directionsRoute.polyline.pointCount >= 2 else {
                    throw URLError(.cannotParseResponse)
                }

                let pointCount = directionsRoute.polyline.pointCount
                var segmentCoordinates = [CLLocationCoordinate2D](
                    repeating: coordinates[index],
                    count: pointCount
                )
                directionsRoute.polyline.getCoordinates(
                    &segmentCoordinates,
                    range: NSRange(location: 0, length: pointCount)
                )
                if !routeCoordinates.isEmpty { segmentCoordinates.removeFirst() }
                routeCoordinates.append(contentsOf: segmentCoordinates)
            }

            guard routeCoordinates.count >= 2 else {
                throw URLError(.cannotParseResponse)
            }

            let sampled = sampleCoordinates(routeCoordinates, targetCount: 40)
            let elevations = try await fetchElevations(for: sampled)
            guard elevations.count == sampled.count,
                  let low = elevations.min(),
                  let high = elevations.max() else {
                throw URLError(.cannotParseResponse)
            }

            let span = max(high - low, 1)
            let samples = elevations.map {
                CGFloat(0.12 + ($0 - low) / span * 0.82)
            }
            guard elevationAttempt == attempt else { return }
            elevationData = ElevationData(
                samples: samples,
                low: Int(low.rounded()),
                high: Int(high.rounded())
            )
            elevationFailed = false
            elevationSlow = false
        } catch {
            guard elevationAttempt == attempt else { return }
            elevationFailed = true
            elevationSlow = false
        }
    }

    /// 地图算路可能长时间不返回；先说明正在计算，超过时限后落到可重试状态，
    /// 避免海拔卡一直停在骨架屏。
    private func scheduleElevationWatchdog(_ attempt: UUID) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard elevationAttempt == attempt, elevationLoading, elevationData == nil else { return }
            elevationSlow = true

            try? await Task.sleep(for: .seconds(12))
            guard elevationAttempt == attempt, elevationLoading, elevationData == nil else { return }
            elevationLoading = false
            elevationFailed = true
            elevationSlow = false
        }
    }

    private func sampleCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        targetCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > targetCount, targetCount > 1 else { return coordinates }
        let step = Double(coordinates.count - 1) / Double(targetCount - 1)
        return (0..<targetCount).map { index in
            coordinates[min(Int(round(Double(index) * step)), coordinates.count - 1)]
        }
    }

    private func fetchElevations(
        for coordinates: [CLLocationCoordinate2D]
    ) async throws -> [Double] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation")!
        components.queryItems = [
            URLQueryItem(
                name: "latitude",
                value: coordinates.map { String(format: "%.6f", $0.latitude) }.joined(separator: ",")
            ),
            URLQueryItem(
                name: "longitude",
                value: coordinates.map { String(format: "%.6f", $0.longitude) }.joined(separator: ",")
            ),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse,
           !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(ElevationResponse.self, from: data).elevation
    }

    // MARK: - 途经点

    private var checkpointsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("途经点")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if !checkpoints.isEmpty {
                    if checkinsLoading {
                        Text("打卡状态读取中")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else if checkinLoadFailed {
                        Button("重试") {
                            Task { await loadMyCheckins() }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    } else {
                        Text("\(checkedCheckpointIds.count)/\(checkpoints.count) 已打卡")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel("已打卡 \(checkedCheckpointIds.count) 个，共 \(checkpoints.count) 个")
                    }
                }
            }

            if checkpoints.isEmpty {
                Text("本路线暂无途经点")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(checkpoints.sorted { $0.seq < $1.seq }.enumerated()), id: \.element.id) { index, checkpoint in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                                .padding(.leading, 34)
                        }
                        checkpointRow(checkpoint)
                    }
                }
            }
        }
    }

    private func checkpointRow(_ checkpoint: Checkpoint) -> some View {
        let done = checkedCheckpointIds.contains(checkpoint.id)
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(done ? Theme.textPrimary : Theme.lightField)
                Text("\(checkpoint.seq)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(done ? Color.white : Theme.textSecondary)
            }
            .frame(width: 22, height: 22)

            Text(checkpoint.name.withoutEmoji)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(checkinLoadFailed ? "—" : (done ? "已打卡" : "未打卡"))
                .font(.system(size: 12))
                .foregroundStyle(done ? Theme.successText : Theme.textSecondary)
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 14)
        // 分开念是「1、滨江路起点、已打卡」三个碎片，序号和名称对不上
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "第 \(checkpoint.seq) 个途经点，\(checkpoint.name.withoutEmoji)，"
                + (checkinLoadFailed ? "打卡状态未知" : (done ? "已打卡" : "未打卡"))
        )
    }

    // MARK: - 底部按钮

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                if pickDestinationMode {
                    addToDepart()
                } else {
                    startRide()
                }
            } label: {
                Text(routeCoordinatesUnavailable
                     ? "路线坐标未就绪"
                     : (pickDestinationMode ? "添加到出发页" : "开始骑行"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(routeCoordinatesUnavailable ? Theme.textSecondary : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(routeCoordinatesUnavailable ? Theme.lightField : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .wellwayBottomBar()
    }

    private func addToDepart() {
        guard !routeCoordinatesUnavailable else {
            showRouteCoordinatesUnavailable = true
            return
        }
        Haptics.tap()
        DepartDraft.shared.route = route
        DepartDraft.shared.checkpoints = checkpoints
        NotificationCenter.default.post(name: .departDraftUpdated, object: nil)
        NotificationCenter.default.post(name: .destinationPickerDone, object: nil)
        NotificationCenter.default.post(name: .switchToDepartTab, object: nil)
        dismiss()
    }

    private func startRide() {
        guard !routeCoordinatesUnavailable else {
            showRouteCoordinatesUnavailable = true
            return
        }
        Haptics.tap()
        if hasVehicle {
            PermissionHelper.requestRidePermissions()
            presentNavChoice()
        } else {
            showNoVehicleGuide = true
        }
    }

    private func presentNavChoice() {
        guard !routeCoordinatesUnavailable else {
            showRouteCoordinatesUnavailable = true
            return
        }
        let cps = checkpoints.sorted { $0.seq < $1.seq }
        navChoice.route = route
        navChoice.onWellway = { beginInAppRide() }
        navChoice.startLat = cps.first?.lat
        navChoice.startLng = cps.first?.lng
        navChoice.endLat = cps.last?.lat
        navChoice.endLng = cps.last?.lng
        navChoice.currentLat = nil
        navChoice.currentLng = nil
        Task { await navChoice.fetchCurrentLocation() }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            navChoice.isPresented = true
        }
    }

    /// 导航至少需要起点与终点两枚坐标；缺失时明确拦截，避免进入一条 0 轨迹的骑行。
    private var routeCoordinatesUnavailable: Bool {
        checkpoints.compactMap { checkpoint -> CLLocationCoordinate2D? in
            guard let lat = checkpoint.lat, let lng = checkpoint.lng,
                  lat != 0, lng != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }.count < 2
    }

    private func beginInAppRide() {
        let status = CLLocationManager().authorizationStatus
        guard status != .denied, status != .restricted else {
            showLocationRequired = true
            return
        }
        showRiding = true
    }

    /// 从第三方地图返回：先导航到起点的那次，若已到起点附近则继续引导到终点。
    private func handleReturnFromExternalNavigation() {
        guard navChoice.awaitingArrivalAtStart else { return }
        Task {
            await navChoice.fetchCurrentLocation()
            if let d = navChoice.distanceToStartKm, d <= 0.5 {
                navChoice.awaitingArrivalAtStart = false
                showArrivedAtStart = true
            }
        }
    }

    private func toggleFavorite() {
        Haptics.selection()
        guard let favorites else { return }
        Task { await favorites.toggle(route.id) }
    }

    // MARK: - 数据

    private func loadDefaultVehicle() async {
        guard let uid = auth.user?.id else { return }
        struct VehicleNames: Decodable {
            let id: UUID
            let nickname: String?
            let model: NameRow?
            let brand: NameRow?
            struct NameRow: Decodable {
                let name: String
                let nameEn: String?
                enum CodingKeys: String, CodingKey {
                    case name
                    case nameEn = "name_en"
                }
            }
            enum CodingKeys: String, CodingKey {
                case id, nickname
                case model = "models"
                case brand = "brands"
            }
        }
        do {
            let vehicles: [VehicleNames] = try await auth.client
                .from("vehicles")
                .select("id, nickname, models(name), brands(name, name_en)")
                .eq("user_id", value: uid)
                .order("is_default", ascending: false)
                .limit(1)
                .execute()
                .value
            guard let first = vehicles.first else {
                defaultVehicle = nil
                return
            }
            // 与出发页 / 车库保持一致：品牌(英文优先) + 车型，昵称仅作兜底
            let name = VehicleDisplayName.make(
                brandName: first.brand?.name,
                brandNameEn: first.brand?.nameEn,
                rawModelName: first.model?.name,
                nickname: first.nickname
            )
            defaultVehicle = (first.id, name)
        } catch {
            defaultVehicle = nil
        }
    }

    private func checkVehicle() async {
        guard let uid = auth.user?.id else { return }
        do {
            struct Row: Codable { let id: UUID }
            let rows: [Row] = try await auth.client
                .from("vehicles")
                .select("id")
                .eq("user_id", value: uid)
                .limit(1)
                .execute()
                .value
            hasVehicle = !rows.isEmpty
        } catch {
            hasVehicle = true
        }
    }

    private func loadMyCheckins() async {
        guard let uid = auth.user?.id, !checkpoints.isEmpty else {
            checkinsLoading = false
            return
        }
        checkinsLoading = true
        checkinLoadFailed = false
        let ids = checkpoints.map(\.id)
        do {
            struct Row: Codable {
                let checkpointId: Int
                enum CodingKeys: String, CodingKey {
                    case checkpointId = "checkpoint_id"
                }
            }
            let rows: [Row] = try await auth.client
                .from("ride_checkins")
                .select("checkpoint_id")
                .eq("user_id", value: uid)
                .in("checkpoint_id", values: ids)
                .execute()
                .value
            checkedCheckpointIds = Set(rows.map(\.checkpointId))
            checkinsLoading = false
        } catch {
            checkinLoadFailed = true
            checkinsLoading = false
        }
    }

    private func loadActiveRiders() async {
        activeRiderCount = await TripService.ridersOnRoute(auth.client, routeId: route.id)
    }
}

// MARK: - 海拔剖面图

/// 地形数据加载中的剖面骨架：用一条极淡的山形线替代空白灰块，
/// 让用户明确知道这里将出现图表，而不是内容缺失。
private struct ElevationLoadingChart: View {
    @State private var shimmer: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.lightField)

                Path { path in
                    let points: [CGPoint] = [
                        CGPoint(x: 0, y: h * 0.78),
                        CGPoint(x: w * 0.12, y: h * 0.66),
                        CGPoint(x: w * 0.24, y: h * 0.72),
                        CGPoint(x: w * 0.38, y: h * 0.52),
                        CGPoint(x: w * 0.50, y: h * 0.62),
                        CGPoint(x: w * 0.64, y: h * 0.42),
                        CGPoint(x: w * 0.76, y: h * 0.56),
                        CGPoint(x: w * 0.88, y: h * 0.34),
                        CGPoint(x: w, y: h * 0.50)
                    ]
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    Theme.textPrimary.opacity(0.13),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.55), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w * 0.45)
                .offset(x: w * shimmer)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: reduceMotion) {
                guard !reduceMotion else {
                    shimmer = 0
                    return
                }
                shimmer = -1
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) {
                    shimmer = 1.1
                }
            }
        }
        .frame(height: 72)
        .accessibilityHidden(true)
    }
}

private struct ElevationProfileView: View {
    let samples: [CGFloat]
    let startLabel: String
    let endLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                let size = proxy.size
                let points = normalizedPoints(in: size)
                ZStack(alignment: .bottom) {
                    // 基线网格
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { _ in
                            Rectangle()
                                .fill(Theme.separator.opacity(0.7))
                                .frame(height: 1)
                            Spacer(minLength: 0)
                        }
                    }

                    if points.count > 1 {
                        areaPath(points, in: size)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.14), Color.black.opacity(0.01)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // 最高点先画、曲线后画：标记只在曲线两侧露出，
                        // 不会在陡峭处把线切出一个缺口。
                        if let peak = points.max(by: { $0.y > $1.y }) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .position(peak)
                            Circle()
                                .fill(Color.black)
                                .frame(width: 5, height: 5)
                                .position(peak)
                        }

                        linePath(points)
                            .stroke(Color.black, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    }
                }
            }

            HStack {
                Text(startLabel)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(endLabel)
                    .lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard samples.count > 1, size.width > 0, size.height > 0 else { return [] }
        let step = size.width / CGFloat(samples.count - 1)
        return samples.enumerated().map { index, value in
            CGPoint(
                x: CGFloat(index) * step,
                y: size.height - value * (size.height - 4) - 2
            )
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midX = (previous.x + current.x) / 2
            path.addCurve(
                to: current,
                control1: CGPoint(x: midX, y: previous.y),
                control2: CGPoint(x: midX, y: current.y)
            )
        }
        return path
    }

    private func areaPath(_ points: [CGPoint], in size: CGSize) -> Path {
        var path = linePath(points)
        path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: size.height))
        path.addLine(to: CGPoint(x: points.first?.x ?? 0, y: size.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - 文案清理

extension String {
    /// 后端路线/途经点名称里可能带 emoji,展示前统一剔除(保留数字与普通标点)
    var withoutEmoji: String {
        let scalars = unicodeScalars.filter { scalar in
            switch scalar.value {
            case 0x1F000...0x1FAFF, 0x2600...0x27BF, 0x2B00...0x2BFF, 0xFE0F, 0x200D:
                return false
            default:
                return true
            }
        }
        return String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}
