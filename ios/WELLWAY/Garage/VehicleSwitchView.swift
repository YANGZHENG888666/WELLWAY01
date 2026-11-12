import SwiftUI

/// 出发 → 更换车辆(从出发 Tab 的车辆卡片进入)
///
/// 与首页 Tab 的车库(P房：横滑车型卡 + 推荐路线 + 最近骑行 +「选择目的地」)刻意区分：
/// 目的地/路线在出发页已经选好，这里只做一件事——挑一辆车。
/// 竖排列表，点一下即切换默认车辆并返回出发页；左上角返回键带「出发」字样标明来源。
/// 每辆车显示该车的骑行记录(总里程 / 次数 / 时长),没有记录时给出提示。
struct VehicleSwitchView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var garage: GarageService?
    @State private var rideStatsByVehicle: [UUID: RideStats] = [:]
    @State private var rideStatsLoaded = false
    @State private var showAddVehicle = false
    /// 正在切换的车辆：切换期间禁用其它行，避免连点写库
    @State private var switchingId: UUID?
    @State private var showSwitchFailed = false
    @State private var switchErrorMessage = "请检查网络后重试"
    /// 首次加载完成前不显示「还没有车辆」,避免网络慢时闪假空态
    @State private var isInitialLoading = true

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if isInitialLoading {
                        vehicleListSkeleton
                    } else if let garage {
                            if garage.errorMessage != nil, garage.vehicles.isEmpty {
                                NetworkErrorView(message: garage.errorMessage) {
                                    Task { await reload(garage) }
                                }
                                .padding(.top, 40)
                            } else if garage.vehicles.isEmpty {
                                emptyState.containerRelativeFrame(.vertical)
                            } else {
                                ForEach(Array(garage.vehicles.enumerated()), id: \.element.id) { index, vehicle in
                                    vehicleRow(garage, vehicle)
                                        .motionAppear(delay: 0.06 + Double(index) * Motion.stagger)
                                    if index < garage.vehicles.count - 1 {
                                        Rectangle()
                                            .fill(Theme.separator)
                                            .frame(height: 1)
                                            .padding(.leading, 116)
                                    }
                                }
                            }
                    } else {
                        vehicleListSkeleton
                    }

                    Spacer(minLength: 32)
                }
            }
            // 空态的主行动和其他页面一样落在底部栏：留在说明文字下面会停在屏幕上半段，
            // 下面空掉大半屏，整页读起来像没排完。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsEmptyAddBar {
                    Button {
                        showAddVehicle = true
                    } label: {
                        Text("添加车辆")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(SolidPressStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                    .wellwayBottomBar()
                }
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .fullScreenCover(isPresented: $showAddVehicle) {
            if let garage {
                AddVehicleFlowView(garage: garage)
            }
        }
        .onChange(of: showAddVehicle) { _, presented in
            guard !presented, let garage else { return }
            Task { await reload(garage) }
        }
        .wellwayDialog(
            isPresented: $showSwitchFailed,
            title: "切换失败",
            message: switchErrorMessage,
            buttons: [WellwayDialogButton(title: "知道了", role: .plain) {}]
        )
        .task {
            let service = garage ?? GarageService(client: auth.client)
            garage = service
            // 选车首屏只依赖车辆列表；目录和统计并行加载，
            // 不能让上千条车型目录阻塞用户看到自己的车辆。
            async let catalog: Void = service.loadCatalog()
            async let stats: Void = loadRideStats(service)
            if let uid = auth.user?.id {
                await service.loadVehicles(userId: uid)
            }
            isInitialLoading = false
            _ = await (catalog, stats)
        }
    }

    // MARK: - 头部(返回箭头 + 「出发」,标注返回目标页)

    /// 一辆车都没有：头部改用「添加车辆」，避免「更换」却无从换起
    private var hasNoVehicles: Bool {
        garage?.vehicles.isEmpty ?? false
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 二级页统一用 DesignPageHeader：返回箭头 44pt 热区、标题 18pt。
            // 之前这里是「← 出发 + 26pt 大标题」，全站其它二级页只认一套页头。
            ZStack(alignment: .topTrailing) {
                DesignPageHeader(
                    title: hasNoVehicles ? "添加车辆" : "更换车辆",
                    onBack: { dismiss() }
                )
                if !hasNoVehicles {
                    Button {
                        showAddVehicle = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(.black)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(IconPressStyle())
                    .accessibilityLabel("添加车辆")
                    .padding(.trailing, 16)
                    .offset(y: 52)
                }
            }

            // 空态卡片已经写了「还没有车辆」，这里不再重复一遍
            if !hasNoVehicles {
                // 点一下就会写 is_default 并返回，不是一次性选择；
                // 文案要说清「默认」这件事，否则用户以为下一趟会自己切回来。
                Text("选择后作为出发页的默认车辆")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
                    // 紧贴标题下方，左边线跟标题文字（48pt）对齐，不跟正文网格
                    .padding(.leading, 48)
                    .padding(.trailing, 20)
                    .padding(.bottom, 12)
            }
        }
        .background(Color.white)
    }

    /// 车辆列表首次加载骨架：与真实行卡同构
    private var vehicleListSkeleton: some View {
        let block = Theme.cardStroke
        return VStack(spacing: 0) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 12) {
                    block
                        .frame(width: 84, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 8) {
                        block.frame(width: 58, height: 11).clipShape(Capsule())
                        block.frame(width: 118, height: 17).clipShape(Capsule())
                        block.frame(width: 168, height: 11).clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 20)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 车辆行

    private func vehicleRow(_ garage: GarageService, _ vehicle: Vehicle) -> some View {
        let stats = rideStatsLoaded ? rideStatsByVehicle[vehicle.id] ?? RideStats() : nil
        let isCurrent = vehicle.isDefault || garage.vehicles.count == 1
        let isSwitching = switchingId == vehicle.id

        return Button {
            guard switchingId == nil else { return }
            if isCurrent {
                dismiss()
            } else {
                Task { await select(vehicle) }
            }
        } label: {
            HStack(spacing: 12) {
                thumbnail(garage, vehicle)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(brandLine(garage, vehicle))
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                            HStack(spacing: 6) {
                                Text(modelText(garage, vehicle))
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                                    .lineLimit(1)
                                if let ordinal = sameModelOrdinal(garage, vehicle) {
                                    Text("第 \(ordinal) 辆")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(Theme.textSecondary)
                                        .padding(.horizontal, 5)
                                        .frame(height: 16)
                                        .background(Theme.lightField)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                        .layoutPriority(1)
                                }
                            }
                        }

                        Spacer(minLength: 0)
                        selectionMark(isCurrent: isCurrent, isSwitching: isSwitching)
                    }

                    // 骑行记录整行铺在文字列下面，不与右侧标记抢宽度(否则会被挤到省略号)
                    rideStatsLine(stats)
                }
                // 统一文字列高度并垂直居中：没有骑行统计的行只剩品牌 + 车型两行，
                // 顶部对齐会让文字浮在行首、下方空出一截；居中后两种行都和车图对齐。
                .frame(height: 60, alignment: .leading)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RowPressStyle())
        .disabled(switchingId != nil)
        .accessibilityHint(isCurrent ? "当前默认车辆" : "点按设为默认车辆")
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func selectionMark(isCurrent: Bool, isSwitching: Bool) -> some View {
        if isSwitching {
            ProgressView()
                .scaleEffect(0.8)
        } else if isCurrent {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("当前车辆")
        } else {
            // 点按整行即切换并返回，是「立即生效的选择」而不是待提交的单选，
            // 未选中行留空即可；一圈空心圆会让人以为还要再点一次确认。
            Color.clear
                .frame(width: 44, height: 44)
        }
    }

    private func thumbnail(_ garage: GarageService, _ vehicle: Vehicle) -> some View {
        Group {
            if let photo = garage.photos[vehicle.id] {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                // 没自拍照片：车型库真车图(透明抠图，不垫灰底) > 分类插画
                // 统一内边距，避免不同源图的透明留白导致车辆视觉大小忽大忽小
                ModelImage(model: garage.model(for: vehicle.modelId), artPadding: 4)
                    .padding(.horizontal, 2)
            }
        }
        .frame(width: 84, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// 空状态：还没有车辆 —— 直接添加，不引导去首页车库
    private var emptyState: some View {
        DesignEmptyState(
            icon: Theme.vehicleSymbol,
            title: "还没有车辆",
            message: "添加后，骑行记录与里程会关联到这辆车"
        )
        .frame(maxWidth: .infinity)
    }

    /// 空态且不是网络错误时才给底部「添加车辆」：错误态自己带重试，不能出现两个主行动
    private var showsEmptyAddBar: Bool {
        guard !isInitialLoading, let garage else { return false }
        return garage.vehicles.isEmpty && garage.errorMessage == nil
    }

    // MARK: - 数据

    private func reload(_ service: GarageService) async {
        guard let uid = auth.user?.id else { return }
        async let vehicles: Void = service.loadVehicles(userId: uid)
        async let stats: Void = loadRideStats(service)
        _ = await (vehicles, stats)
    }

    private func loadRideStats(_ service: GarageService) async {
        guard let uid = auth.user?.id else { return }
        if let stats = await service.loadRideStats(userId: uid) {
            rideStatsByVehicle = stats
            rideStatsLoaded = true
        }
    }

    /// 切换默认车辆 → 通知出发页刷新 → 返回出发页
    private func select(_ vehicle: Vehicle) async {
        guard let uid = auth.user?.id, let garage else { return }
        switchingId = vehicle.id
        let switched = await garage.setDefault(id: vehicle.id, userId: uid)
        switchingId = nil
        guard switched else {
            switchErrorMessage = garage.errorMessage ?? "请检查网络后重试"
            showSwitchFailed = true
            return
        }
        NotificationCenter.default.post(name: .defaultVehicleChanged, object: nil)
        dismiss()
    }

    // MARK: - 展示文案(与车库首页一致：品牌英文名 / 去掉品牌前缀的车型)

    private func brandText(_ garage: GarageService, _ vehicle: Vehicle) -> String {
        garage.displayBrandName(for: vehicle.brandId)
    }

    private func brandLine(_ garage: GarageService, _ vehicle: Vehicle) -> String {
        brandText(garage, vehicle)
    }

    /// 同一车型有多辆时给出序号（只在车型名后显示小标记）
    private func sameModelOrdinal(_ garage: GarageService, _ vehicle: Vehicle) -> Int? {
        let sameModel = garage.vehicles.filter { $0.modelId == vehicle.modelId }
        guard sameModel.count > 1,
              let index = sameModel.firstIndex(where: { $0.id == vehicle.id }) else { return nil }
        return index + 1
    }

    private func modelText(_ garage: GarageService, _ vehicle: Vehicle) -> String {
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

    /// 该车骑行记录：总里程 / 骑行次数 / 累计时长(与车库首页同一口径)
    /// 用单个 Text 拼接：多个 Text 放进 HStack 会被逐段压缩成省略号。
    /// 没有记录时整行不出现：一屏八九辆车每辆都写「还没有骑行记录」，
    /// 读到的全是同一句否定，既没有信息量又显得列表空。行高由外层固定 60pt
    /// 文字列兜住，去掉占位不会让列表忽高忽低。
    @ViewBuilder
    private func rideStatsLine(_ stats: RideStats?) -> some View {
        if let text = rideStatsText(stats) {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func rideStatsText(_ stats: RideStats?) -> String? {
        guard let stats, stats.rideCount > 0 else { return nil }
        let duration: String
        if stats.totalSeconds < 60 {
            duration = "\(stats.totalSeconds) 秒"
        } else if stats.totalSeconds < 3_600 {
            duration = "\(stats.totalSeconds / 60) 分钟"
        } else {
            duration = String(format: "%.1f 小时", Double(stats.totalSeconds) / 3_600)
        }
        var parts: [String] = []
        if stats.totalKm >= 0.05 {
            parts.append(String(format: "总里程 %.1f km", stats.totalKm))
        }
        parts.append("骑行 \(stats.rideCount) 次")
        parts.append("累计 \(duration)")
        return parts.joined(separator: " · ")
    }
}

