import SwiftUI
import UIKit
import CoreLocation

/// 首页车辆卡片的骑行统计(总里程/次数/时长),无数据时隐藏
struct RideStats {
    var totalKm: Double = 0
    var rideCount: Int = 0
    var totalSeconds: Int = 0
    var totalMinutes: Int { totalSeconds / 60 }
    var hasData: Bool { rideCount > 0 }
}

/// 最近骑行条目(车库首页展示)
struct RecentRide: Identifiable {
    let id: UUID
    let routeName: String?
    /// 记录页同源的自定义名称；为空时回退到路线名
    var recordName: String? = nil
    let startedAt: Date?
    let distanceM: Int
    var durationS: Int? = nil
    var avgSpeed: Double? = nil
    var maxSpeed: Double? = nil
    /// 所属路线 id:首页据此取 checkpoint 画真实轨迹缩略图
    var routeId: Int? = nil

    var hasRecordedTrack: Bool { distanceM >= 50 }

    var displayName: String {
        let record = recordName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !record.isEmpty { return record }
        let route = routeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return route.isEmpty ? "自由骑行" : route
    }
}

/// 车库首页 v19(375×812 坐标)
///
/// 版式：标题 → 车辆(左右滑动切换) → 车型/总里程 → 三项统计
///      → 「本次出发」数据带(汽油/天气/路况，通栏浅色，无卡片盒)
///      → 「上次骑行」 → 「开始骑行」
///
/// 设计原则：版块标题一律在容器之外，用排版建立层级而不是靠卡片堆叠；
/// 只有存在比例关系的数据(路况)才用图表，其余保持数值 + 图标。
struct DesignHomeView: View {
    let garage: GarageService
    var onAddVehicle: () -> Void
    var onPickDestination: () -> Void
    /// 首页下拉刷新：由车库根视图统一重载车辆、统计、最近骑行和推荐路线
    var onRefresh: (() async -> Void)? = nil
    var showsBackButton: Bool = false
    var checkpointsByRoute: [Int: [Checkpoint]] = [:]
    var rideStatsByVehicle: [UUID: RideStats] = [:]
    /// false 表示统计从未成功加载，此时显示未知态，不能伪装成 0 次骑行
    var rideStatsLoaded: Bool = false
    /// 每辆车的最近一次已完成骑行。必须按车辆隔离，
    /// 避免当前车辆显示另一辆车的记录。
    var recentRidesByVehicle: [UUID: RecentRide] = [:]
    /// false 表示「上次骑行」还没取回来，此时显示占位，避免短暂闪出「还没有骑行记录」
    var recentRidesLoaded: Bool = false

    @Environment(AuthManager.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedRoute: Route?
    @State private var vehicleIndex = 0
    @GestureState private var vehicleDragOffset: CGFloat = 0
    @State private var prevVehicleCount = 0
    @State private var detailVehicle: Vehicle?
    @State private var weather: WeatherSnapshot?
    @State private var fuel: FuelQuote?
    /// 车辆使用的汽油标号：影响首页油价卡展示与柱状图高亮
    @AppStorage("preferredFuelGrade") private var fuelGrade: Int = 95
    @State private var province: String?
    @State private var locationFetcher = OneShotLocationFetcher()
    @State private var showFuelSheet = false
    @State private var showWeatherSheet = false
    @State private var showTrafficSheet = false
    @State private var showRecords = false
    @State private var lastUpdated: Date?
    @State private var didAttemptUpdate = false
    @State private var isRefreshingWeather = false
    @State private var weatherRefreshFailed = false
    @State private var fuelRefreshFailed = false

    // MARK: - 数据

    private var currentVehicle: Vehicle? {
        guard !garage.vehicles.isEmpty else { return nil }
        return garage.vehicles[min(vehicleIndex, garage.vehicles.count - 1)]
    }

    private var currentStats: RideStats {
        guard let vehicle = currentVehicle else { return RideStats() }
        return rideStatsByVehicle[vehicle.id] ?? RideStats()
    }

    /// 品牌展示：优先英文名
    private func brandText(for vehicle: Vehicle) -> String {
        garage.displayBrandName(for: vehicle.brandId)
    }

    /// 车型展示：去掉品牌前缀
    private func modelText(for vehicle: Vehicle) -> String {
        let name = garage.modelName(for: vehicle.modelId)
        let parts = name.split(separator: " ")
        if let first = parts.first.map(String.init) {
            let known = garage.brands.flatMap { [$0.name, $0.nameEn ?? ""] } + ["春风动力", "春风"]
            if known.contains(where: { $0 == first || first.hasPrefix($0) || $0.hasPrefix(first) }) {
                return parts.dropFirst().joined(separator: " ")
            }
        }
        return name
    }

    private var displayName: String {
        guard let vehicle = currentVehicle else { return "" }
        let brand = brandText(for: vehicle)
        let model = modelText(for: vehicle)
        if brand.isEmpty { return model }
        if model.isEmpty { return brand }
        return "\(brand) \(model)"
    }

    /// 同一车型有多辆时给出序号（与「我的车辆」列表同一口径）。
    /// 不加这枚标签，横滑到第三辆 450SR 时标题和第一辆完全相同，看不出切没切。
    private var sameModelOrdinal: Int? {
        guard let vehicle = currentVehicle else { return nil }
        let sameModel = garage.vehicles.filter { $0.modelId == vehicle.modelId }
        guard sameModel.count > 1,
              let index = sameModel.firstIndex(where: { $0.id == vehicle.id }) else { return nil }
        return index + 1
    }

    /// 里程口径与「我的」账号摘要一致：1 km 以上用 km，不足 1 km 用米。
    /// 旧实现从 0.05 km 起就取整，会让 0.4 km 的骑行显示成「总里程 0 km」。
    private var kmParts: (value: String, unit: String) {
        guard rideStatsLoaded else { return ("\u{2014}", "") }
        let km = currentStats.totalKm
        if km >= 1 {
            return (km >= 100 ? String(format: "%.0f", km) : String(format: "%.1f", km), "km")
        }
        let meters = Int((km * 1000).rounded())
        return meters > 0 ? ("\(meters)", "m") : ("0.0", "km")
    }

    /// 骑过但没有一条轨迹记录时，总里程是「未记录」而不是真的 0：
    /// 「0.0 km」和「骑行 5 次」并排会被读成统计算错了。
    private var kmIsUnknown: Bool {
        rideStatsLoaded && currentStats.rideCount > 0 && currentStats.totalKm <= 0
    }

    private var durationParts: (value: String, unit: String) {
        guard rideStatsLoaded else { return ("\u{2014}", "") }
        let seconds = max(0, currentStats.totalSeconds)
        if seconds == 0 { return ("0", "分钟") }
        if seconds < 60 { return ("\(seconds)", "秒") }
        if seconds < 3_600 { return ("\(seconds / 60)", "分钟") }
        let hours = Double(seconds) / 3_600
        return (hours < 10 ? String(format: "%.1f", hours) : String(format: "%.0f", hours), "小时")
    }

    /// 视觉上单位用 km/m，读屏要念中文，否则会被读成字母
    private var kmSpokenText: String {
        guard !kmParts.unit.isEmpty else { return kmParts.value }
        let unit = kmParts.unit == "km" ? "公里" : kmParts.unit == "m" ? "米" : kmParts.unit
        return "\(kmParts.value) \(unit)"
    }

    private var avgSpeedText: String {
        guard rideStatsLoaded else { return "\u{2014}" }
        guard currentStats.totalSeconds > 0, currentStats.totalKm > 0 else { return "—" }
        let hours = Double(currentStats.totalSeconds) / 3_600
        return String(format: "%.1f", currentStats.totalKm / hours)
    }

    private var hasAvgSpeed: Bool {
        rideStatsLoaded && currentStats.totalSeconds > 0 && currentStats.totalKm > 0
    }

    /// 短屏（SE 667pt）首屏只到 483pt：原布局把「上次骑行」整块压在按钮下面，
    /// 用户不知道页面下面还有内容。短屏整体上提 ~74pt，让标题露在首屏边缘。
    private var isCompactHeight: Bool {
        let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.height ?? 800
        return height < 700
    }

    private var bikeCenterY: CGFloat { isCompactHeight ? 150 : 186 }
    private var bikeImageSize: CGSize {
        isCompactHeight ? CGSize(width: 176, height: 112) : CGSize(width: 202, height: 128)
    }
    private var bikeLayerHeight: CGFloat { isCompactHeight ? 148 : 164 }
    private var dotsCenterY: CGFloat { isCompactHeight ? 220 : 263 }
    private var metaCenterY: CGFloat { isCompactHeight ? 242 : 285 }
    private var statsCenterY: CGFloat { isCompactHeight ? 288 : 332 }
    private var departHeaderY: CGFloat { isCompactHeight ? 328 : 372 }
    private var bandCenterY: CGFloat { isCompactHeight ? 396 : 450 }
    private var bandHeight: CGFloat { isCompactHeight ? 104 : 116 }

    /// 「上次骑行」的纵向落位：只有一行内容（无轨迹）时整体下沉到主按钮上方，
    /// 有统计行时保持原有高度，避免无数据状态在页面底部留出一大片空白。
    private var lastRideLayout: (headerY: CGFloat, rowY: CGFloat, rowHeight: CGFloat) {
        if let vehicle = currentVehicle,
           let ride = recentRidesByVehicle[vehicle.id],
           ride.hasRecordedTrack {
            return isCompactHeight ? (466, 526, 134) : (540, 629, 134)
        }
        return isCompactHeight ? (466, 526, 76) : (540, 600, 76)
    }

    private var weatherStyle: WeatherVisuals.Style {
        WeatherVisuals.style(
            for: weather?.current.weatherCode ?? 0,
            isNight: WeatherVisuals.isNightNow()
        )
    }

    private var weatherSymbol: String {
        guard weather != nil else { return "cloud" }
        return weatherStyle.icon.replacingOccurrences(of: ".fill", with: "")
    }

    private var temperatureText: String {
        guard let weather else { return "—" }
        return "\(Int(weather.current.temperature2m.rounded()))°"
    }

    /// 路况：按出发时段做本地预估(0 畅通 / 1 缓行 / 2 拥堵)
    private var trafficLevel: Int {
        let hour = Calendar.current.component(.hour, from: Date())
        if (7...9).contains(hour) || (17...19).contains(hour) { return 2 }
        if (11...13).contains(hour) { return 1 }
        return 0
    }

    /// 不展示虚构的"路况指数"，直接给状态词
    private var trafficText: String {
        switch trafficLevel {
        case 0: return "畅通"
        case 1: return "缓行"
        default: return "拥堵"
        }
    }

    private var trafficProgress: Double {
        switch trafficLevel {
        case 0: return 1.0
        case 1: return 0.62
        default: return 0.38
        }
    }

    private var trafficColor: Color {
        switch trafficLevel {
        case 0: return Color(red: 0x2E / 255, green: 0x9E / 255, blue: 0x6B / 255)
        case 1: return Color(red: 0xD9 / 255, green: 0x94 / 255, blue: 0x00 / 255)
        default: return Color(red: 0xD9 / 255, green: 0x44 / 255, blue: 0x3F / 255)
        }
    }

    private var fuelPrice: Double? {
        switch fuelGrade {
        case 92: return fuel?.p92
        case 98: return fuel?.p98
        default: return fuel?.p95
        }
    }

    private var fuelPrimary: String {
        guard let value = fuelPrice else { return "—" }
        return String(format: "%.2f", value)
    }

    private var fuelLabel: String { "\(fuelGrade)号汽油" }

    /// 当前气温映射到 -5…35℃ 区间，让天气也有直观的圆环进度
    private var weatherProgress: Double {
        guard let weather else { return 0 }
        return min(1, max(0.06, (weather.current.temperature2m + 5) / 40))
    }

    /// 与 DesignPageHeader(compact) 共用同一基线；首页 ignoresSafeArea，
    /// 因此这里直接按真实安全区计算标题中心，避免 iPhone SE 上标题单独偏低。
    private var tabHeaderCenterY: CGFloat {
        let safeTop = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.top ?? 20
        return max(48, safeTop + 9)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                canvas(width: geo.size.width, viewportHeight: geo.size.height)
                    // 主行动已移到 safeAreaInset:画布只需要撑到最后一屏内容,
                    // 不再为按钮预留 70pt 的空白,短屏也不会出现「能滚但没有内容」的死滚动
                    .frame(width: geo.size.width,
                           // 有轨迹时上次骑行卡更高（629+134），固定 740 会在 SE 上裁掉卡片底部
                           // 额外留出一整条底部操作栏的高度：短屏首页首屏会把「上次骑行」压在按钮下面，
                           // 留白保证这段内容始终能滚到按钮上方，而不是被固定栏挡住。
                           height: max(lastRideLayout.rowY + lastRideLayout.rowHeight + 96,
                                       geo.size.height),
                           alignment: .topLeading)
            }
            .refreshable {
                if let onRefresh { await onRefresh() }
                await loadWeather(force: true)
            }
            .background(Color.white)
            // 主行动钉在 Tab 栏之上:短屏(SE)也始终可见,不用滚到底才能出发
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if garage.vehicles.isEmpty {
                    emptyCtaBar
                } else {
                    ctaBar
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.white)
        .navigationDestination(item: $selectedRoute) { route in
            RouteDetailView(
                route: route,
                checkpoints: checkpointsByRoute[route.id] ?? [],
                ridersCount: 0,
                pageNumber: 1,
                pickDestinationMode: true
            )
        }
        .navigationDestination(isPresented: $showRecords) {
            RecordsView()
        }
        .sheet(item: $detailVehicle) { vehicle in
            VehicleDetailSheet(
                garage: garage,
                vehicle: vehicle,
                brandText: brandText(for: vehicle),
                modelText: modelText(for: vehicle),
                onSetDefault: {
                    guard let uid = auth.user?.id else { return false }
                    let ok = await garage.setDefault(id: vehicle.id, userId: uid)
                    if ok {
                        NotificationCenter.default.post(name: .defaultVehicleChanged, object: nil)
                    }
                    return ok
                }
            )
        }
        .sheet(isPresented: $showFuelSheet) {
            FuelPriceSheet(quote: ProcessInfo.processInfo.arguments.contains("-fuelerror") ? nil : fuel, selectedGrade: $fuelGrade) {
                await loadWeather(force: true)
            }
        }
        .sheet(isPresented: $showWeatherSheet) {
            WeatherDetailSheet(weather: ProcessInfo.processInfo.arguments.contains("-weathererror") ? nil : weather, placeName: province) {
                await loadWeather(force: true)
            }
        }
        .sheet(isPresented: $showTrafficSheet) {
            TrafficEstimateSheet(level: trafficLevel, status: trafficText, color: trafficColor)
        }
        .onChange(of: garage.vehicles.count) { _, newCount in
            guard prevVehicleCount > 0 else {
                prevVehicleCount = newCount
                vehicleIndex = 0
                return
            }
            if newCount > 0 {
                vehicleIndex = min(vehicleIndex, newCount - 1)
            }
            prevVehicleCount = newCount
            jumpToJustAddedVehicle()
        }
        .onChange(of: garage.lastAddedVehicleId) { _, _ in
            jumpToJustAddedVehicle()
        }
        .onChange(of: garage.vehicles.isEmpty) { _, isEmpty in
            guard !isEmpty else { return }
            Task { await loadWeather() }
        }
        .task { await loadWeather() }
        .onChange(of: scenePhase) { _, phase in
            // 回前台且数据超过 10 分钟时刷新，避免首页长期显示旧天气/油价
            guard phase == .active,
                  Date().timeIntervalSince(lastUpdated ?? .distantPast) > 600 else { return }
            Task { await loadWeather(force: true) }
        }
        .task {
            // 调试：直接展开对应弹窗，便于逐屏视觉复检
            let args = ProcessInfo.processInfo.arguments
            guard args.contains("-vehicledetail") || args.contains("-fuel")
                    || args.contains("-weathersheet") || args.contains("-trafficsheet") else { return }
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if args.contains("-vehicledetail") {
                detailVehicle = garage.vehicles.first
            } else if args.contains("-weathersheet") {
                showWeatherSheet = true
            } else if args.contains("-trafficsheet") {
                showTrafficSheet = true
            } else {
                showFuelSheet = true
            }
        }
        .pageMark(garage.vehicles.isEmpty ? 22 : 23)
        .onAppear {
            // 添加车辆是全屏覆盖层：关闭后补一次跳转，避免轮播仍停在旧车。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                jumpToJustAddedVehicle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addVehicleFlowDismissed)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                jumpToJustAddedVehicle()
            }
        }
        // 在「我的车辆」里换了照片：首页是另一个 GarageService 实例，必须清缓存重拉
        .onReceive(NotificationCenter.default.publisher(for: .vehiclePhotoChanged)) { note in
            guard let id = note.object as? UUID, let uid = auth.user?.id else { return }
            garage.clearPhotoCache(for: id)
            Task { await garage.loadVehicles(userId: uid) }
        }
    }

    private func jumpToJustAddedVehicle() {
        guard let id = garage.lastAddedVehicleId,
              let index = garage.vehicles.firstIndex(where: { $0.id == id }) else { return }
        vehicleIndex = index
        prevVehicleCount = garage.vehicles.count
        garage.clearLastAddedFlag()
    }

    /// 当前位置天气(和风优先，失败回退 Open-Meteo) + 本省油价
    private func loadWeather(force: Bool = false) async {
        didAttemptUpdate = true
        // 新用户空车库不弹系统定位授权，等有车后再请求
        if CLLocationManager().authorizationStatus == .notDetermined, garage.vehicles.isEmpty {
            return
        }
        guard !isRefreshingWeather else { return }
        let needsWeather = force || weather == nil
        let needsFuel = force || fuel == nil
        guard needsWeather || needsFuel else { return }

        isRefreshingWeather = true
        defer { isRefreshingWeather = false }

        let debugArgs = ProcessInfo.processInfo.arguments
        let simulateWeatherFailure = debugArgs.contains("-weatherrefreshfail")
        let simulateFuelFailure = debugArgs.contains("-fuelrefreshfail")
        var weatherRefreshed = false
        var fuelRefreshed = false
        if let location = await locationFetcher.fetchLocation() {
            // 天气与油价互不依赖：并发请求，避免天气超时把油价一起拖住
            async let weatherSnapshot: WeatherSnapshot? = (needsWeather && !simulateWeatherFailure)
                ? WeatherService.fetchSmart(
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude
                )
                : nil
            if province == nil {
                province = await PlaceNameService.province(for: location)
            }
            if needsFuel {
                if !simulateFuelFailure,
                   let province,
                   let quote = await FuelPriceService.fetch(province: province) {
                    fuel = quote
                    fuelRefreshFailed = false
                    fuelRefreshed = true
                } else {
                    fuelRefreshFailed = true
                }
            }
            if needsWeather {
                if let snapshot = await weatherSnapshot {
                    weather = snapshot
                    weatherRefreshFailed = false
                    weatherRefreshed = true
                } else {
                    weatherRefreshFailed = true
                }
            } else {
                _ = await weatherSnapshot
            }
        } else {
            if needsWeather { weatherRefreshFailed = true }
            if needsFuel { fuelRefreshFailed = true }
        }

        // 只有真正拿到新数据才更新“刚刚更新”，避免部分成功时误报
        if weatherRefreshed || fuelRefreshed {
            lastUpdated = Date()
        }
    }

    // MARK: - Canvas

    private func canvas(width: CGFloat, viewportHeight: CGFloat) -> some View {
        return ZStack(alignment: .topLeading) {
            Color.white
            header(width: width)
            if garage.vehicles.isEmpty {
                emptyLayer(width: width, viewportHeight: viewportHeight)
            } else {
                vehicleLayer(width: width)
                vehicleDots(width: width)
                    .zIndex(2)
            }
        }
    }

    private func header(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Text("车库")
                .font(.system(size: 18, weight: .bold))
                .kerning(0.2)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 160, height: 26, alignment: .leading)
                // 与 DesignPageHeader(compact) 的 20pt 内容边距对齐：
                // 车库标题写 16pt 时，切到路线/对向/我的会看到标题横跳 4pt
                .position(x: 20 + 80, y: tabHeaderCenterY)

            if !garage.vehicles.isEmpty {
                Button(action: onAddVehicle) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel("添加车辆")
                .position(x: width - 28, y: tabHeaderCenterY)
            }
        }
    }

    // MARK: - 空状态

    private func emptyLayer(width: CGFloat, viewportHeight: CGFloat) -> some View {
        // 空车库只放「图标 + 文案」：主按钮交给底部 safeAreaInset 的 CTA 栏，
        // 和已有车辆时的「开始骑行」保持同一位置。按钮跟着文案一起居中，
        // 会停在屏幕中段、下方空出一大块，整页看起来像没排完。
        let top: CGFloat = 96
        let bottom: CGFloat = 31
        let available = max(280, viewportHeight - top - bottom)
        return DesignEmptyState(
            icon: Theme.vehicleSymbol,
            title: "还没有车辆",
            message: "添加你的第一辆车，开始记录骑行"
        )
        .frame(width: width, height: available)
        .position(x: width / 2, y: top + available / 2)
    }

    // MARK: - 车辆指示点

    /// 指示点固定在画布坐标系里，不随车辆图层一起移动；
    /// 车辆图换成不同的透明底图片时也不会被图层的包围盒带着上下漂。
    @ViewBuilder
    private func vehicleDots(width: CGFloat) -> some View {
        if garage.vehicles.count > 1 {
            // 车辆多时收紧点距:车库是长期资产,车辆数会一直涨,
            // 固定 14pt 槽位在 20 辆以上会顶出屏幕
            let compactDots = garage.vehicles.count > 8
            HStack(spacing: compactDots ? 4 : 6) {
                ForEach(garage.vehicles.indices, id: \.self) { index in
                    ZStack {
                        Capsule()
                            .fill(index == vehicleIndex ? Theme.textPrimary : Theme.dotIdle)
                            .frame(width: index == vehicleIndex ? (compactDots ? 14 : 18) : (compactDots ? 4 : 6), height: 6)
                    }
                    .frame(width: compactDots ? 14 : 18, height: 6)
                }
            }
            .position(x: width / 2, y: dotsCenterY)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(vehicleIndex + 1) 辆，共 \(garage.vehicles.count) 辆")
            // 可调节元素没有 value 时系统会补一个 NaN，旁白会念出「nan」；
            // 用当前车名当 value，切车后也能听到换成了哪辆。
            .accessibilityValue(displayName)
            .accessibilityHint("上下轻扫切换车辆")
            // 切车只有横滑手势，旁白用户没法用；给指示点补一个可调节动作
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 1 : -1
                let next = min(max(vehicleIndex + step, 0), garage.vehicles.count - 1)
                guard next != vehicleIndex else { return }
                withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                    vehicleIndex = next
                }
            }
        }

    }

    // MARK: - 车辆

    @ViewBuilder
    private func vehicleLayer(width: CGFloat) -> some View {
        ZStack {
            if let vehicle = currentVehicle {
                bikeImage(for: vehicle)
                    .id(vehicle.id)
                    .transition(.opacity)
            }
        }
        .frame(width: width, height: bikeLayerHeight)
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 18)
                .updating($vehicleDragOffset) { value, state, _ in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    state = value.translation.width
                }
                .onEnded { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.2, abs(dx) > 42 else { return }
                    let next = min(max(vehicleIndex + (dx < 0 ? 1 : -1), 0), garage.vehicles.count - 1)
                    guard next != vehicleIndex else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                        vehicleIndex = next
                    }
                }
        )
        .offset(x: vehicleDragOffset * 0.06)
        .animation(.easeOut(duration: 0.18), value: vehicleIndex)
        .position(x: width / 2, y: bikeCenterY)


        vehicleMetaRow(width: width)
        statsRow(width: width)
        sectionHeader("本次出发", width: width) { liveBadge }
            .position(x: width / 2, y: departHeaderY)
        departureBand(width: width)
        if isCompactHeight {
            // 短屏没有第二屏的预算：标题 + 64pt 记录行会被底部主按钮整条压住，
            // 只剩「上次骑行」四个字悬在按钮上沿，看起来像数据丢了。
            // 短屏改成一行摘要，完整落在本次出发带与主按钮之间。
            compactLastRideRow(width: width)
        } else {
            sectionHeader("上次骑行", width: width) { recordsLink }
                .position(x: width / 2, y: lastRideLayout.headerY)
            lastRideRow(width: width)
        }
    }

    private func bikeImage(for vehicle: Vehicle) -> some View {
        Group {
            if let photo = garage.photos[vehicle.id] {
                TiltBike {
                    // 自选车照是矩形照片，压成透明抠图会像贴纸浮在白色里；
                    // 收 14pt 圆角并给一层很浅的投影，读起来才是一张「车辆照片」。
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 6)
                }
            } else if hasModelImage(for: vehicle) {
                TiltBike {
                    ModelImage(model: garage.model(for: vehicle.modelId), artPadding: 0)
                }
            } else {
                noModelImagePlaceholder
            }
        }
        .frame(width: bikeImageSize.width, height: bikeImageSize.height)
        .contentShape(Rectangle())
        .onTapGesture { detailVehicle = vehicle }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(brandText(for: vehicle)) \(modelText(for: vehicle)) 车辆详情")
        .accessibilityHint("点按查看车辆信息")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { detailVehicle = vehicle }
    }

    /// 车型库有没有可用的官方抠图（库存里确实有 10 款热门车没图）
    private func hasModelImage(for vehicle: Vehicle) -> Bool {
        guard let raw = garage.model(for: vehicle.modelId)?.imageUrl else { return false }
        return !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 没有官方抠图时不要画一台灰车——那会被读成「图没加载出来」。
    /// 直接说明现状，并告诉用户下一步能做什么。
    private var noModelImagePlaceholder: some View {
        VStack(spacing: 8) {
            // motorcycle 是 iOS 18 才有的符号，写死会在 iOS 17 上变成空白
            Image(systemName: Theme.vehicleSymbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            Text("还没有车型图")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("点按添加自己的车照")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func vehicleMetaRow(width: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            HStack(spacing: 6) {
                Text(displayName)
                    .font(.system(size: 17, weight: .bold))
                    .kerning(0.1)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                // 同款多辆时给出序号：横滑到第三辆 450SR 时标题仍是「春风动力 450SR」，
                // 不加序号就分不清现在看的是哪一辆（车辆列表页已有同一枚标签）。
                if let ordinal = sameModelOrdinal {
                    Text("第 \(ordinal) 辆")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Theme.lightField)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .layoutPriority(1)
                }
            }

            Spacer(minLength: 8)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("总里程")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(kmIsUnknown ? "未记录" : kmParts.value)
                    .font(.system(size: 13, weight: kmIsUnknown ? .medium : .semibold).monospacedDigit())
                    .foregroundStyle(kmIsUnknown ? Theme.textSecondary : Theme.textPrimary)
                if !kmParts.unit.isEmpty && !kmIsUnknown {
                    Text(kmParts.unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .frame(width: width - 40, height: 26)
        .position(x: width / 2, y: metaCenterY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName)\(sameModelOrdinal.map { "，第 \($0) 辆" } ?? "")，总里程\(kmIsUnknown ? "未记录" : " \(kmSpokenText)")")
    }

    private func statsRow(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            let countText = rideStatsLoaded ? String(currentStats.rideCount) : "\u{2014}"
            statColumn(value: countText, unit: "", label: "骑行次数")
            dividerV
            statColumn(value: durationParts.value, unit: durationParts.unit, label: "累计时长")
            if hasAvgSpeed {
                dividerV
                statColumn(value: avgSpeedText, unit: "km/h", label: "均速")
            }
        }
        .frame(width: width - 40, height: 52)
        .position(x: width / 2, y: statsCenterY)
        // 三项统计按布局顺序会被念成「5、56、秒、骑行次数」，数字和标签错位；
        // 合成一句读出来才听得懂。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statsAccessibilityLabel)
    }

    private var statsAccessibilityLabel: String {
        guard rideStatsLoaded else { return "骑行统计加载中" }
        var parts = ["骑行 \(currentStats.rideCount) 次"]
        let duration = durationParts
        if !duration.unit.isEmpty {
            parts.append("累计时长 \(duration.value) \(duration.unit)")
        }
        if hasAvgSpeed {
            parts.append("平均时速 \(avgSpeedText) 公里每小时")
        }
        return parts.joined(separator: "，")
    }

    private func statColumn(value: String, unit: String, label: String) -> some View {
        // 暂无数据用灰色小号占位，避免一条粗黑破折号盖过真实数值的层级
        let missing = (value == "\u{2014}")
        return VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: missing ? 15 : 17, weight: missing ? .regular : .bold).monospacedDigit())
                    .foregroundStyle(missing ? Theme.textSecondary : Theme.textPrimary)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(label)
                // 与「本次出发」数据带的说明文字同为 12pt：
                // 同一屏两排标签一边 11 一边 12，会读成两个层级。
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var dividerV: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(width: 1, height: 34)
    }

    // MARK: - 版块标题

    private func sectionHeader<Trailing: View>(
        _ title: String,
        width: CGFloat,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .kerning(0.2)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(width: width - 40, height: 44)
    }

    /// 定位被拒时汽油/天气永远拿不到：这时点状态行应该去系统设置，而不是再刷一次注定失败的请求
    private var locationDeniedForWeather: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .denied || status == .restricted
    }

    private var liveBadge: some View {
        Button {
            // 状态本身就是刷新入口：失败时可直接重试，而不只是打开详情。
            if locationDeniedForWeather {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                return
            }
            guard !isRefreshingWeather else { return }
            Task { await loadWeather(force: true) }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(
                        (locationDeniedForWeather || weatherRefreshFailed || fuelRefreshFailed)
                            ? Theme.danger
                            : (lastUpdated == nil
                                ? Theme.listGray
                                : Theme.success)
                    )
                    .frame(width: 5, height: 5)
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(updatedText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                // 定位被拒时这一行是去系统设置的入口，给个箭头，别让人以为只是状态文字
                if locationDeniedForWeather {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
        .disabled(isRefreshingWeather && !locationDeniedForWeather)
        .accessibilityLabel("天气和油价状态")
        .accessibilityHint(locationDeniedForWeather
                           ? "点按去系统设置开启定位"
                           : (isRefreshingWeather ? "正在刷新" : "点按刷新天气和油价"))
    }

    private var updatedText: String {
        if locationDeniedForWeather { return "定位未开启" }
        if isRefreshingWeather { return "更新中" }
        if weatherRefreshFailed && fuelRefreshFailed { return "刷新失败" }
        if weatherRefreshFailed { return "天气未更新" }
        if fuelRefreshFailed { return "油价未更新" }
        guard let lastUpdated else {
            return didAttemptUpdate ? "待更新" : "更新中"
        }
        let minutes = Int(Date().timeIntervalSince(lastUpdated) / 60)
        if minutes < 1 { return "刚刚更新" }
        if minutes < 60 { return "\(minutes) 分钟前更新" }
        return "\(minutes / 60) 小时前更新"
    }

    private var recordsLink: some View {
        Button { showRecords = true } label: {
            HStack(spacing: 1) {
                Text("查看记录")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
        .accessibilityLabel("查看骑行记录")
    }

    // MARK: - 本次出发

    private func departureBand(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            fuelTile
            dividerV.frame(height: 58)
            metricTile(
                value: temperatureText,
                unit: nil,
                // 三列说明词必须是同一类名词（今日油价 / 天气 / 路况预估）；
                // 之前这里直接写「阴」，读者会把它当成第三个指标的名字，而不是天气状态。
                label: weather == nil ? "天气" : "天气 · \(weatherStyle.text)",
                // 视觉标签用「天气 · 多云」保持三列说明词同构；
                // 读屏不该把状态念两遍，改用只含名词的短名。
                accessibilityName: "天气",
                action: { showWeatherSheet = true },
                accessibilityDetail: weatherAccessibilityDetail
            ) {
                weatherGauge
            }
            dividerV.frame(height: 58)
            metricTile(value: trafficText, unit: nil, label: "路况预估", action: { showTrafficSheet = true }) {
                trafficGauge
            }
        }
        // 与上方统计行共用 20pt 边距，两排三列的竖向分隔线才对得上
        .padding(.horizontal, 20)
        // 底部 24pt 让位：底部按钮栏顶部有 18pt 白色渐隐，说明文字落在渐变里
        // 会被洗成浅灰，看起来像被裁掉一半。
        .padding(.bottom, 24)
        .frame(width: width, height: bandHeight)
        .background(Theme.bandBackground)
        .position(x: width / 2, y: bandCenterY)
    }

    private func metricTile<Chart: View>(
        value: String,
        unit: String?,
        label: String,
        accessibilityName: String? = nil,
        action: @escaping () -> Void,
        accessibilityDetail: String? = nil,
        @ViewBuilder chart: () -> Chart
    ) -> some View {
        let spokenName = accessibilityName ?? label
        return Button(action: action) {
            VStack(spacing: 0) {
                chart()
                    .frame(height: 44)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(value)
                        .font(.system(size: 19, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    if let unit, value != "—" {
                        Text(unit)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.top, 7)
                Text(label)
                    // 浅底上的说明性整句按规范用 12pt：11pt 在白底的
                    // 对比与可读性都不够，深色 HUD 才用 11。
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            // 详情与数值之间必须有停顿：天气瓦片带预警时原来念成
            // 「…空气重污染橙色预警3°」，预警正文和温度黏成一个词。
            .accessibilityLabel("\(spokenName)\(accessibilityDetail.map { "，\($0)" } ?? "")，\(value)\(unit ?? "")")
            .accessibilityHint("查看\(spokenName)详情")
        }
        // 数据块能点开详情，但之前按下没有任何反馈；
        // 与「我的」页账簿行用同一套浅底按压，全站可点区域的手感才一致。
        .buttonStyle(RowPressStyle())
    }

    /// 统一的仪表圆环：起点在顶部，缺口朝下，接近健康类 App 的指标环
    private func metricRing<Content: View>(
        progress: Double,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.hairlineStrong, lineWidth: 4)
            if progress > 0 {
                Circle()
                    .trim(from: 0, to: max(0.08, min(1, progress)))
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            content()
        }
        .frame(width: 44, height: 44)
    }

    /// 油价没有"完成度"可言：三档标号直接列出来，点了就切换，
    /// 弧长既不能表达价格高低，也不该假装是油量。
    private var fuelTile: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach([92, 95, 98], id: \.self) { grade in
                    Button {
                        if fuelGrade == grade {
                            showFuelSheet = true
                        } else {
                            withAnimation(.easeOut(duration: 0.16)) { fuelGrade = grade }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(grade)")
                                .font(.system(size: 12, weight: fuelGrade == grade ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(fuelGrade == grade ? Theme.textPrimary : Theme.textTertiary)
                            // 价格固定居中显示，必须有一条短线把数字和当前标号绑定，
                            // 否则切到 95/98 时数字仍停在中间，像是 95 的价格。
                            Capsule()
                                .fill(fuelGrade == grade ? Theme.textPrimary : Color.clear)
                                .frame(width: 14, height: 2)
                        }
                        // 点击区保持 34x44：三个标号挨得近，太小容易点错
                        .frame(width: 34, height: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                    .accessibilityLabel("\(grade)号汽油")
                    .accessibilityAddTraits(fuelGrade == grade ? [.isButton, .isSelected] : .isButton)
                }
            }
            .frame(height: 44)

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(fuelPrimary)
                    .font(.system(size: 19, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                if fuelPrice != nil {
                    Text("元/L")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 7)

            Text("今日油价")
                // 与同排的「路况预估」「雨」保持一致：同一行三个指标说明不能有两种字号
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        // 三列里另外两块是 Button（已经自带浅底按压），油价这块内嵌三档按钮，
        // 只能用不接管手势的方式补同样的按压底色，否则只有它按下去没反应。
        .tilePressHighlight()
        .onTapGesture { showFuelSheet = true }
        // 三档标号在油价面板里也能选，瓦片本身合成一个按钮即可；
        // 用 .contain 时子按钮进不了读屏焦点链。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日油价，\(fuelLabel)，\(fuelPrimary)元每升")
        .accessibilityHint("查看油价详情")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showFuelSheet = true }
    }

    /// 天气没有"完成度"：温度映射到圆环只是装饰，直接用天气图标
    /// （晴=太阳、阴=云），预警用右上角一个圆点标出。
    private var weatherGauge: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: weatherSymbol)
                .font(.system(size: 27, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            if activeWeatherWarning != nil {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 13, height: 13)
                    .background(weatherWarningColor)
                    .clipShape(Circle())
                    .offset(x: 1, y: 3)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44)
    }

    private var activeWeatherWarning: WeatherWarning? {
        weather?.warnings?.first
    }

    private var weatherWarningColor: Color {
        guard let warning = activeWeatherWarning else { return Theme.textPrimary }
        switch warning.severityColor {
        case "Yellow": return Color(red: 0xE6 / 255, green: 0xA5 / 255, blue: 0x00 / 255)
        case "Orange": return Color(red: 0xF2 / 255, green: 0x7A / 255, blue: 0x00 / 255)
        case "Red", "Black": return Theme.danger
        default: return Color(red: 0x2F / 255, green: 0x6F / 255, blue: 0xD8 / 255)
        }
    }

    private var weatherAccessibilityDetail: String? {
        guard weather != nil else { return nil }
        var parts = [weatherStyle.text]
        if let warning = activeWeatherWarning {
            parts.append("有气象预警：\(warning.title)")
        }
        return parts.joined(separator: "，")
    }

    private var trafficGauge: some View {
        metricRing(progress: trafficProgress, color: trafficColor) {
            Image(systemName: "road.lanes")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(trafficColor)
        }
    }

    // MARK: - 上次骑行

    /// 短屏单行摘要：左「上次骑行」标签 + 路线名，右侧距离/状态 + 箭头。
    /// 与完整版同一去处（打开骑行记录），只是省掉缩略图和三项统计。
    private func compactLastRideRow(width: CGFloat) -> AnyView {
        let ride = currentVehicle.flatMap { recentRidesByVehicle[$0.id] }
        let loaded = recentRidesLoaded
        let title: String = {
            guard let ride else { return loaded ? "这辆车还没有骑行记录" : "载入中" }
            return ride.displayName
        }()
        let distance: String? = {
            guard let ride, ride.hasRecordedTrack else { return nil }
            return String(format: "%.1f km", Double(ride.distanceM) / 1000)
        }()

        return AnyView(Button {
            showRecords = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("上次骑行")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let distance {
                    Text(distance)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                } else if ride != nil, loaded {
                    Text("轨迹未记录")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            .padding(.horizontal, 20)
            .frame(width: width, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("上次骑行，" + title + (distance.map { "，" + $0 } ?? ""))
        .accessibilityHint("打开骑行记录")
        .position(x: width / 2, y: 474))
    }

    private func lastRideRow(width: CGFloat) -> AnyView {
        let ride = currentVehicle.flatMap { recentRidesByVehicle[$0.id] }
        let distance = ride.map { Double($0.distanceM) / 1000 } ?? currentStats.totalKm
        let seconds = ride?.durationS ?? (ride == nil ? currentStats.totalSeconds : nil)
        let hasTrack = ride?.hasRecordedTrack ?? false

        if ride == nil && !recentRidesLoaded {
            return AnyView(
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Theme.lightField)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 7) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.hairline)
                                .frame(width: 120, height: 12)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.hairline.opacity(0.6))
                                .frame(width: 74, height: 10)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 20)
                }
                .frame(width: width, height: lastRideLayout.rowHeight, alignment: .top)
                .position(x: width / 2, y: lastRideLayout.rowY)
                .accessibilityLabel("正在载入上次骑行")
            )
        }

        // 这一行看起来就是可点的一条记录，但之前只有右上角「查看记录」能点，
        // 用户点正文没有任何反馈。整行跳到记录列表，与右上角同一去处。
        return AnyView(Button {
            showRecords = true
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    routeThumb(ride)
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(ride?.displayName ?? "这辆车还没有骑行记录")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Text(lastRideSubtitle(ride, seconds: seconds))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if ride != nil {
                        if hasTrack {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", distance))
                                    .font(.system(size: 25, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                                Text("km")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        } else {
                            Text("轨迹未记录")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lastRideAccessibilityLabel(ride, seconds: seconds))

                // 没有轨迹时极速/均速必然为空，只剩「时长」一项会像被漏掉的残块；
                // 这种情况把时长并回副标题，统计行整段不出现。
                if ride != nil, hasTrack {
                    Rectangle()
                        .fill(Theme.hairline)
                        .frame(height: 1)
                        .padding(.top, 12)

                    HStack(spacing: 0) {
                        lastStat("时长", durationCompact(seconds))
                        // 没有轨迹时极速/均速必然为空，两个破折号只会制造噪音
                        if hasTrack {
                            dividerV
                            lastStat("极速", (ride?.maxSpeed).flatMap { $0 > 0 ? String(format: "%.0f km/h", $0) : nil } ?? "—")
                            dividerV
                            lastStat("均速", (ride?.avgSpeed).flatMap { $0 > 0 ? String(format: "%.1f km/h", $0) : nil } ?? "—")
                        }
                    }
                    .padding(.top, 11)
                }
            }
            .padding(.horizontal, 20)
            // 头部 64 + 分隔线 + 三项统计约需 127pt，122 会把统计行裁掉
            .frame(width: width, height: lastRideLayout.rowHeight, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("打开骑行记录")
        .position(x: width / 2, y: lastRideLayout.rowY))
    }

    private func lastStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func routeThumb(_ ride: RecentRide?) -> some View {
        // 有真实轨迹时画实线；没有轨迹时用浅灰虚线画路线形状，并由右侧
        // 「轨迹未记录」明确说明状态，避免只剩一个灰色地图占位图标。
        let hasTrack = ride?.hasRecordedTrack ?? false
        let points = thumbPoints(for: ride)
        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Theme.lightField)

            if points.count >= 2 {
                MiniRouteThumb(
                    points: points,
                    tint: hasTrack ? Theme.routeSignal : Theme.textTertiary.opacity(0.85),
                    dashed: !hasTrack
                )
            } else {
                Image(systemName: "map")
                    .font(.system(size: 19, weight: .light))
                    .foregroundStyle(Theme.textTertiary.opacity(0.85))
            }
        }
    }

    /// 把 checkpoint 经纬度归一化成 0…1 的缩略图坐标(取不到就返回空)
    private func thumbPoints(for ride: RecentRide?) -> [CGPoint] {
        guard let routeId = ride?.routeId,
              let list = checkpointsByRoute[routeId] else { return [] }
        let coords = list
            .sorted { $0.seq < $1.seq }
            .compactMap { checkpoint -> (Double, Double)? in
                guard let lat = checkpoint.lat, let lng = checkpoint.lng else { return nil }
                return (lat, lng)
            }
        guard coords.count >= 2 else { return [] }
        let lats = coords.map { $0.0 }
        let lngs = coords.map { $0.1 }
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return [] }
        let spanLat = max(maxLat - minLat, 1e-6)
        let spanLng = max(maxLng - minLng, 1e-6)
        return coords.map { coord in
            CGPoint(
                x: (coord.1 - minLng) / spanLng,
                y: 1 - (coord.0 - minLat) / spanLat
            )
        }
    }

    // MARK: - CTA

    /// 底部主行动(常驻在 Tab 栏上方)
    private var ctaBar: some View {
        primaryBar(title: "开始骑行", action: onPickDestination)
    }

    /// 空车库的主行动：位置、尺寸、渐变全部与「开始骑行」一致，
    /// 用户添完车后按钮不会跳位置。
    private var emptyCtaBar: some View {
        primaryBar(title: "添加车辆", action: onAddVehicle)
    }

    private func primaryBar(title: String, action: @escaping () -> Void) -> some View {
        // 开始骑行 / 添加车辆是首页唯一的重动作，点下去要有实体反馈
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .kerning(1.2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Theme.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .padding(.horizontal, 20)
        .padding(.top, 8)
        // 与悬浮 Tab 栏之间留出呼吸位:iOS 26 的玻璃 Tab 栏从安全区底部开始,
        // 10pt 会让按钮几乎贴上去
        .padding(.bottom, 20)
        // 小屏(SE)上「本次出发」卡片会正好切在按钮栏上沿:没有渐变就像被裁坏,
        // 统一走 wellwayBottomBar(),和出发页 / 路线详情 / 骑行总结保持一致。
        .wellwayBottomBar()
    }

    /// 上次骑行副标题：有轨迹时只放时间；无轨迹时把时长并入，避免统计行只剩一项
    private func lastRideSubtitle(_ ride: RecentRide?, seconds: Int?) -> String {
        guard ride != nil else { return "完成一次骑行后会出现在这里" }
        var parts = [dateText(ride?.startedAt)]
        if !(ride?.hasRecordedTrack ?? false), let seconds, seconds > 0 {
            parts.append("时长 \(durationCompact(seconds))")
        }
        return parts.joined(separator: " · ")
    }

    private func dateText(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "M月d日 HH:mm"
            : "yyyy年M月d日"
        return formatter.string(from: date)
    }

    /// 上次骑行整行读屏：有轨迹时三项统计都要念到，没轨迹时说清缺轨迹；
    /// 屏幕上的「·」在语音里只是停顿，这里统一用逗号。
    private func lastRideAccessibilityLabel(_ ride: RecentRide?, seconds: Int?) -> String {
        guard let ride else { return "这辆车还没有骑行记录" }
        var parts = [ride.displayName, dateText(ride.startedAt)]
        if let seconds, seconds > 0 {
            parts.append("时长 \(durationCompact(seconds))")
        }
        if ride.hasRecordedTrack {
            if let max = ride.maxSpeed, max > 0 {
                parts.append("极速 \(Int(max.rounded())) 公里每小时")
            }
            if let avg = ride.avgSpeed, avg > 0 {
                parts.append("均速 \(String(format: "%.1f", avg)) 公里每小时")
            }
        } else {
            parts.append("轨迹未记录")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "，")
    }

    /// 秒 → 紧凑中文时长(18 秒 / 42 分钟 / 1 小时 08 分)
    private func durationCompact(_ seconds: Int?) -> String {
        guard let seconds else { return "—" }
        return RideDurationText.words(seconds: seconds)
    }
}

// MARK: - 车辆主视觉（灯光跟随）

/// 灯带的光跟着手机走：车随手倾斜轻微位移，投影朝反方向拉开，
/// 一条很淡的高光带扫过车身。陀螺仪状态关在这个小视图里，
/// 30Hz 的刷新不会带着整个车库页重算。
private struct TiltBike<Content: View>: View {
    @ViewBuilder var content: () -> Content
    @State private var tilt = TiltLight()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 减弱动态效果开启时仍保留静态灯带和阴影，但不读取陀螺仪。
    private var lightX: CGFloat { reduceMotion ? 0 : tilt.x }
    private var lightY: CGFloat { reduceMotion ? 0 : tilt.y }

    var body: some View {
        ZStack {
            content()

            content()
                .mask {
                    GeometryReader { geo in
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0), location: 0),
                                .init(color: .white.opacity(0.30), location: 0.5),
                                .init(color: .white.opacity(0), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: geo.size.width * 0.34)
                        .rotationEffect(.degrees(12))
                        .offset(x: (geo.size.width - geo.size.width * 0.34) * (0.5 + lightX * 0.85))
                    }
                }
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
        }
        .offset(x: lightX * 3, y: lightY * 1.5)
        .shadow(
            color: .black.opacity(0.10 + Double(abs(lightY)) * 0.05),
            radius: 7 + lightY * 2,
            x: lightX * 10,
            y: 5 - lightY * 2
        )
        .animation(.easeOut(duration: 0.18), value: lightX)
        .animation(.easeOut(duration: 0.18), value: lightY)
        .task(id: reduceMotion) {
            if reduceMotion {
                tilt.stop()
            } else {
                tilt.start()
            }
        }
        .onDisappear { tilt.stop() }
    }
}

// MARK: - 上次骑行缩略轨迹

/// 用真实 checkpoint 画一条极简轨迹(不画假街区)
private struct MiniRouteThumb: View {
    let points: [CGPoint]
    let tint: Color
    var dashed = false

    var body: some View {
        GeometryReader { geo in
            let inset: CGFloat = 10
            let width = max(geo.size.width - inset * 2, 1)
            let height = max(geo.size.height - inset * 2, 1)

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: resolve(first, inset: inset, width: width, height: height))
                    for point in points.dropFirst() {
                        path.addLine(to: resolve(point, inset: inset, width: width, height: height))
                    }
                }
                .stroke(
                    tint,
                    style: StrokeStyle(
                        lineWidth: dashed ? 1.6 : 2.4,
                        lineCap: .round,
                        lineJoin: .round,
                        dash: dashed ? [3, 3] : []
                    )
                )

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    if index == 0 || index == points.count - 1 {
                        Circle()
                            .fill(.white)
                            .frame(width: 9, height: 9)
                            .overlay(
                                Circle()
                                    .fill(index == 0 || dashed ? tint : Color.black)
                                    .frame(width: 5.5, height: 5.5)
                            )
                            .position(resolve(point, inset: inset, width: width, height: height))
                    }
                }
            }
        }
    }

    private func resolve(_ point: CGPoint, inset: CGFloat, width: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: inset + point.x * width, y: inset + point.y * height)
    }
}

// MARK: - 油价明细

private struct FuelPriceSheet: View {
    let quote: FuelQuote?
    @Binding var selectedGrade: Int
    let onRetry: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isRetrying = false

    private var rows: [(grade: Int, label: String, price: String)] {
        [
            (92, "92号", quote?.p92),
            (95, "95号", quote?.p95),
            (98, "98号", quote?.p98),
        ].map { grade, label, price in
            (grade, label, price.map { String(format: "%.2f", $0) } ?? "—")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text("本地油价")
                    // 与路况预估/天气/车辆详情同一档 22pt 粗体：
                    // 同页三个底部面板的标题原来一个是 22、两个是 17，放在一起明显不齐。
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel("关闭")
            }
            .padding(.bottom, 4)

            if let quote {
                Text(quote.province)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 14)

                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    Button {
                        selectedGrade = row.grade
                        dismiss()
                    } label: {
                        HStack {
                            Text(row.label)
                                .font(.system(size: 15, weight: selectedGrade == row.grade ? .semibold : .medium))
                            Spacer()
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(row.price)
                                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                Text("元/L")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .opacity(selectedGrade == row.grade ? 1 : 0)
                                .padding(.leading, 10)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(RowPressStyle())
                    .accessibilityHint("设为常用汽油标号")
                    if index < rows.count - 1 {
                        Divider()
                    }
                }

                // 原来是一整句，12pt 下正好在「当日挂牌价」后断开，末行只剩一个「为准」，
                // 读起来像被裁掉。拆成两条各自成行：一句说明点击行为，一句说明数据口径。
                VStack(alignment: .leading, spacing: 3) {
                    Text("点击标号即设为首页展示的油价")
                    Text("省级参考价，实际以加油站挂牌价为准")
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                // 面板高度按内容实测，布局压缩时这两行会被挤到一行并省略号收尾，
                // 固定成完整多行才能量到真实高度。
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "fuelpump")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Theme.textSecondary)
                    Text("暂无法获取本地油价")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    if let onRetry {
                        Button {
                            guard !isRetrying else { return }
                            Task {
                                isRetrying = true
                                await onRetry()
                                isRetrying = false
                            }
                        } label: {
                            HStack(spacing: 7) {
                                if isRetrying {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                }
                                Text(isRetrying ? "正在获取" : "重新获取")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(SolidPressStyle())
                        .disabled(isRetrying)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        // sheet 高度大于内容时，系统会把整块 VStack 垂直居中：失败态只剩一行按钮时，
        // 标题会离拖拽条过远。固定顶对齐，让正常态和失败态共用同一个页头位置。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        // 实测内容约 293pt；iOS 26 的 sheet 会在 detent 之外再补安全区，
        // 用实测值反而把空白叠在底部。300 能让「92/95/98 + 说明」完整露出。
        // SE 更窄，底部说明会折成三行，300 时最后一行压在圆角上，补到 335。
        // 失败态只有「图标 + 一句说明 + 重试」约 204pt 高，原来的 260 会在按钮下面
        // 留出近一个按钮高度的空白；260 是照着带说明的正常态定的，失败态用不上。
        .presentationDetents([.height(quote == nil ? 210 : (UIScreen.main.bounds.height >= 700 ? 300 : 335))])
        .presentationCornerRadius(24)
        .presentationBackground(Color.white)
        .presentationDragIndicator(.visible)
    }
}

// MARK: - 天气详情(本次出发)

private struct WeatherDetailSheet: View {
    let weather: WeatherSnapshot?
    var placeName: String? = nil
    let onRetry: (() async -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isRetrying = false
    @State private var isWarningExpanded = false

    private var style: WeatherVisuals.Style {
        WeatherVisuals.style(
            for: weather?.current.weatherCode ?? 3,
            isNight: WeatherVisuals.isNightNow()
        )
    }

    private var condition: String {
        weather?.placeText ?? style.text
    }

    private var hourly: [HourlyForecast] {
        Array((weather?.hourly ?? []).prefix(12))
    }

    private var sheetHeight: CGFloat {
        guard weather != nil else { return 240 }
        // 336 装不下「当前天气 + 三项指标 + 逐小时 + 数据来源」整块：
        // SE 上数据来源那行会贴着屏幕底边，还差 30pt 才能滚到底。
        // iOS 26 的 sheet 会在 detent 之外再补安全区，实测高度会把空白留在底部。
        // SE 的可用宽度更窄，逐小时和来源行需要 380pt 才能一次看全；Pro 330pt 足够。
        let tall = UIScreen.main.bounds.height >= 700
        // SE 更窄，来源说明会折成两行，380 时最后一行正好压在圆角边上，
        // 看起来像被裁掉；415 才能让「数据来源」整行落在白色区域内。
        var height: CGFloat = hourly.isEmpty ? 230 : (tall ? 330 : 415)
        if weather?.warnings?.first != nil { height += 86 }
        return min(height, 560)
    }

    private var sourceLabel: String {
        switch weather?.source {
        case "qweather": return "和风天气"
        case "open-meteo": return "Open-Meteo"
        default: return "公开天气数据"
        }
    }

    private var locationDenied: Bool {
        let status = CLLocationManager().authorizationStatus
        return status == .denied || status == .restricted
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text(placeName.map { "\($0) · 天气" } ?? "天气")
                // 与同页油价/路况面板统一 22pt 粗体
                .font(.system(size: 22, weight: .bold))
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("关闭")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let weather {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 16) {
                            Image(systemName: style.icon)
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(style.tint)
                                .frame(width: 48, height: 48)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(Int(weather.current.temperature2m.rounded()))°")
                                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                                Text(condition)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer(minLength: 0)

                            VStack(alignment: .trailing, spacing: 5) {
                                Text("体感 \(Int(weather.current.apparentTemperature.rounded()))°")
                                Text("湿度 \(Int(weather.current.relativeHumidity2m.rounded()))%")
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.top, 4)

                        HStack(spacing: 0) {
                            weatherDetailItem(
                                title: "风速",
                                value: String(format: "%.1f km/h", weather.current.windSpeed10m)
                            )
                            Divider().frame(height: 28)
                            weatherDetailItem(
                                title: "风向",
                                value: WeatherVisuals.windDirection(weather.current.windDirection10m)
                            )
                            Divider().frame(height: 28)
                            // 「骑行｜谨慎骑行」把同一个词写了两遍；
                            // 指标名已经限定语境，值只留判定词（与出发页紧凑行一致）。
                            weatherDetailItem(
                                title: "骑行",
                                value: Suitability.shortLabel(Suitability.score(weather))
                            )
                        }

                        if let warning = weather.warnings?.first {
                            Button {
                                guard !warning.text.isEmpty else { return }
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isWarningExpanded.toggle()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("气象预警")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color(red: 0.78, green: 0.3, blue: 0.26))
                                    Text(warning.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    if !warning.text.isEmpty {
                                        Text(warning.text)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.textSecondary)
                                            .lineSpacing(2)
                                            .lineLimit(isWarningExpanded ? nil : 3)
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: 3) {
                                            Text(isWarningExpanded ? "收起" : "查看全文")
                                            Image(systemName: isWarningExpanded ? "chevron.up" : "chevron.down")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Color(red: 0.78, green: 0.3, blue: 0.26))
                                        .padding(.top, 2)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(CardPressStyle(scale: 0.98))
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(red: 0.78, green: 0.3, blue: 0.26).opacity(0.06))
                            )
                        }

                        if !hourly.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                // 不再写「左右滑动」：能在同屏看到的小时数已经说明了
                                // 后面还有内容，右缘渐隐负责把「可以滑」表达出来。
                                Text("未来 \(hourly.count) 小时")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 0) {
                                        ForEach(hourly) { hour in
                                            let hourStyle = WeatherVisuals.style(
                                                for: hour.openMeteoCode,
                                                isNight: WeatherVisuals.isNight(iso: hour.time)
                                            )
                                            VStack(spacing: 7) {
                                                Text(hourLabel(hour.time))
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(Theme.textSecondary)
                                                Image(systemName: hourStyle.icon)
                                                    .font(.system(size: 18, weight: .light))
                                                    .foregroundStyle(hourStyle.tint)
                                                    .frame(height: 24)
                                                Text("\(Int(hour.temp.rounded()))°")
                                                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                                                // 每个小时都挂一个「0%」既啰嗦又看不出是降水概率：
                                                // 只在有降水时显示，并补一枚小雨滴；空列保留等高，避免整行错位。
                                                HStack(spacing: 1) {
                                                    if let pop = hour.pop, pop > 0 {
                                                        Image(systemName: "drop.fill")
                                                            .font(.system(size: 8))
                                                        Text("\(pop)%")
                                                            .font(.system(size: 11))
                                                    }
                                                }
                                                .foregroundStyle(Theme.textSecondary)
                                                .frame(height: 14)
                                            }
                                            // 略窄于 1/6 屏宽，右侧露出下一条，提示可以横滑
                                            .frame(width: 54)
                                        }
                                    }
                                }
                                // 与骑行中/出发页的小时条一致：右缘 24pt 渐隐代替文字提示
                                .overlay(alignment: .trailing) {
                                    LinearGradient(
                                        colors: [Color.white.opacity(0), Color.white],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: 24)
                                    .allowsHitTesting(false)
                                }
                            }
                        }

                        Text("数据来源：\(sourceLabel) · 天气存在变化，出行前请以官方预报为准")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 2)
                    }
                    .padding(.bottom, 24)
                }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "cloud")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(Theme.textSecondary)
                    Text(locationDenied ? "定位权限未开启" : "暂时无法获取天气")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    if locationDenied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        } label: {
                            Text("去设置开启定位")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(SolidPressStyle())
                    } else if let onRetry {
                        Button {
                            guard !isRetrying else { return }
                            Task {
                                isRetrying = true
                                await onRetry()
                                isRetrying = false
                            }
                        } label: {
                            HStack(spacing: 7) {
                                if isRetrying {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                }
                                Text(isRetrying ? "正在获取" : "重新获取")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(SolidPressStyle())
                        .disabled(isRetrying)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .background(Color.white)
        .presentationDetents([.height(sheetHeight)])
        .presentationCornerRadius(24)
        .presentationBackground(Color.white)
        .presentationDragIndicator(.visible)
    }

    private func weatherDetailItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hourLabel(_ raw: String) -> String {
        guard let tIndex = raw.firstIndex(of: "T") else { return raw }
        let afterT = raw[raw.index(after: tIndex)...]
        return String(afterT.prefix(2)) + "时"
    }
}

// MARK: - 路况预估(本次出发)

private struct TrafficEstimateSheet: View {
    let level: Int
    let status: String
    let color: Color
    @Environment(\.dismiss) private var dismiss

    private var progress: Double {
        switch level {
        case 0: return 1.0
        case 1: return 0.62
        default: return 0.38
        }
    }

    private var advice: String {
        switch level {
        case 0: return "当前时段整体畅通，适合出发。"
        case 1: return "车流开始增加，建议避开主干道并预留更多通行时间。"
        default: return "正值常见高峰，建议错峰出发，注意路口与会车安全。"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("路况预估")
                    // 与同页天气/油价/车辆照片弹窗同一档 22pt 粗体：
                    // 17pt 的标题在同一组底部面板里明显偏小。
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel("关闭")
            }

            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color(red: 0.91, green: 0.93, blue: 0.95), lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    // 畅通时 progress = 1，圆环是一个完整空圈，看起来像没加载出来；
                    // 首页通栏用的是「圆环 + 道路图标」，弹窗里补上同一个图标。
                    Image(systemName: "road.lanes")
                        .font(.system(size: 18))
                        .foregroundStyle(color)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status)
                        .font(.system(size: 24, weight: .semibold))
                        // 圆环与车图标可以用亮色，文字不信：亮绿 #33C759 落在白底
                        // 只有约 1.9:1，24pt 也难读；正文改用同色系的深一档。
                        .foregroundStyle(Congestion.summaryColor(level))
                    Text("按当前时段估算")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 20)

            trafficRow("常见高峰", "07:00–09:00 · 17:00–19:00")
            Divider()
            // 两行的值必须同构：一行是时段、另一行是「时段 + 判定」，读起来像
            // 漏掉了早高峰的判定；而且「可能缓行」与顶部的确定结论「缓行」互相打架。
            trafficRow("午间", "11:00–13:00")
            Divider()

            Text(advice)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 16)

            Text("路况仅按本地时段估算，未接入实时路况；出发前请结合导航 App 的实时信息。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.chipBackground)
                )
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .background(Color.white)
        // 实测贴合会让正文在测量阶段先被截断、高度越测越小，只能定高；
        // 380 是这一版内容（22pt 标题 + 两行免责说明）刚好放满、底部只留一组内边距的高度。
        .presentationDetents([.height(380)])
        .presentationCornerRadius(24)
        .presentationBackground(Color.white)
        .presentationDragIndicator(.visible)
    }

    private func trafficRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }
}

// MARK: - 油价(本次出发)

struct FuelQuote: Equatable {
    let province: String
    let p92: Double?
    let p95: Double?
    let p98: Double?
}

/// 省级油价查询(无需 key),30 分钟缓存；失败保留上一次结果
enum FuelPriceService {
    private struct Response: Decodable {
        struct Payload: Decodable {
            let prov: String?
            let p92: String?
            let p95: String?
            let p98: String?
        }
        let code: Int
        let data: Payload?
    }

    private static var cache: [String: (quote: FuelQuote, at: Date)] = [:]

    static func fetch(province: String) async -> FuelQuote? {
        let key = province
        guard !province.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if let hit = cache[key], Date().timeIntervalSince(hit.at) < 1800 {
            return hit.quote
        }

        let quote = await request(province: province)
        // 接口有响应但三个标号全为空时同样视为无数据，避免把空价格记成“刚刚更新”。
        guard let quote, [quote.p92, quote.p95, quote.p98].contains(where: { $0 != nil }) else {
            return cache[key]?.quote
        }
        cache[key] = (quote, Date())
        return quote
    }

    private static func request(province: String) async -> FuelQuote? {
        var comps = URLComponents(string: "https://api.qqsuu.cn/api/dm-oilprice")!
        comps.queryItems = [
            URLQueryItem(name: "prov", value: shortProvince(province))
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 8

        var payload: Response.Payload?
        for attempt in 0..<2 {
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let response = try? JSONDecoder().decode(Response.self, from: data),
               response.code == 200,
               let dataPayload = response.data {
                payload = dataPayload
                break
            }
            if attempt == 0 {
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
        guard let payload else { return nil }

        let name = payload.prov.flatMap { $0.isEmpty ? nil : $0 }
        return FuelQuote(
            province: name ?? province,
            p92: price(payload.p92),
            p95: price(payload.p95),
            p98: price(payload.p98)
        )
    }

    private static func price(_ raw: String?) -> Double? {
        guard let value = Double(raw ?? ""), value > 0 else { return nil }
        return value
    }

    /// "广东省" → "广东",接口只认简称
    private static func shortProvince(_ raw: String) -> String {
        let suffixes = ["壮族自治区", "回族自治区", "维吾尔自治区", "特别行政区", "自治区", "省", "市"]
        for suffix in suffixes where raw.hasSuffix(suffix) {
            return String(raw.dropLast(suffix.count))
        }
        return raw
    }
}

extension PlaceNameService {
    private struct BCResponse: Decodable {
        let principalSubdivision: String?
        let city: String?
    }

    /// 当前位置 → 省级行政区(广东省 / 上海市 …)
    /// 系统 CLGeocoder 偶尔在模拟器/弱网下返回空，再用 BigDataCloud 兜底
    static func province(for location: CLLocation) async -> String? {
        if let place = try? await CLGeocoder().reverseGeocodeLocation(location).first,
           let area = place.administrativeArea,
           !area.isEmpty {
            return area
        }

        let lat = location.coordinate.latitude
        let lon = location.coordinate.longitude
        guard let url = URL(string: "https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=\(lat)&longitude=\(lon)&localityLanguage=zh") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(BCResponse.self, from: data) else {
            return nil
        }
        if let area = response.principalSubdivision, !area.isEmpty { return area }
        return response.city
    }
}

/// 车顶灯带：上窄下宽的梯形
private struct LightBarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.10
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 车底光锥：上窄下宽，像灯打在车后的地面上
private struct BeamShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.17
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 车辆详情(只读)

/// 点击车辆卡片后从底部弹出的车辆详情。
private struct VehicleDetailSheet: View {
    let garage: GarageService
    let vehicle: Vehicle
    let brandText: String
    let modelText: String
    var onSetDefault: (() async -> Bool)?

    @Environment(\.dismiss) private var dismiss
    @State private var isSettingDefault = false
    @State private var showSetDefaultFailed = false

    private struct DetailRow: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    private var model: VehicleModel? {
        garage.model(for: vehicle.modelId)
    }

    private func trimmed(_ text: String?) -> String? {
        let value = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var rows: [DetailRow] {
        var list: [DetailRow] = []
        if let type = trimmed(model?.modelType) { list.append(DetailRow(label: "车型", value: type)) }
        if let cc = model?.displacementCc { list.append(DetailRow(label: "排量", value: "\(cc)cc")) }
        if let color = trimmed(vehicle.color) { list.append(DetailRow(label: "颜色", value: color)) }
        if let nickname = trimmed(vehicle.nickname), !isRedundantNickname(nickname) {
            list.append(DetailRow(label: "昵称", value: nickname))
        }
        return list
    }

    /// 昵称若只是车型全名的复制(最常见的是添加车辆时自动写入的「春风 800NK」),
    /// 再展示一遍没有信息量，直接省略。
    private func isRedundantNickname(_ nickname: String) -> Bool {
        let modelName = model?.name ?? modelText
        let candidates = [
            modelName,
            modelText,
            "\(brandText) \(modelText)",
            "\(brandText) \(modelName)",
        ]
        let normalized = nickname.replacingOccurrences(of: " ", with: "").lowercased()
        return candidates.contains {
            $0.replacingOccurrences(of: " ", with: "").lowercased() == normalized
        }
    }

    private var estimatedHeight: CGFloat {
        var header: CGFloat = 46
        if vehicle.isDefault { header += 22 }
        header = max(header, 88)
        // 109 是早先按「胶囊 + 完成行 + 底部留白」估的，实测比内容高出一截：
        // 两行信息的默认车辆在「完成」下面还空着约 70pt。收到 78 后
        // 与其它底部面板（按钮下约一个安全区的量）观感一致。
        var height: CGFloat = 78
        height += header
        height += CGFloat(rows.count) * 38
        if !vehicle.isDefault, garage.vehicles.count > 1, onSetDefault != nil { height += 53 }
        return height
    }

    /// sheet 的 detent 高度包含底部安全区，而内容本身只按安全区以上布局。
    /// 不扣掉这段会让「完成」下面多出一整块空白。
    private var bottomSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .keyWindow?.safeAreaInsets.bottom ?? 0
    }

    private var detentHeight: CGFloat {
        // 只按内容估算：测量值会和 detent 互相反馈，偶尔把 sheet 撑到远高于内容，
        // 在「完成」下面留出一大块空白。
        let base = estimatedHeight
        let maxAllowed = UIScreen.main.bounds.height - 80
        return min(maxAllowed, max(260, base + bottomSafeArea))
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)

            header
                .padding(.horizontal, 20)
                .padding(.bottom, 10)

            if !rows.isEmpty {
                Divider().padding(.horizontal, 20)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: 1)
                        }
                        infoRow(row.label, row.value)
                    }
                }
                .padding(.horizontal, 20)
            }

            // 不在这里放 Spacer：Spacer 会把内容撑到 detent 高度，
            // 实测高度永远等于当前 detent，「完成」上方那块空白就收不掉。
            Divider()
                .padding(.top, 12)

            if !vehicle.isDefault, garage.vehicles.count > 1, let onSetDefault {
                Button {
                    guard !isSettingDefault else { return }
                    isSettingDefault = true
                    Task {
                        let ok = await onSetDefault()
                        isSettingDefault = false
                        if ok {
                            dismiss()
                        } else {
                            showSetDefaultFailed = true
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        if isSettingDefault {
                            ProgressView().controlSize(.small)
                        }
                        Text(isSettingDefault ? "正在设置" : "设为默认车辆")
                    }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(RowPressStyle())
                .disabled(isSettingDefault)

                Divider()
            }

            Button {
                dismiss()
            } label: {
                Text("完成")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(RowPressStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
        .background(Color.white)
        // 内容比估算更矮时，固定 detent 会把多出来的高度留在「完成」上方，
        // 中间空出近百 pt；改成按实测内容贴合，估算值只做兜底。
        .fittedSheetHeight(fallback: detentHeight)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(24)
        .presentationBackground(Color.white)
        .wellwayDialog(
            isPresented: $showSetDefaultFailed,
            title: "设置失败",
            message: garage.errorMessage ?? "请检查网络后重试",
            buttons: [WellwayDialogButton(title: "知道了", role: .plain) {}]
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            // 与首页车辆卡保持一致：透明底、按 4:3 满幅填充。
            // 之前塞进 88x88 的圆角方块并额外留白，同一张车型图在弹窗里只剩邮票大小，
            // 看起来像换了另一张图。
            Group {
                if let photo = garage.photos[vehicle.id] {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ModelImage(model: model)
                }
            }
            .frame(width: 104, height: 78)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(brandText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(modelText)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(2)
                if vehicle.isDefault {
                    Text("默认")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Theme.lightField)
                        .clipShape(Capsule())
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black)
                .lineLimit(1)
        }
        .frame(height: 38)
    }

}


// MARK: - 深色玻璃卡片

private struct GlassCard: ViewModifier {
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
    }
}

extension View {
    fileprivate func glassCard(_ radius: CGFloat) -> some View {
        modifier(GlassCard(radius: radius))
    }
}

