import SwiftUI
import UIKit
import CoreLocation

struct RootView: View {
    @Environment(AuthManager.self) private var auth
    @State private var showSplash = true
    /// 根视图是外观的唯一真源：preferredColorScheme 只有最外层生效,
    /// 子页面(骑行 HUD 等)通过 ScreenAppearance.shared 请求,不能各自声明。
    /// 用单例而不是 environment:全屏 cover 的环境传递并不总是可靠。
    private var screenAppearance: ScreenAppearance { .shared }

    /// 调试启动页：`-routes` 进路线 Tab,`-depart` 进出发 Tab,`-profile` 进个人中心 Tab,默认首页
    private static var debugInitialTab: Int {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-depart") { return 2 }
        if args.contains("-routes") { return 1 }
        if args.contains("-team") { return 3 }
        if args.contains("-profile") { return 4 }
        return 0
    }

    var body: some View {
        rootContent
            .preferredColorScheme(screenAppearance.colorScheme)
    }

    @ViewBuilder
    private var rootContent: some View {
        if ProcessInfo.processInfo.arguments.contains("-signup") {
            EmailSignupView()
        } else if ProcessInfo.processInfo.arguments.contains("-codelogin") {
            EmailSignupView(codeLoginMode: true)
        } else if ProcessInfo.processInfo.arguments.contains("-passwordlogin") {
            PasswordLoginView()
        } else if ProcessInfo.processInfo.arguments.contains("-forgot") {
            ForgotPasswordView()
        } else if ProcessInfo.processInfo.arguments.contains("-loginsuccess") {
            LoginSuccessView(onEnter: {})
        } else if ProcessInfo.processInfo.arguments.contains("-login") {
            AuthView()
        } else if ProcessInfo.processInfo.arguments.contains("-gallery") {
            DesignGalleryView()
        } else if ProcessInfo.processInfo.arguments.contains("-summary") {
            DebugRideSummaryLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-sharecard") {
            DebugRideShareCardLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-badgeearned") {
            DebugBadgeEarnedLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-badgedetail") {
            DebugBadgeDetailLoader(earned: !ProcessInfo.processInfo.arguments.contains("-badgelocked"))
                .environment(NavChoiceCenter())
        } else if ProcessInfo.processInfo.arguments.contains("-badgesharepreview") {
            DebugBadgeSharePreview()
        } else if ProcessInfo.processInfo.arguments.contains("-riding") {
            DebugRideLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-arrival") {
            DebugRideLoader(arrival: true)
        } else if ProcessInfo.processInfo.arguments.contains("-mapswitch") {
            DebugRideLoader(mapOnly: true)
        } else if ProcessInfo.processInfo.arguments.contains("-navchoice") {
            DebugNavChoiceLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-dialogdemo") {
            DebugDialogLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-routedetailpicker") {
            DebugRouteDetailLoader(pickDestinationMode: true)
        } else if ProcessInfo.processInfo.arguments.contains("-routedetail") {
            DebugRouteDetailLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-destinationpicker") {
            // 路线详情要读 NavChoiceCenter：调试入口没注入会在点开任一条路线时直接崩溃
            NavigationStack { RoutesView(onClose: {}) }
                .environment(NavChoiceCenter())
        } else if ProcessInfo.processInfo.arguments.contains("-riders") {
            DebugRouteDetailLoader(ridersOnly: true)
        } else if ProcessInfo.processInfo.arguments.contains("-departinfo") {
            DebugDepartInfoLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-records") {
            NavigationStack { RecordsView() }
        } else if ProcessInfo.processInfo.arguments.contains("-profilepage") {
            // 调试：「我的」单页复检(不带 Tab 栏)。-profile 仍按 Tab 4 启动
            NavigationStack { ProfileView() }
        } else if ProcessInfo.processInfo.arguments.contains("-settings") {
            NavigationStack { SettingsView() }
        } else if ProcessInfo.processInfo.arguments.contains("-vehicleswitch") {
            NavigationStack { VehicleSwitchView() }
        } else if ProcessInfo.processInfo.arguments.contains("-vehicles") {
            NavigationStack { MyVehiclesView() }
        } else if ProcessInfo.processInfo.arguments.contains("-badges") {
            NavigationStack { BadgesView(initialBadgeId: ProcessInfo.processInfo.arguments.contains("-badgedeeplink") ? 1 : nil) }
                .environment(NavChoiceCenter())
        } else if ProcessInfo.processInfo.arguments.contains("-recorddetail") {
            DebugRecordDetailLoader()
        } else if ProcessInfo.processInfo.arguments.contains("-notifications") {
            NavigationStack { NotificationsView() }
        } else if ProcessInfo.processInfo.arguments.contains("-agreement-user") {
            NavigationStack { AgreementView(kind: .userAgreement) }
        } else if ProcessInfo.processInfo.arguments.contains("-agreement-intro") {
            NavigationStack { AgreementView(kind: .privacyIntro) }
        } else if ProcessInfo.processInfo.arguments.contains("-agreement") {
            NavigationStack { AgreementView(kind: .privacyPolicy) }
        } else if ProcessInfo.processInfo.arguments.contains("-emailbind") {
            NavigationStack { EmailBindView() }
        } else if ProcessInfo.processInfo.arguments.contains("-networkerror") {
            // 四种错误体验证入口：默认断网，另加 -networkerror-server / -auth / -timeout
            let args = ProcessInfo.processInfo.arguments
            let sample = args.contains("-networkerror-server") ? "操作未完成，请稍后重试"
                : args.contains("-networkerror-auth") ? "当前操作没有权限，请重新登录后再试"
                : args.contains("-networkerror-timeout") ? "请求超时，请稍后重试"
                : "网络连接不可用，请检查网络后重试"
            NetworkErrorView(message: sample) {}
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
        } else if ProcessInfo.processInfo.arguments.contains("-about") || ProcessInfo.processInfo.arguments.contains("-feedback") {
            NavigationStack { AboutFeedbackView() }
        } else if ProcessInfo.processInfo.arguments.contains("-addvehicle") {
            DebugGarageFlowLoader(mode: .addVehicle)
        } else if ProcessInfo.processInfo.arguments.contains("-picker") {
            DebugGarageFlowLoader(mode: .picker)
        } else if ProcessInfo.processInfo.arguments.contains("-pickermodels") {
            DebugGarageFlowLoader(mode: .modelPicker)
        } else if ProcessInfo.processInfo.arguments.contains("-addvehicleselected") {
            DebugGarageFlowLoader(mode: .addVehicleSelected)
        } else {
            ZStack {
                // 正式内容(登录/主界面)铺底，开屏动画在其上层播放后淡出
                content

                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .ignoresSafeArea(.keyboard)
            .tint(Theme.primary)
            .animation(.easeInOut(duration: 0.28), value: auth.state)
            .animation(.easeInOut(duration: 0.28), value: auth.pendingLoginSuccess)
        }
    }

    /// 登录/主界面内容(与开屏动画同层，位于其下层)
    private var content: some View {
        ZStack {
            switch auth.state {
            case .loading:
                VStack(spacing: 12) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 33)
                    ProgressView()
                    Text("正在进入 WellWay…")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .transition(.opacity)
            case .signedOut:
                AuthView()
                    .transition(.opacity)
            case .signedIn:
                if auth.pendingLoginSuccess {
                    LoginSuccessView(onEnter: {
                        auth.enterMain()
                    })
                    .transition(.opacity)
                } else {
                    MainTabView(initialTab: Self.debugInitialTab)
                        .transition(.opacity)
                }
            }
        }
    }
}

/// 调试入口（-navchoice）：直接打开导航方式弹层，用于设计自查与截图
struct DebugNavChoiceLoader: View {
    @State private var isPresented = true
    @State private var center = NavChoiceCenter()

    private static var isFarDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-navchoice-far")
    }
    private static var confirmDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-navchoice-confirm")
    }

    private let route = Route(
        id: 0,
        name: "四惠桥通勤线",
        startName: "四惠桥",
        endName: "国贸",
        distanceM: 12_600,
        elevationM: 120,
        difficulty: "简单",
        durationMin: 45,
        mapUrl: nil,
        coverImageUrl: nil,
        province: "北京",
        city: "北京"
    )

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if isPresented {
                NavChoiceSheet(
                    isPresented: $isPresented,
                    route: route,
                    startLat: 39.9087,
                    startLng: 116.3975,
                    endLat: 39.9097,
                    endLng: 116.4575,
                    currentLat: Self.isFarDemo ? 39.9330 : 39.9088,
                    currentLng: Self.isFarDemo ? 116.4200 : 116.3976,
                    center: center,
                    autoConfirmGoToStart: Self.confirmDemo,
                    onWellway: {}
                )
            }
        }
    }
}

/// 调试入口（-dialogdemo）：检查全局弹窗样式
struct DebugDialogLoader: View {
    @State private var multi = !ProcessInfo.processInfo.arguments.contains("-dialogprompt")
    @State private var single = false
    @State private var destructive = false
    @State private var promptOpen = ProcessInfo.processInfo.arguments.contains("-dialogprompt")
    @State private var promptText = "我的 CB400F"

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            Text("弹窗样式")
                .font(.system(size: 20, weight: .bold))
        }
        .wellwayDialog(
            isPresented: $multi,
            title: "你不在起点附近",
            message: "距路线起点约 3.3 km。可以先导航到起点，也可以直接前往终点。",
            buttons: [
                WellwayDialogButton(title: "导航到该路线起点", role: .primary) {},
                WellwayDialogButton(title: "导航到该路线终点", role: .plain) {}
            ]
        )
        .wellwayDialog(
            isPresented: $single,
            title: "已保存",
            message: "车辆信息已更新。",
            buttons: [WellwayDialogButton(title: "知道了", role: .primary) {}]
        )
        .wellwayPrompt(
            isPresented: $promptOpen,
            title: "重命名车辆",
            placeholder: "车辆名称",
            text: $promptText
        ) {}
        .wellwayDialog(
            isPresented: $destructive,
            title: "删除这辆车？",
            message: "将从车库移除这辆车，骑行记录会保留。",
            buttons: [
                WellwayDialogButton(title: "删除车辆", role: .destructive) {},
                WellwayDialogButton(title: "取消", role: .plain) {}
            ]
        )
    }
}

/// 主 Tab 栏(Figma「Tab Bar」292:36):首页 / 路线 / 出发 / 对向 / 个人中心(仅图标)
struct MainTabView: View {
    var initialTab: Int = 0
    @Environment(AuthManager.self) private var auth
    @State private var selectedTab = 0
    @State private var departEpoch = 0
    /// 跨 Tab 跳转时用来把各 Tab 的导航栈收回根页面：
    /// 只切 selectedTab 不会弹掉「车库 → 记录」「我的 → 设置」这类已经推开的页面，
    /// 用户会看到新 Tab 里还压着一层旧页面。
    @State private var stackEpoch = 0
    /// 导航方式选择覆盖层状态(挂载在 Tab 层之上，盖住 Tab 栏)
    @State private var navChoice = NavChoiceCenter()
    /// 全局轻提示：骑行结束后确认记录去向，2.8 秒自动消失
    @State private var toastText: String?
    /// 提示前的图标：成功是勾，失败提示必须是警示，不能给错误配一个对勾
    @State private var toastIcon: String? = "checkmark"
    @State private var toastWork: DispatchWorkItem?

    /// Tab 栏黑白配色(设计稿：未选中 #9A9A9A / 选中黑色，白底，不用系统蓝)
    init(initialTab: Int = 0) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        let normal = UIColor(Theme.listGray)
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = normal
            layout.selected.iconColor = .black
            layout.normal.titleTextAttributes = [.foregroundColor: normal]
            layout.selected.titleTextAttributes = [.foregroundColor: UIColor.black]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                GarageView()
            }
            .id(stackEpoch)
            .tabItem { tabItem(TabIcons.home, "车库") }
            .tag(0)
            NavigationStack {
                RoutesView()
            }
            .id(stackEpoch)
            .tabItem { tabItem(TabIcons.compass, "路线") }
            .tag(1)
            NavigationStack {
                DepartView()
                    .id(departEpoch)
            }
            .id(stackEpoch)
            .tabItem { tabItemBrandMark }
            .tag(2)
            NavigationStack {
                TeamRidersView(title: "对向", showsBack: false)
            }
            .id(stackEpoch)
            .tabItem { tabItem(TabIcons.team, "对向") }
                .tag(3)
            NavigationStack {
                ProfileView()
            }
            .id(stackEpoch)
            .tabItem { tabItem(TabIcons.person, "我的") }
                .tag(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToDepartTab)) { _ in
            // P房「选择目的地」添加路线后需先收起全屏 cover 再切 Tab:
            // 同帧切换会与 cover 收起动画冲突导致停留在车库，延迟等动画完成
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) {
                stackEpoch += 1
                selectedTab = 2
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchToRoutesTab)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                stackEpoch += 1
                selectedTab = 1
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .rideDidFinish)) { note in
            showToast((note.object as? String) ?? "骑行记录已保存")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showToast)) { note in
            guard let message = note.object as? ToastMessage, !message.text.isEmpty else { return }
            showToast(message.text, icon: message.icon)
        }
        .environment(navChoice)
        // 车库首页已改为白底，全部 Tab 统一浅色 Tab 栏
        .onAppear {
            applyTabBarStyle(dark: false)
            if ProcessInfo.processInfo.arguments.contains("-departlate") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { selectedTab = 2 }
            }
            // 调试：-departdraftdemo 完整模拟「路线详情 → 添加到出发页」：
            // 取 id 最大的一条路线写入草稿，再走正式通知链路切 Tab，
            // 用于确认出发页真的选中了这条路线，而不是默认第一条。
            if ProcessInfo.processInfo.arguments.contains("-departdraftdemo") {
                Task {
                    do {
                        let routes: [Route] = try await auth.client
                            .from("routes")
                            .select("id, name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, map_url, cover_image_url, province, city")
                            .eq("is_active", value: true)
                            .order("id")
                            .execute()
                            .value
                        guard let route = routes.last else { return }
                        let cps: [Checkpoint] = (try? await auth.client
                            .from("checkpoints")
                            .select("id, route_id, name, seq, lat, lng, radius_m")
                            .eq("route_id", value: route.id)
                            .order("seq")
                            .execute()
                            .value) ?? []
                        DepartDraft.shared.route = route
                        DepartDraft.shared.checkpoints = cps
                        NotificationCenter.default.post(name: .departDraftUpdated, object: nil)
                        NotificationCenter.default.post(name: .destinationPickerDone, object: nil)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            NotificationCenter.default.post(name: .switchToDepartTab, object: nil)
                        }
                    } catch {}
                }
            }
            // 调试：-toastdemo 走通知通道预览轻提示(和刷新失败共用同一条链路)
            if ProcessInfo.processInfo.arguments.contains("-toastdemo") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    NotificationCenter.default.post(
                        name: .showToast,
                        object: ToastMessage(text: "网络异常，车辆信息未更新", icon: "exclamationmark.triangle.fill")
                    )
                }
            }
        }
        .task {
            // 冷启动时不存在仍在运行的骑行会话：把上一次被系统终止后遗留的
            // riding 记录收尾为「未完成」，避免记录页出现幽灵「进行中」。
            guard let userId = auth.user?.id else { return }
            await InterruptedRideRecovery.abandonInterruptedRides(client: auth.client, userId: userId)
        }
        .onChange(of: selectedTab) { _, newValue in
            applyTabBarStyle(dark: false)
            if newValue == 2 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { departEpoch += 1 }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
        .overlay {
            if navChoice.isPresented, let route = navChoice.route {
                NavChoiceSheet(
                    isPresented: $navChoice.isPresented,
                    route: route,
                    startLat: navChoice.startLat,
                    startLng: navChoice.startLng,
                    endLat: navChoice.endLat,
                    endLng: navChoice.endLng,
                    currentLat: navChoice.currentLat,
                    currentLng: navChoice.currentLng,
                    isLocating: navChoice.isLocating,
                    center: navChoice,
                    locationTask: navChoice.locationTask,
                    onRetryLocation: {
                        Task { await navChoice.fetchCurrentLocation() }
                    }
                ) {
                    navChoice.onWellway?()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(50)
            }
        }
        .overlay(alignment: .bottom) {
            if let toastText {
                HStack(spacing: 6) {
                    if let toastIcon {
                        Image(systemName: toastIcon)
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(toastText)
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.88))
                .clipShape(Capsule())
                // 让开底部悬浮 Tab 胶囊，同时和主按钮留出呼吸距离。
                // 126pt 只够让开 Tab 栏，车库首屏的「开始骑行」会顶到气泡下沿；
                // 这里按「按钮上沿再留 12pt」取值。
                .padding(.bottom, 156)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .allowsHitTesting(false)
                .zIndex(60)
            }
        }
        .animation(.easeOut(duration: 0.2), value: toastText)
    }

    /// 全局轻提示：同一时刻只保留最新一条
    private func showToast(_ text: String, icon: String? = "checkmark") {
        toastWork?.cancel()
        toastText = text
        toastIcon = icon
        let work = DispatchWorkItem { toastText = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4, execute: work)
    }

    /// 首页为深色页面，其余页面为浅色：Tab 栏配色跟随当前 Tab
    private func applyTabBarStyle(dark: Bool) {
        let bg = dark
            ? UIColor(red: 0.04, green: 0.04, blue: 0.04, alpha: 1)
            : UIColor.white
        let normal = dark
            ? UIColor(white: 1.0, alpha: 0.45)
            : UIColor(Theme.listGray)
        let selected = dark ? UIColor.white : UIColor.black
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = bg
        // iOS 26 的悬浮 Tab 栏使用系统玻璃材质，appearance 背景色不会进入该图层。
        appearance.backgroundEffect = nil
        appearance.shadowColor = dark ? .clear : UIColor(white: 0, alpha: 0.12)
        for layout in [appearance.stackedLayoutAppearance,
                       appearance.inlineLayoutAppearance,
                       appearance.compactInlineLayoutAppearance] {
            layout.normal.iconColor = normal
            layout.normal.titleTextAttributes = [.foregroundColor: normal]
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        // 注意：不要设置 isTranslucent = false。iOS 26 上强制设为不透明会让 Tab 栏高度
        // 被重复计入底部安全区，各 Tab 内容底部多出整整一条 Tab 栏的空白（出发页
        // 「开始骑行」按钮会被挤出可见区域）。
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController,
              let tabBar = Self.findTabBar(in: root)?.tabBar else { return }
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.setNeedsLayout()
    }

    private static func findTabBar(in vc: UIViewController) -> UITabBarController? {
        if let tab = vc as? UITabBarController { return tab }
        for child in vc.children {
            if let tab = findTabBar(in: child) { return tab }
        }
        if let presented = vc.presentedViewController {
            return findTabBar(in: presented)
        }
        return nil
    }

    /// 设计稿 Tab Bar 图标(UIImage template 渲染),不带文字标签
    @ViewBuilder
    private func tabItem(_ image: UIImage, _ label: String) -> some View {
        Image(uiImage: image)
            .renderingMode(.template)
            .accessibilityLabel(label)
    }

    /// 出发 Tab:直接用品牌 logo 图片资源(Assets/TabDepart,由「第五版logo反色.svg」生成)。
    /// 必须走 template：路线页等深色内容会让 iOS 26 的悬浮 Tab 栏变成深色玻璃，
    /// 其余四个 Tab 的 template 图标会自动转白，而 original 会保留近黑原色、直接看不见。
    /// 形状与选中/未选中用同一张图，不做旋转等点击变换。
    private var tabItemBrandMark: some View {
        Image("TabDepart")
            .renderingMode(.template)
            .accessibilityLabel("出发")
    }
}


extension Notification.Name {
    /// 「去骑第一条路线」等场景切换到出发 Tab
    static let switchToDepartTab = Notification.Name("switchToDepartTab")
    /// 「去看看路线」等场景切换到热力轨迹 Tab
    static let switchToRoutesTab = Notification.Name("switchToRoutesTab")
    /// P房「选择目的地」完成后：关闭目的地选择弹层
    static let destinationPickerDone = Notification.Name("destinationPickerDone")
    /// 路线已添加到出发页：出发页据此选中/定位该路线
    static let departDraftUpdated = Notification.Name("departDraftUpdated")
    /// 默认车辆已切换(出发 → 更换车辆):出发页据此刷新车辆卡片
    static let defaultVehicleChanged = Notification.Name("defaultVehicleChanged")
    /// 添加车辆全屏流程关闭：车库首页据此跳到刚添加的车辆
    static let addVehicleFlowDismissed = Notification.Name("addVehicleFlowDismissed")
    /// 车辆照片已更换(object 为车辆 id)：首页需丢弃旧缓存并重新拉取
    static let vehiclePhotoChanged = Notification.Name("vehiclePhotoChanged")
    /// 骑行记录保存成功(object 为提示文案)：全局提示一次，避免「点完成之后什么都没发生」
    static let rideDidFinish = Notification.Name("rideDidFinish")
    /// 通用轻提示(object 为提示文案)：刷新失败等不该打断当前内容的一次性反馈
    static let showToast = Notification.Name("showToast")
}

/// 全局轻提示内容：文案 + 前置图标（成功用 checkmark，失败提示用警示图标）
struct ToastMessage {
    let text: String
    let icon: String?
}


/// 调试入口(`-routedetail`):直接打开第一条路线详情，用于设计自查与截图
struct DebugRouteDetailLoader: View {
    /// 只渲染「路线骑手」页：对向页点「查看」的落地页，没有独立入口时无法截图评审。
    var ridersOnly = false
    /// 复检 P房「选择目的地」进入时的底部主行动与关闭路径。
    var pickDestinationMode = false
    @Environment(AuthManager.self) private var auth
    @State private var route: Route?
    @State private var checkpoints: [Checkpoint] = []
    @State private var failed = false
    @State private var navChoice = NavChoiceCenter()

    var body: some View {
        NavigationStack {
            Group {
                if let route {
                    if ridersOnly {
                        RidersView(route: route, checkpoints: checkpoints)
                    } else {
                        RouteDetailView(
                            route: route,
                            checkpoints: checkpoints,
                            pickDestinationMode: pickDestinationMode
                        )
                    }
                } else if failed {
                    Text("路线加载失败")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    ProgressView()
                }
            }
        }
        .environment(navChoice)
        .task {
            do {
                let routes: [Route] = try await auth.client
                    .from("routes")
                    .select("*")
                    .limit(1)
                    .execute()
                    .value
                guard let first = routes.first else {
                    failed = true
                    return
                }
                let cps: [Checkpoint] = try await auth.client
                    .from("checkpoints")
                    .select("*")
                    .eq("route_id", value: first.id)
                    .order("seq", ascending: true)
                    .execute()
                    .value
                route = first
                checkpoints = cps
            } catch {
                failed = true
            }
        }
    }
}


/// 调试入口(`-badgeearned`):静态展示打卡完成徽章页
struct DebugBadgeEarnedLoader: View {
    private let checkpoints = [
        Checkpoint(id: 1, routeId: 1, name: "大理古城", seq: 1, lat: 25.693, lng: 100.162, radiusM: 300),
        Checkpoint(id: 2, routeId: 1, name: "喜洲古镇", seq: 2, lat: 25.852, lng: 100.130, radiusM: 300),
        Checkpoint(id: 3, routeId: 1, name: "双廊", seq: 3, lat: 25.900, lng: 100.194, radiusM: 300)
    ]

    var body: some View {
        BadgeEarnedView(
            badge: Badge(
                id: 1,
                routeId: 1,
                name: "洱海初见",
                imageUrl: nil,
                conditionDesc: "完成洱海环湖线全部打卡点",
                seq: 1
            ),
            checkpoints: checkpoints,
            checkedIds: [1, 2, 3],
            rideDistanceM: 32_400,
            rideDurationS: 4_260,
            rideAvgSpeedKmh: 27.4,
            onClose: {}
        )
    }
}

/// 调试入口(`-badgesharepreview`)：直接展示分享卡渲染结果，验证 ImageRenderer 出图。
/// 可配 `-badgesharelong` 验证长名称/长条件，配 `-badgesharenodate` 验证无获得日期。
struct DebugBadgeSharePreview: View {
    @State private var image: UIImage?
    @State private var failed = false

    private var badge: Badge {
        let long = ProcessInfo.processInfo.arguments.contains("-badgesharelong")
        return Badge(
            id: 1,
            routeId: 1,
            name: long ? "洱海环湖夜骑与双廊日出长距离挑战徽章" : "洱海初见",
            imageUrl: nil,
            conditionDesc: long
                ? "完成洱海环湖线全部打卡点，并在日落前抵达双廊终点，全程不得借助外部交通工具"
                : "完成洱海环湖线全部打卡点",
            seq: 1
        )
    }

    private var dateText: String {
        ProcessInfo.processInfo.arguments.contains("-badgesharenodate") ? "" : "2026年11月12日 18:40"
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .background(Color.white)
                    .ignoresSafeArea()
            } else if failed {
                Text("分享卡渲染失败")
                    .foregroundStyle(Theme.textPrimary)
            } else {
                ProgressView()
            }
        }
        .task {
            guard image == nil, !failed else { return }
            image = BadgeShareCardRenderer.image(
                badge: badge,
                name: badge.name,
                condition: badge.conditionDesc ?? "",
                dateText: dateText
            )
            failed = image == nil
        }
    }
}

/// 调试入口(`-badgedetail`, 可配 `-badgelocked`):分别展示已获得/未获得的徽章详情
struct DebugBadgeDetailLoader: View {
    let earned: Bool
    @Environment(AuthManager.self) private var auth
    @State private var store: BadgesStore?

    private var selectedEntry: BadgeEntry? {
        guard let store, let first = store.entries.first else { return nil }
        return earned ? first : (store.entries.count > 2 ? store.entries[2] : first)
    }

    var body: some View {
        Group {
            if let store, let entry = selectedEntry {
                NavigationStack {
                    BadgeDetailView(entry: entry, store: store)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard store == nil else { return }
            let service = BadgesStore(client: auth.client, userId: auth.user?.id ?? UUID())
            service.applyDebugSample()
            store = service
        }
    }
}


/// 调试入口(`-summary`):静态展示骑行总结，不写数据库
struct DebugRideSummaryLoader: View {
    /// -longnames：把名称换成真实骑行团常出现的长名字，用来验证截断与换行
    private var sampleRouteName: String {
        ProcessInfo.processInfo.arguments.contains("-longnames")
            ? "大理古城到双廊的环洱海长距离耐力骑行挑战路线"
            : "洱海环湖骑行"
    }

    private var route: Route {
        Route(
        id: 1,
        name: sampleRouteName,
        startName: "大理古城",
        endName: "双廊",
        distanceM: 42_100,
        elevationM: 560,
        difficulty: "简单",
        durationMin: 180,
        mapUrl: nil,
        coverImageUrl: nil,
        province: "云南",
        city: "大理"
        )
    }

    private let checkpoints = [
        Checkpoint(id: 1, routeId: 1, name: "大理古城", seq: 1, lat: 25.693, lng: 100.162, radiusM: 300),
        Checkpoint(id: 2, routeId: 1, name: "喜洲古镇", seq: 2, lat: 25.852, lng: 100.130, radiusM: 300),
        Checkpoint(id: 3, routeId: 1, name: "双廊", seq: 3, lat: 25.900, lng: 100.194, radiusM: 300)
    ]

    /// -summaryfailed：记录已建、收尾没同步（可重试）
    /// -summarylost：记录根本没建起来（重试无从下手，只能确认离开）
    private var summaryWarning: String? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-summarylost") { return "骑行记录未能创建，本次轨迹与打卡没有保存" }
        return args.contains("-summaryfailed") ? "骑行记录未能同步到服务器" : nil
    }

    private var summary: RideSummary {
        let noTrack = ProcessInfo.processInfo.arguments.contains("-summarynotrack")
        let record = RideRecord(
            id: UUID(),
            userId: UUID(),
            routeId: 1,
            vehicleId: nil,
            name: "洱海环湖骑行",
            startedAt: "2026-11-05T10:00:00Z",
            endedAt: "2026-11-05T12:08:00Z",
            distanceM: noTrack ? 0 : 42_100,
            durationS: 7_680,
            avgSpeedKmh: noTrack ? 0 : 19.7,
            maxSpeedKmh: noTrack ? 0 : 64.0,
            elevationGainM: noTrack ? 0 : 560,
            status: "finished"
        )
        return RideSummary(
            record: record,
            checkedCheckpointIds: [1, 2, 3],
            awardedBadge: nil,
            allCheckpointsDone: true,
            track: ProcessInfo.processInfo.arguments.contains("-summarytrack")
                ? [
                    CLLocationCoordinate2D(latitude: 25.6930, longitude: 100.1620),
                    CLLocationCoordinate2D(latitude: 25.7240, longitude: 100.1510),
                    CLLocationCoordinate2D(latitude: 25.7660, longitude: 100.1430),
                    CLLocationCoordinate2D(latitude: 25.8100, longitude: 100.1450),
                    CLLocationCoordinate2D(latitude: 25.8520, longitude: 100.1610),
                    CLLocationCoordinate2D(latitude: 25.8850, longitude: 100.1880),
                    CLLocationCoordinate2D(latitude: 25.9130, longitude: 100.2360),
                    CLLocationCoordinate2D(latitude: 25.9180, longitude: 100.2540)
                ]
                : [],
            saveWarning: summaryWarning,
            canRetrySave: !ProcessInfo.processInfo.arguments.contains("-summarylost")
        )
    }

    var body: some View {
        RideSummaryView(route: route, checkpoints: checkpoints, summary: summary, onFinish: {}, onRetrySave: { false })
    }
}

/// 调试入口 -sharecard：直接渲染分享卡，方便检查 4:5 版式和轨迹
struct DebugRideShareCardLoader: View {
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Theme.lightField.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(18)
            } else {
                ProgressView()
            }
        }
        .task {
            // `-sharecardnotrack`：没有轨迹时卡面不留假线，只保留真实有值的指标。
            if ProcessInfo.processInfo.arguments.contains("-sharecardnotrack") {
                image = RideShareCardRenderer.image(
                    routeName: "长安街夜骑线",
                    dateText: "11月7日 14:55",
                    endpoints: "西单 → 建国门",
                    metrics: [("时长", "14 秒"), ("打卡", "3/3")],
                    unitPoints: [],
                    hasTrack: false
                )
                return
            }
            image = RideShareCardRenderer.image(
                // -longnames：长名字是分享卡最容易溢出的输入，卡面必须自己截断
                routeName: ProcessInfo.processInfo.arguments.contains("-longnames")
                    ? "大理古城到双廊的环洱海长距离耐力骑行挑战路线"
                    : "洱海环湖骑行",
                // 与 -summary 的示例同一趟骑行：时间、指标、轨迹走向都要一致，
                // 否则两张截图放在一起评审会以为分享卡画错了线。
                dateText: "11月5日 18:00",
                endpoints: "大理古城 → 双廊",
                metrics: [
                    ("里程", "42.1 km"),
                    ("时长", "2:08:00"),
                    ("均速", "19.7 km/h"),
                    ("爬升", "560 m")
                ],
                unitPoints: [
                    CGPoint(x: 0.13, y: 0.85),
                    CGPoint(x: 0.09, y: 0.68),
                    CGPoint(x: 0.16, y: 0.48),
                    CGPoint(x: 0.32, y: 0.36),
                    CGPoint(x: 0.52, y: 0.30),
                    CGPoint(x: 0.72, y: 0.23),
                    CGPoint(x: 0.86, y: 0.17),
                    CGPoint(x: 0.94, y: 0.13)
                ],
                hasTrack: true
            )
        }
    }
}


/// 调试入口(`-riding`):静态展示骑行中 HUD,不启动定位、不写骑行记录
struct DebugRideLoader: View {
    @Environment(AuthManager.self) private var auth
    var mapOnly: Bool = false
    var arrival: Bool = false
    @State private var route: Route?
    @State private var checkpoints: [Checkpoint] = []
    @State private var failed = false

    var body: some View {
        Group {
            if let route {
                if mapOnly {
                    MapSwitchView(route: route, checkpoints: checkpoints, ride: nil)
                } else {
                    RidingView(
                        route: route,
                        checkpoints: checkpoints,
                        vehicleId: nil,
                        vehicleName: "春风动力 800NK",
                        demo: true,
                        demoArrival: arrival
                    )
                }
            } else if failed {
                Text("路线加载失败")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let routes: [Route] = try await auth.client
                    .from("routes")
                    .select("*")
                    .limit(1)
                    .execute()
                    .value
                guard let first = routes.first else {
                    failed = true
                    return
                }
                let cps: [Checkpoint] = try await auth.client
                    .from("checkpoints")
                    .select("*")
                    .eq("route_id", value: first.id)
                    .order("seq", ascending: true)
                    .execute()
                    .value
                route = first
                checkpoints = cps
            } catch {
                failed = true
            }
        }
    }
}


/// 调试入口(`-recorddetail`):打开最近一条骑行记录的详情
struct DebugRecordDetailLoader: View {
    @Environment(AuthManager.self) private var auth
    @State private var store: RecordsStore?
    @State private var recordId: UUID?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let store, let recordId {
                    RecordDetailView(store: store, recordId: recordId)
                } else if isLoading {
                    ProgressView()
                } else {
                    DesignEmptyState(
                        icon: "clock.arrow.circlepath",
                        title: "还没有骑行记录",
                        message: "完成第一次骑行后，记录会出现在这里"
                    )
                }
            }
        }
        .task {
            defer { isLoading = false }
            guard let uid = auth.user?.id else { return }
            let service = RecordsStore(client: auth.client, userId: uid)
            await service.load()
            store = service
            recordId = service.records.first?.id
            if let id = recordId,
               ProcessInfo.processInfo.arguments.contains("-recordtrackpreview") {
                service.applyDebugTrackPreview(for: id)
            } else if let id = recordId,
                      ProcessInfo.processInfo.arguments.contains("-recordtracksample") {
                service.applyDebugTrack(for: id)
            }
        }
    }
}


/// 调试入口：添加车辆 / 车型选择器(需先加载品牌车型目录)
struct DebugGarageFlowLoader: View {
    enum Mode { case addVehicle, picker, modelPicker, addVehicleSelected }
    let mode: Mode
    @Environment(AuthManager.self) private var auth
    @State private var garage: GarageService?
    @State private var modelId: Int?

    var body: some View {
        Group {
            if let garage {
                switch mode {
                case .addVehicle:
                    AddVehicleFlowView(garage: garage)
                case .addVehicleSelected:
                    AddVehicleFlowView(
                        garage: garage,
                        preselectedModelIds: garage.modelsByBrand.values.flatMap { $0 }.prefix(2).map { $0.id }
                    )
                case .picker:
                    NavigationStack {
                        VehiclePickerView(garage: garage, selectedModelId: $modelId)
                    }
                case .modelPicker:
                    NavigationStack {
                        VehiclePickerView(
                            garage: garage,
                            selectedModelId: $modelId,
                            // 目录里的车型按品牌懒加载，modelsByBrand 此时可能还是空的，
                            // 用第一个品牌 id 当入口，调试入口才能稳定落到车型页。
                            initialBrandId: garage.brands.first?.id,
                            // 调试「已添加」态：把已加载车型的第一辆当成已选
                            existingModelIds: Set((garage.modelsByBrand[garage.brands.first?.id ?? -1] ?? []).prefix(1).map { $0.id })
                        )
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            guard garage == nil else { return }
            let service = GarageService(client: auth.client)
            // 先加载目录再挂载视图：否则预选车型时目录还是空的
            await service.loadCatalog()
            garage = service
        }
    }
}

/// 调试入口(-departinfo)：单独渲染出发页的「骑行参考」面板，方便逐卡检查
struct DebugDepartInfoLoader: View {
    @Environment(AuthManager.self) private var auth
    @State private var route: Route?
    @State private var checkpoints: [Checkpoint] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let route {
                    RideInfoPanel(route: route, checkpoints: checkpoints)
                        .padding(.top, 80)
                } else {
                    ProgressView()
                        .padding(.top, 200)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color.white)
        .task {
            do {
                let routes: [Route] = try await auth.client
                    .from("routes")
                    .select("*")
                    .limit(1)
                    .execute()
                    .value
                guard let first = routes.first else { return }
                let cps: [Checkpoint] = try await auth.client
                    .from("checkpoints")
                    .select("*")
                    .eq("route_id", value: first.id)
                    .order("seq", ascending: true)
                    .execute()
                    .value
                checkpoints = cps
                route = first
            } catch {
                // 调试页保持空白即可
            }
        }
    }
}

/// 全屏深色页面(骑行 HUD)需要白字状态栏,但 preferredColorScheme 只认最外层,
/// 所以子页面把诉求压进这个栈,由 RootView 统一应用到窗口。
@Observable
final class ScreenAppearance {
    static let shared = ScreenAppearance()

    private(set) var stack: [ColorScheme] = []

    var colorScheme: ColorScheme { stack.last ?? .light }

    func push(_ scheme: ColorScheme) {
        stack.append(scheme)
    }

    func pop(_ scheme: ColorScheme) {
        if let index = stack.lastIndex(of: scheme) {
            stack.remove(at: index)
        }
    }
}
