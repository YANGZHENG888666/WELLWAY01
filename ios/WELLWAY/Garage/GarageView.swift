import SwiftUI
import UIKit

/// 车库：我的车辆 + 选择目的地(Figma「首页PitHouse」135:475,1:1 设计还原)
struct GarageView: View {
    @Environment(AuthManager.self) private var auth
    @State private var garage: GarageService?
    @State private var showAddVehicle = false
    @State private var showDestinations = false
    /// 首页缩略轨迹用的 checkpoint 缓存(与热力轨迹 tab 同源)
    @State private var routeCheckpoints: [Int: [Checkpoint]] = [:]
    /// 每辆车的骑行统计(该车已完成记录聚合)
    @State private var rideStatsByVehicle: [UUID: RideStats] = [:]
    /// 统计是否至少成功加载过一次；首次失败时首页显示未知态，而不是伪造 0
    @State private var rideStatsLoaded = false
    /// 每辆车最近一次已完成骑行(车库首页展示)
    @State private var recentRidesByVehicle: [UUID: RecentRide] = [:]
    /// 「上次骑行」是否已完成首轮加载，用于区分「加载中」与「真的没有记录」
    @State private var recentRidesLoaded = false
    /// 首次拉取车辆完成前显示加载态，避免「还没有车辆」假空态闪现
    @State private var isInitialLoading = true
    var showsBackButton: Bool = false

    var body: some View {
        Group {
            if let garage, !isInitialLoading {
                if garage.vehicles.isEmpty, let message = garage.errorMessage {
                    NetworkErrorView(message: message) {
                        Task { await loadVehicles(garage) }
                    }
                } else {
                    DesignHomeView(
                        garage: garage,
                        onAddVehicle: { showAddVehicle = true },
                        onPickDestination: { showDestinations = true },
                        onRefresh: { await refreshAll() },
                        showsBackButton: showsBackButton,
                        checkpointsByRoute: routeCheckpoints,
                        rideStatsByVehicle: rideStatsByVehicle,
                        rideStatsLoaded: rideStatsLoaded,
                        recentRidesByVehicle: recentRidesByVehicle,
                        recentRidesLoaded: recentRidesLoaded
                    )
                }
            } else {
                GarageSkeletonView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onReceive(NotificationCenter.default.publisher(for: .destinationPickerDone)) { _ in
            showDestinations = false
        }
        .fullScreenCover(isPresented: $showAddVehicle, onDismiss: {
            // 覆盖层完全收起后再通知首页跳到新车，避免切换被 TabView 布局覆盖
            NotificationCenter.default.post(name: .addVehicleFlowDismissed, object: nil)
        }) {
            if let garage {
                AddVehicleFlowView(garage: garage)
            }
        }
        .fullScreenCover(isPresented: $showDestinations) {
            NavigationStack {
                RoutesView(onClose: { showDestinations = false })
            }
        }
        .task {
            let service = garage ?? GarageService(client: auth.client)
            garage = service
            // 目录用于加车，不影响首屏车辆展示：与车辆、路线、统计并行加载，
            // 避免首次安装时等待上千条车型目录而长时间停留在骨架屏。
            async let catalog: Void = service.loadCatalog()
            await loadVehicles(service)
            async let routes: Void = loadRecommendedRoutes()
            async let stats: Void = loadRideStats()
            async let recent: Void = loadRecentRides()
            _ = await (catalog, routes, stats, recent)
        }
        .onAppear {
            // 每次回到首页刷新统计与最近骑行(骑完一次后返回即可见)
            Task { await loadRideStats() }
            Task { await loadRecentRides() }
        }
    }

    /// 首次/重试拉取车辆；完成后结束加载态
    private func loadVehicles(_ service: GarageService) async {
        if let uid = auth.user?.id {
            await service.loadVehicles(userId: uid)
        }
        // 调试入口：-garageskeleton 停在骨架屏，便于比对加载前后是否跳动
        if ProcessInfo.processInfo.arguments.contains("-garageskeleton") {
            try? await Task.sleep(for: .seconds(25))
        }
        isInitialLoading = false
    }

    /// 首页下拉刷新：所有入口并行重载，避免旧车辆/旧骑行记录停留在首屏
    private func refreshAll() async {
        guard let garage else { return }
        async let catalog: Void = garage.loadCatalog(force: true)
        async let vehicles: Void = loadVehicles(garage)
        async let routes: Void = loadRecommendedRoutes()
        async let stats: Void = loadRideStats()
        async let recent: Void = loadRecentRides()
        _ = await (catalog, vehicles, routes, stats, recent)
        // 下拉刷新失败时列表仍是旧数据：给一次轻提示，否则用户会以为「刷新成功但没变化」
        if garage.vehicleRefreshFailed {
            NotificationCenter.default.post(
                name: .showToast,
                object: ToastMessage(text: "网络异常，车辆信息未更新", icon: "exclamationmark.triangle.fill")
            )
        }
    }

    /// 拉取全部已完成骑行记录，按车辆聚合(失败不影响车库主流程)
    private func loadRideStats() async {
        guard let uid = auth.user?.id, let garage else { return }
        if let stats = await garage.loadRideStats(userId: uid) {
            rideStatsByVehicle = stats
            rideStatsLoaded = true
        }
    }

    /// 每辆车各取最近一次已完成骑行(含路线名),填充车库首页。
    /// 首页切换到哪辆车，就显示哪辆车自己的上次骑行。
    private func loadRecentRides() async {
        guard let uid = auth.user?.id, let garage else { return }
        // 下拉刷新时车辆与记录并行加载，这里先确保车辆列表就绪，
        // 否则会在车辆还没回来时静默返回，导致「有骑行次数、上次骑行为空」。
        if garage.vehicles.isEmpty {
            await garage.loadVehicles(userId: uid)
        }
        guard !garage.vehicles.isEmpty else { recentRidesLoaded = true; return }
        do {
            // 一次取回所有车辆的已完成记录，按开始时间倒序后每辆车取第一条。
            // 逐车查询时，任意一条记录解码失败都会让整块「上次骑行」静默变空，
            // 出现「骑行次数 1、上次骑行却为空」的自相矛盾。
            let rows: [RecentRideRow] = try await auth.client
                .from("ride_records")
                .select("id, vehicle_id, route_id, started_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh")
                .eq("user_id", value: uid)
                .eq("status", value: "completed")
                .in("vehicle_id", values: garage.vehicles.map { $0.id.uuidString })
                .order("started_at", ascending: false)
                .execute()
                .value

            var latestByVehicle: [UUID: RecentRideRow] = [:]
            for row in rows {
                guard let vehicleId = row.vehicleId, latestByVehicle[vehicleId] == nil else { continue }
                latestByVehicle[vehicleId] = row
            }

            var routeNames: [Int: String] = [:]
            let routeIds = Set(latestByVehicle.values.compactMap(\.routeId))
            if !routeIds.isEmpty {
                // 只取 id/name 两列(完整 Route 解码要求全部字段，用小行避免失败)
                if let routes: [RouteNameRow] = try? await auth.client
                    .from("routes")
                    .select("id, name")
                    .in("id", values: Array(routeIds))
                    .execute()
                    .value {
                    routeNames = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0.name) })
                }

                // 「上次骑行」的缩略轨迹要用这条路线自己的 checkpoint。之前只缓存了
                // 首页前 6 条路线的点，骑到第 7 条以后就退化成一张地图图标。
                let missing = routeIds.subtracting(routeCheckpoints.keys)
                if !missing.isEmpty,
                   let checkpoints: [Checkpoint] = try? await auth.client
                       .from("checkpoints")
                       .select("id, route_id, name, seq, lat, lng, radius_m")
                       .in("route_id", values: Array(missing))
                       .order("seq")
                       .execute()
                       .value {
                    var grouped = routeCheckpoints
                    for cp in checkpoints {
                        grouped[cp.routeId, default: []].append(cp)
                    }
                    routeCheckpoints = grouped
                }
            }
            recentRidesLoaded = true
            recentRidesByVehicle = latestByVehicle.mapValues { row in
                RecentRide(
                    id: row.id,
                    routeName: row.routeId.flatMap { routeNames[$0] },
                    startedAt: row.startedAt.flatMap { ISO8601DateFormatter.wellwayDate(from: $0) },
                    distanceM: Int(row.distanceM.rounded()),
                    durationS: row.durationS,
                    avgSpeed: row.avgSpeed,
                    maxSpeed: row.maxSpeed,
                    routeId: row.routeId
                )
            }
        } catch {
            // 静默失败，保持上一次数据；仍结束加载态，避免一直停在占位
            if recentRidesByVehicle.isEmpty { recentRidesLoaded = true }
        }
    }

    /// 拉取首页推荐路线(与热力轨迹 tab 相同查询，取前 6 条便于横向滑动)
    private func loadRecommendedRoutes() async {
        do {
            let client = auth.client
            let loaded: [Route] = try await client
                .from("routes")
                .select("id, name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, map_url, cover_image_url, province, city")
                .eq("is_active", value: true)
                .order("id")
                .limit(6)
                .execute()
                .value
            let checkpoints: [Checkpoint] = try await client
                .from("checkpoints")
                .select("id, route_id, name, seq, lat, lng, radius_m")
                .order("seq")
                .execute()
                .value
            var grouped: [Int: [Checkpoint]] = [:]
            let ids = Set(loaded.map(\.id))
            for cp in checkpoints where ids.contains(cp.routeId) {
                grouped[cp.routeId, default: []].append(cp)
            }
            routeCheckpoints = grouped
        } catch {
            // 推荐路线仅作首页增强，失败不影响车库主流程
        }
    }
}

/// 最近骑行行(车库首页)
private struct RecentRideRow: Decodable {
    let id: UUID
    let vehicleId: UUID?
    let routeId: Int?
    let startedAt: String?
    let distanceM: Double
    let durationS: Int?
    let avgSpeed: Double?
    let maxSpeed: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case vehicleId = "vehicle_id"
        case routeId = "route_id"
        case startedAt = "started_at"
        case distanceM = "distance_m"
        case durationS = "duration_s"
        case avgSpeed = "avg_speed_kmh"
        case maxSpeed = "max_speed_kmh"
    }

    var hasRecordedTrack: Bool { distanceM >= 50 }
}

/// 路线名查询用最小行(id + name)
private struct RouteNameRow: Decodable {
    let id: Int
    let name: String
}


/// 车库首屏骨架：和真实首页同构(车辆图 / 名称 / 统计 / 本次出发 / 上次骑行)，
/// 冷启动时不至于只有一片白底加一个转圈
private struct GarageSkeletonView: View {
    private let block = Theme.cardStroke
    /// 与真实首页一致的 20pt 内容边距：骨架屏用 16pt 会在数据到达时左右各跳 4pt
    private let horizontal: CGFloat = 20

    /// 车库首页 ignoresSafeArea 后按真实安全区算标题中心；
    /// 骨架屏沿用同一基线，否则加载中「车库」会压到状态栏上。
    private var headerCenterY: CGFloat {
        let safeTop = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.top ?? 20
        return max(48, safeTop + 9)
    }

    /// 与真实首页完全共用同一组纵向落位常量：骨架和数据同坐标，
    /// 加载完成时任何一块都不会横跳（Pro 与 SE 各有一套紧凑值）。
    private var isCompactHeight: Bool {
        let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.height ?? 800
        return height < 700
    }

    private var bikeCenterY: CGFloat { isCompactHeight ? 150 : 186 }
    private var bikeLayerHeight: CGFloat { isCompactHeight ? 148 : 164 }
    private var metaCenterY: CGFloat { isCompactHeight ? 242 : 285 }
    private var statsCenterY: CGFloat { isCompactHeight ? 288 : 332 }
    private var departHeaderY: CGFloat { isCompactHeight ? 328 : 372 }
    private var bandCenterY: CGFloat { isCompactHeight ? 396 : 450 }
    private var bandHeight: CGFloat { isCompactHeight ? 104 : 116 }
    private var lastHeaderY: CGFloat { isCompactHeight ? 466 : 540 }
    private var lastRowY: CGFloat { isCompactHeight ? 526 : 600 }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                Color.white

                Text("车库")
                    .font(.system(size: 18, weight: .bold))
                    .kerning(0.2)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 160, height: 26, alignment: .leading)
                    .position(x: horizontal + 80, y: headerCenterY)

                Image(systemName: "plus")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textPrimary.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .position(x: width - 28, y: headerCenterY)

                vehiclePlaceholder
                    .frame(width: width - horizontal * 2, height: bikeLayerHeight)
                    .position(x: width / 2, y: bikeCenterY)

                bar(width: 190, height: 24)
                    .position(x: horizontal + 95, y: metaCenterY)

                HStack(spacing: 0) {
                    statPlaceholder
                    Rectangle()
                        .fill(block)
                        .frame(width: 1, height: 34)
                    statPlaceholder
                }
                .frame(width: width - 40, height: 52)
                .position(x: width / 2, y: statsCenterY)

                bar(width: 96, height: 18)
                    .position(x: horizontal + 48, y: departHeaderY)

                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        VStack(spacing: 8) {
                            Circle()
                                .fill(block)
                                .frame(width: 26, height: 26)
                            bar(width: 54, height: 10)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: width, height: bandHeight)
                .background(Theme.lightField)
                .position(x: width / 2, y: bandCenterY)

                bar(width: 84, height: 18)
                    .position(x: horizontal + 42, y: lastHeaderY)

                lastRidePlaceholder
                    .frame(width: width - horizontal * 2, height: 76, alignment: .top)
                    .position(x: width / 2, y: lastRowY)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.white)
        // 底部主行动在真实首页是 safeAreaInset 常驻按钮：骨架缺了这一块，
        // 数据到达时页面底部会突然「长」出一个黑色按钮，落差比内容块更明显。
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(block)
                .frame(height: 52)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
                .wellwayBottomBar()
        }
    }

    /// 车辆图是透明底的产品照，骨架不能整块铺灰：那会读成一张灰色图片卡，
    /// 数据到达时「卡片→车」的跳变很明显。用淡车辆图形加地影暗示正在加载照片。
    private var vehiclePlaceholder: some View {
        ZStack {
            Ellipse()
                .fill(block.opacity(0.8))
                .frame(width: 150, height: 7)
                .offset(y: 46)
            Image(systemName: Theme.vehicleSymbol)
                .font(.system(size: 74, weight: .light))
                .foregroundStyle(Theme.textSecondary.opacity(0.20))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 164)
    }

    /// 与真实首页「上次骑行」加载占位同构：64pt 缩略图 + 两行文字块
    private var lastRidePlaceholder: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.lightField)
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 7) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(block)
                    .frame(width: 120, height: 12)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(block.opacity(0.6))
                    .frame(width: 74, height: 10)
            }
            Spacer(minLength: 8)
        }
    }

    private var statPlaceholder: some View {
        VStack(spacing: 3) {
            bar(width: 44, height: 17)
            bar(width: 60, height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        block
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
