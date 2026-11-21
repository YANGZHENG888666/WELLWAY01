import SwiftUI
import UIKit
import CoreLocation

/// 出发(Figma Tab「出发」):选车 → 选路线 → 开始骑行
/// 流程复用：骑行前权限检查 → 导航方式选择 → 骑行中
struct DepartView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(NavChoiceCenter.self) private var navChoice
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @State private var routes: [Route] = []
    @State private var checkpointsByRoute: [Int: [Checkpoint]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 路线列表可用但坐标没刷新成功:不能把它伪装成整页路线加载失败
    @State private var checkpointWarning: String?
    @State private var selectedRouteId: Int?
    @State private var routeToOpen: Route?
    @State private var locationFetcher = OneShotLocationFetcher()
    /// 用户手动翻过路线后，不再用定位结果覆盖他的选择
    @State private var didChooseRouteManually = false
    @State private var didResolveDefaultRoute = false

    @State private var defaultVehicle: (id: UUID, name: String, ordinal: Int?, imageUrl: String?)?
    @State private var hasVehicle = true
    /// 车辆接口失败 ≠ 没有车辆：不能把网络错误引导成「去添加车辆」
    @State private var vehicleLoadFailed = false
    @State private var showGarage = false
    @State private var showNoVehicleGuide = false
    @State private var showRiding = false
    /// 定位被拒绝时不能静默开始一条 0 轨迹的骑行记录
    @State private var showLocationRequired = false
    /// 路线缺少起终点坐标时，给出明确原因与重新加载入口，而不是点击无反应
    @State private var showRouteCoordinatesUnavailable = false
    /// 先导航到起点后回到 App:已到达起点附近，询问是否继续导航到终点
    @State private var showArrivedAtStart = false
    /// 骑行参考给出的适宜度：低于 55 分（不建议骑行）时，出发前必须再确认一次
    @State private var suitabilityScore: Int?
    /// 调试：-departlowsuit 只覆盖确认框里的展示分数，真实天气数据仍按接口返回
    private var lowSuitabilityPreviewScore: Int? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-departlowsuit") { return 45 }
        #endif
        return nil
    }
    /// 调试：-departlowsuit 冷启动即弹出确认框，便于截图复检
    @State private var showLowSuitability = ProcessInfo.processInfo.arguments.contains("-departlowsuit")
    private var selectedRoute: Route? {
        routes.first { $0.id == selectedRouteId }
    }

    /// SE 等 667pt 高的小屏：路线图从 148pt 收到 128pt，
    /// 让「骑行参考」摘要行完整落在开始按钮的 18pt 渐变上方。
    private var isShortScreen: Bool {
        let height = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .screen.bounds.height ?? 800
        return height < 700
    }

    // SE 上要同时放下路线卡、骑行参考摘要和底部开始按钮：
    // 地图收到 98pt，摘要才能完整露出，不再只露出卡片上沿。
    private var routePreviewHeight: CGFloat { isShortScreen ? 98 : 148 }

    /// 面板始终跟随当前选中的路线
    private var displayRoute: Route {
        selectedRoute ?? routes[0]
    }

    /// 通过全局覆盖层展示导航方式选择(盖住 Tab 栏，避开 iOS 26 浮动 sheet 底部留白)
    private func presentNavChoice() {
        guard let route = selectedRoute else { return }
        guard selectedRouteCoordinatesReady else {
            showRouteCoordinatesUnavailable = true
            return
        }
        navChoice.route = route
        navChoice.onWellway = { beginInAppRide() }
        let cps = (checkpointsByRoute[route.id] ?? []).sorted { $0.seq < $1.seq }
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

    private func beginInAppRide() {
        let status = CLLocationManager().authorizationStatus
        guard status != .denied, status != .restricted else {
            showLocationRequired = true
            return
        }
        showRiding = true
    }

    /// 展开后把「骑行参考」顶到可视区顶部。
    /// 只滚一次不够：面板展开会改变内容高度，第一次 scrollTo 还按旧高度算，
    /// 矮屏（SE）上会被夹回原位，表现成「点了展开什么都没发生」。动画结束后补一次。
    private func scrollToInfoPanel(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo("rideInfoPanel", anchor: .top)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("rideInfoPanel", anchor: .top)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    vehicleCard
                        .motionAppear(delay: 0.05)
                    routeSection
                        .motionAppear(delay: 0.15)
                    if !routes.isEmpty {
                        RideInfoPanel(
                            route: displayRoute,
                            checkpoints: checkpointsByRoute[displayRoute.id] ?? [],
                            collapsible: true,
                            // 调试：-departexpanded 直接展开，便于截图复检收起按钮与长内容
                            initiallyExpanded: ProcessInfo.processInfo.arguments.contains("-departexpanded"),
                            // 展开后统一把面板顶到可视区：大屏上折叠摘要贴近底部按钮栏，
                            // 展开内容的第一屏会被按钮栏裁掉，点「查看详情」看起来像没反应。
                            onExpand: { scrollToInfoPanel(proxy) },
                            onSuitabilityChange: { suitabilityScore = $0 }
                        )
                        .id("rideInfoPanel")
                        .padding(.top, isShortScreen ? 6 : 20)
                        .motionAppear(delay: 0.22)
                    }
                    // 主按钮用 safeAreaInset 独占底部，Tab 栏不会再压住滚动内容；
                    // 这里只留 24pt 收尾呼吸，避免滚到底出现一大块空白。
                    Color.clear.frame(height: 24)
                        .id("pageBottom")
                }
                .onAppear {
                    let args = ProcessInfo.processInfo.arguments
                    // 调试：-departexpanded 复检展开后滚到面板顶部的版式
                    if args.contains("-departexpanded") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                            scrollToInfoPanel(proxy)
                        }
                    }
                    // 调试：-departbottom 直接滚到页尾，检查逐小时条等长内容的收尾
                    if args.contains("-departbottom") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo("pageBottom", anchor: .bottom) }
                        }
                        // 天气 / 路线热度晚到时内容还会变高，补一次滚到底，
                        // 否则截图停在旧内容高度算出的位置，看到的不是真正的页尾。
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo("pageBottom", anchor: .bottom) }
                        }
                    }
                }
                // 主行动必须直接挂在 ScrollView 上：挂在 ScrollViewReader 外层时
                // 滚动区不会扣掉按钮栏高度，滚到底的免责说明会被整条按钮栏压住。
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    startButton
                        .motionAppear(delay: 0.28)
                }
            }
        }
        .background(Color.white)
        .navigationDestination(isPresented: $showGarage) {
            // 出发页进来的是「更换车辆」:竖排选车列表，不是首页那套 P房
            VehicleSwitchView()
        }
        .navigationDestination(item: $routeToOpen) { route in
            RouteDetailView(
                route: route,
                checkpoints: checkpointsByRoute[route.id] ?? [],
                ridersCount: 0
            )
        }
        .fullScreenCover(isPresented: $showRiding) {
            if let route = selectedRoute {
                RidingView(
                    route: route,
                    checkpoints: checkpointsByRoute[route.id] ?? [],
                    vehicleId: defaultVehicle?.id,
                    vehicleName: defaultVehicle?.name
                )
            }
        }
        .wellwayDialog(
            isPresented: $showLowSuitability,
            title: "当前不建议骑行",
            message: "天气适宜度 \((lowSuitabilityPreviewScore ?? suitabilityScore).map { "\($0)" } ?? "--") 分，天气或气象预警存在风险。如仍要出发，请谨慎慢行。",
            buttons: [
                WellwayDialogButton(title: "仍要出发", role: .primary) {
                    PermissionHelper.requestRidePermissions()
                    presentNavChoice()
                },
                WellwayDialogButton(title: "取消", role: .plain) {}
            ]
        )
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
            message: "这条路线缺少起点或终点坐标，暂时无法开始导航。可以重新加载路线坐标后再试。",
            buttons: [
                WellwayDialogButton(title: "重新加载", role: .primary) {
                    Task { await loadCheckpoints() }
                },
                WellwayDialogButton(title: "取消", role: .plain) {}
            ]
        )
        .task {
            async let routes: Void = load()
            async let vehicle: Void = loadDefaultVehicle()
            _ = await (routes, vehicle)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            handleReturnFromExternalNavigation()
        }
        .onReceive(NotificationCenter.default.publisher(for: .departDraftUpdated)) { _ in
            applyDraftSelection()
        }
        // 「更换车辆」选完车返回：刷新车辆卡片
        .onReceive(NotificationCenter.default.publisher(for: .defaultVehicleChanged)) { _ in
            Task { await loadDefaultVehicle() }
        }
        // 从车库加车/换车返回后重新加载，避免车辆信息不刷新
        .onAppear {
            Task { await loadDefaultVehicle() }
        }
    }

    /// 从第三方地图返回 App:若之前选择了「先导航到路线起点」,检测是否已到达起点附近
    private func handleReturnFromExternalNavigation() {
        guard navChoice.awaitingArrivalAtStart else { return }
        Task {
            await navChoice.fetchCurrentLocation()
            if let d = navChoice.distanceToStartKm, d <= 0.5 {
                navChoice.awaitingArrivalAtStart = false
                showArrivedAtStart = true
            }
            // 中途切回 App 但还没到起点时保留等待状态：
            // 用户再次从地图返回时继续判断，避免只回来一次就永久失去到达提示。
        }
    }

    private var header: some View {
        DesignPageHeader(title: "出发", showsBack: false, compact: true)
    }

    private var vehicleCard: some View {
        Button {
            if vehicleLoadFailed {
                Task { await loadDefaultVehicle() }
            } else {
                showGarage = true
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("本次车辆")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 6) {
                        Text(defaultVehicle?.name ?? (vehicleLoadFailed ? "车辆信息加载失败" : "未选择车辆"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                        // 同款多辆时给出序号：出发页决定这次用哪辆车，只写车型名会让
                        // 第 1 辆和第 3 辆 450SR 看起来完全一样（车辆列表页已有同一枚标签）。
                        if let ordinal = defaultVehicle?.ordinal {
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
                    if vehicleLoadFailed {
                        Text("点按重试")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    } else if defaultVehicle == nil {
                        Text("去车库添加你的爱车")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                DepartVehicleThumb(urlString: defaultVehicle?.imageUrl)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            // SE 上折叠摘要多出空气 / 限行一行后，车辆行少留 4pt 纵向余量，
            // 让第二行完整落在底部按钮栏上方，而不是被切掉半行。
            .padding(.vertical, isShortScreen ? 10 : 14)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(height: 1)
            }
        }
        .buttonStyle(RowPressStyle())
        // 只在这里给一次 20pt 横向边距：行内再补一层会让「本次车辆」比下方的
        // 「选择路线」和路线卡多缩进 20pt，同屏两条不同的左边线
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// 左右切换路线；只在横向位移明确大于纵向位移时响应，避免抢走出发页的纵向滚动。
    private func moveRoute(by offset: Int) {
        guard !routes.isEmpty else { return }
        didChooseRouteManually = true
        let currentIndex = routes.firstIndex { $0.id == selectedRouteId } ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), routes.count - 1)
        guard nextIndex != currentIndex else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            selectedRouteId = routes[nextIndex].id
        }
    }

    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("选择路线")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 20)

            if isLoading, routes.isEmpty {
                routeCardSkeleton
            } else if let errorMessage, routes.isEmpty {
                NetworkErrorView(message: errorMessage) {
                    Task { await load() }
                }
            } else if routes.isEmpty {
                VStack(spacing: 20) {
                    DesignEmptyState(
                        icon: "map",
                        title: "暂无可用路线",
                        message: "新路线正在准备中，也可以先去路线页看看"
                    )
                    Button {
                        NotificationCenter.default.post(name: .switchToRoutesTab, object: nil)
                    } label: {
                        Text("去找一条路线")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(SolidPressStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 0) {
                    if errorMessage != nil {
                        InlineRefreshNotice(message: "路线刷新失败，当前显示上次数据") {
                            Task { await load() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    }
                    if checkpointWarning != nil, errorMessage == nil {
                        InlineRefreshNotice(message: "路线坐标未更新，导航可能不完整") {
                            Task { await loadCheckpoints() }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                    }

                    // 单屏一张，横向拖动切页；小圆点负责明确指示并可点按切换。
                    // 不再嵌套横向 ScrollView，避免和页面纵向滚动抢手势。
                    routeButton(displayRoute)
                        .id(displayRoute.id)
                        .transition(.opacity)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 24)
                                .onEnded { value in
                                    let dx = value.translation.width
                                    let dy = value.translation.height
                                    guard abs(dx) > abs(dy) * 1.25, abs(dx) > 44 else { return }
                                    moveRoute(by: dx < 0 ? 1 : -1)
                                }
                        )

                    if routes.count > 1 {
                        // 圆点本身就是按钮：命中区做到 44pt 高（点的视觉仍 5pt），
                        // 用负间距把相邻命中区叠回去，保持原来 22pt 的点距视觉。
                        HStack(spacing: -22) {
                            ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                                Button {
                                    didChooseRouteManually = true
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        selectedRouteId = route.id
                                    }
                                } label: {
                                    Circle()
                                        .fill(route.id == selectedRouteId ? Color.black : Color.black.opacity(0.14))
                                        .frame(width: 5, height: 5)
                                        .frame(width: 44, height: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(IconPressStyle(pressedOpacity: 0.6))
                                .accessibilityLabel("第 \(index + 1) 条路线，共 \(routes.count) 条，\(route.name)")
                                .accessibilityValue(route.id == selectedRouteId ? "已选择" : "未选择")
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .animation(.easeOut(duration: 0.18), value: selectedRouteId)
                    }
                }
            }
        }
        .padding(.top, isShortScreen ? 12 : 16)
    }

    /// 路线卡首次加载骨架：与横向分页卡同尺寸，避免冷启动时页面突然塌成转圈
    private var routeCardSkeleton: some View {
        let block = Theme.lightField
        let line = Theme.separator
        return VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(block)
                .frame(height: routePreviewHeight)
            line
                .frame(width: 112, height: 15)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 10)
            line
                .frame(width: 92, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 7)
            line
                .frame(width: 136, height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .accessibilityHidden(true)
    }

    private func routeButton(_ route: Route) -> some View {
        return Button {
            didChooseRouteManually = true
            selectedRouteId = route.id
            routeToOpen = route
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                RouteThumbnailView(
                    route: route,
                    checkpoints: checkpointsByRoute[route.id] ?? [],
                    reservesTextArea: false
                )
                .frame(maxWidth: .infinity)
                .frame(height: routePreviewHeight)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text(route.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .padding(.top, 10)

                HStack(spacing: 5) {
                    Circle()
                        .fill(Theme.success)
                        .frame(width: 5.5, height: 5.5)
                    Text(route.startName ?? "起点")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.chevron)
                        .padding(.horizontal, 1)
                    // 路线卡上的终点是白色方块，这行用同一种形状：
                    // 空心圆放在 5.5pt 上会被读成一个小写 o
                    RoundedRectangle(cornerRadius: 0.5, style: .continuous)
                        .strokeBorder(Theme.textPrimary.opacity(0.75), lineWidth: 1.3)
                        .frame(width: 5.5, height: 5.5)
                    Text(route.endName ?? "终点")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.top, 6)

                Text(routeMeta(route))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            // 卡片内是缩略图 + 三行文字，系统自动合并会把「·」和「km」直接念出来。
            // 这里改成显式文案：起点终点说清楚，距离用中文「公里」。
            // 修饰必须落在 label 内容上；加在 Button 外层会同时保留系统生成的
            // 自动合并元素，读屏里出现两条同名卡片。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(routeAccessibilityLabel(route))
            .accessibilityHint("查看路线详情")
        }
        .buttonStyle(CardPressStyle(scale: 0.98))
        .padding(.horizontal, 20)
    }

    /// 卡片副标题与路线列表保持一致：地区 · 距离 · 难度
    private func routeMeta(_ route: Route, spoken: Bool = false) -> String {
        let province = route.province?.trimmingCharacters(in: .whitespaces) ?? ""
        let city = route.city?.trimmingCharacters(in: .whitespaces) ?? ""
        let place: String
        if !province.isEmpty, !city.isEmpty {
            place = province == city ? province : "\(province) · \(city)"
        } else {
            place = province.isEmpty ? city : province
        }
        let km = Double(route.distanceM) / 1000
        // 屏幕上的距离统一用 km（与路线详情、车库、骑行总结一致），
        // 「公里」只出现在读屏文案里。
        let distance = (km == km.rounded() ? String(format: "%.0f", km) : String(format: "%.1f", km))
            + (spoken ? " 公里" : " km")
        let parts = [place, distance, route.difficulty]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return parts.joined(separator: spoken ? "，" : " · ")
    }

    /// 读屏用路线卡文案。屏幕上的「·」会被念成停顿、「km」会被念成字母，
    /// 所以整卡合成一句：名称，起点 x，终点 y，地区，9.8 公里，简单。
    private func routeAccessibilityLabel(_ route: Route) -> String {
        var parts = [route.name]
        if let start = route.startName?.trimmingCharacters(in: .whitespaces), !start.isEmpty {
            parts.append("起点 \(start)")
        }
        if let end = route.endName?.trimmingCharacters(in: .whitespaces), !end.isEmpty {
            parts.append("终点 \(end)")
        }
        parts.append(routeMeta(route, spoken: true))
        return parts
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "，")
    }

    private var startButton: some View {
        Button {
            if vehicleLoadFailed {
                Task { await loadDefaultVehicle() }
                return
            }
            guard selectedRouteCoordinatesReady else {
                showRouteCoordinatesUnavailable = true
                return
            }
            Haptics.tap()
            if hasVehicle {
                // 天气恶劣/预警时适宜度会被压到 55 分以下：这时不能一点就走，
                // 让用户先看到结论再决定，避免安全提示只躺在展开面板里没人看。
                if let score = lowSuitabilityPreviewScore ?? suitabilityScore, score < 55 {
                    showLowSuitability = true
                    return
                }
                PermissionHelper.requestRidePermissions()
                presentNavChoice()
            } else {
                showNoVehicleGuide = true
            }
        } label: {
            let canTap = selectedRoute != nil || vehicleLoadFailed
            Text(ctaTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(canTap ? Color.white : Theme.listGray)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(canTap ? Color.black : Theme.lightField)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        // 车辆接口失败时按钮用来重试，不能因为还没选中路线而被禁用。
        .allowsHitTesting(selectedRoute != nil || vehicleLoadFailed)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .wellwayBottomBar()
    }

    /// 主按钮文案要跟着前置条件走：没有车辆时不能只写「开始骑行」再弹提示
    private var ctaTitle: String {
        if vehicleLoadFailed { return "重新加载车辆" }
        if selectedRoute == nil { return "选择路线后开始骑行" }
        // 路线详情页的同名文案是禁用按钮；出发页这里是可点重载的主行动，
        // 所以用动词文案，避免同一个标签在两页表示不同交互。
        if !selectedRouteCoordinatesReady { return "重新载入路线坐标" }
        return hasVehicle ? "开始骑行" : "添加车辆后开始骑行"
    }

    /// 导航起点与终点至少需要两枚有效坐标。
    private var selectedRouteCoordinatesReady: Bool {
        #if DEBUG
        // 调试：-departnocoords 复检「路线坐标未就绪」引导，不改动真实打卡点数据
        if ProcessInfo.processInfo.arguments.contains("-departnocoords") { return false }
        #endif
        guard let selectedRoute else { return false }
        return (checkpointsByRoute[selectedRoute.id] ?? []).compactMap { checkpoint -> CLLocationCoordinate2D? in
            guard let lat = checkpoint.lat, let lng = checkpoint.lng,
                  lat != 0, lng != 0 else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }.count >= 2
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        errorMessage = nil
        // 打卡点与路线互不依赖：并行拉取，避免串行等待
        async let checkpoints: Void = loadCheckpoints()
        do {
            let client = auth.client
            let loadedRoutes: [Route] = try await client
                .from("routes")
                .select("id, name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, map_url, cover_image_url, province, city")
                .eq("is_active", value: true)
                .order("id")
                .execute()
                .value
            routes = loadedRoutes
            applyDraftSelection()
        } catch {
            errorMessage = error.wellwayUserMessage
        }
        await checkpoints
        await resolveNearestRouteIfNeeded()
    }

    /// 坐标与路线分两次查询：任一失败时保留另一份可用数据，并只提示对应部分
    private func loadCheckpoints() async {
        do {
            let checkpoints: [Checkpoint] = try await auth.client
                .from("checkpoints")
                .select("id, route_id, name, seq, lat, lng, radius_m")
                .order("seq")
                .execute()
                .value
            var grouped: [Int: [Checkpoint]] = [:]
            for cp in checkpoints {
                grouped[cp.routeId, default: []].append(cp)
            }
            checkpointsByRoute = grouped
            checkpointWarning = nil
        } catch {
            checkpointWarning = "路线坐标未更新，导航可能不完整"
        }
    }

    /// 没有目的地草稿时，优先把离当前位置最近的路线排在前面并选中。
    /// 定位未授权或失败时保持后台顺序，不为了排序额外打断用户。
    private func resolveNearestRouteIfNeeded() async {
        guard !didResolveDefaultRoute, !routes.isEmpty else { return }
        didResolveDefaultRoute = true
        guard DepartDraft.shared.route == nil, !didChooseRouteManually else { return }
        let status = CLLocationManager().authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        guard let location = await locationFetcher.fetchLocation() else { return }

        let sorted = routes.sorted {
            distanceToStart($0, from: location) < distanceToStart($1, from: location)
        }
        guard let nearest = sorted.first, !didChooseRouteManually,
              DepartDraft.shared.route == nil else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            routes = sorted
            selectedRouteId = nearest.id
        }
    }

    private func distanceToStart(_ route: Route, from location: CLLocation) -> CLLocationDistance {
        let start = (checkpointsByRoute[route.id] ?? [])
            .sorted { $0.seq < $1.seq }
            .first { checkpoint in
                guard let lat = checkpoint.lat, let lng = checkpoint.lng else { return false }
                return lat != 0 && lng != 0
            }
        guard let start, let lat = start.lat, let lng = start.lng else {
            return .greatestFiniteMagnitude
        }
        return location.distance(from: CLLocation(latitude: lat, longitude: lng))
    }

    /// 选中路线：优先 P房「选择目的地」添加的路线，否则默认第一条
    private func applyDraftSelection() {
        let draftId = DepartDraft.shared.route?.id
        if let draftId, routes.contains(where: { $0.id == draftId }) {
            selectedRouteId = draftId
        } else if selectedRouteId == nil {
            selectedRouteId = routes.first?.id
        }
    }

    /// 默认车辆(与路线详情页一致)
    private func loadDefaultVehicle() async {
        vehicleLoadFailed = false
        guard let uid = auth.user?.id else {
            hasVehicle = false
            return
        }
        struct VehicleNames: Decodable {
            let id: UUID
            let nickname: String?
            let modelId: Int
            let model: NameRow?
            let brand: NameRow?
            struct NameRow: Decodable {
                let name: String
                let nameEn: String?
                let imageUrl: String?
                enum CodingKeys: String, CodingKey {
                    case name
                    case nameEn = "name_en"
                    case imageUrl = "image_url"
                }
            }
            enum CodingKeys: String, CodingKey {
                case id, nickname
                case model = "models"
                case brand = "brands"
                case modelId = "model_id"
            }
        }
        do {
            let vehicles: [VehicleNames] = try await auth.client
                .from("vehicles")
                .select("id, nickname, model_id, models(name, image_url), brands(name, name_en)")
                .eq("user_id", value: uid)
                .order("is_default", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            guard let first = vehicles.first else {
                hasVehicle = false
                defaultVehicle = nil
                return
            }
            let name = VehicleDisplayName.make(
                brandName: first.brand?.name,
                brandNameEn: first.brand?.nameEn,
                rawModelName: first.model?.name,
                nickname: first.nickname
            )
            // 序号口径与「我的车辆」列表一致：同一 modelId 的车辆按同样排序取位置
            let sameModel = vehicles.filter { $0.modelId == first.modelId }
            let ordinal: Int? = sameModel.count > 1
                ? sameModel.firstIndex(where: { $0.id == first.id }).map { $0 + 1 }
                : nil
            defaultVehicle = (first.id, name, ordinal, first.model?.imageUrl)
            hasVehicle = true
        } catch {
            hasVehicle = false
            defaultVehicle = nil
            vehicleLoadFailed = true
        }
    }
}

/// 出发页车辆行缩略图：复用车型真图（透明抠图）缓存，没有图时不留空位。
private struct DepartVehicleThumb: View {
    let urlString: String?

    private var url: URL? {
        guard let raw = urlString?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        return URL(string: raw)
    }

    var body: some View {
        if let url {
            Group {
                if let image = ModelPhotoLoader.shared.cached(url) {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Color.clear
                }
            }
            .frame(width: 64, height: 48)
            .task(id: url) { _ = await ModelPhotoLoader.shared.image(for: url) }
        }
    }
}
