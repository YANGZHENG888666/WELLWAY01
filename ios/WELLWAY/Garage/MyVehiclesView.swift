import SwiftUI
import UIKit
import PhotosUI

/// 我的车辆(第五个 tab → 我的车辆):只展示自己添加的车辆，
/// 车辆卡片样式与首页车库一致(品牌/车型/照片/默认徽标，无骑行统计),
/// 列表上下排列(无横滑);点击车辆弹出底部弹窗，仅「设为默认车辆 / 删除车辆」两个操作；
/// 右上角「+」添加车辆，永不被遮挡
struct MyVehiclesView: View {
    @Environment(AuthManager.self) private var auth
    @State private var garage: GarageService?
    /// 首次加载中：此时还没有车辆数据，不能直接显示「还没有车辆」空态
    @State private var isLoading = true
    @State private var actionVehicle: Vehicle?
    @State private var showAddVehicle = false
    @State private var editVehicle: Vehicle?
    @State private var pendingDeleteVehicle: Vehicle?
    @State private var showDeleteConfirm = false
    @State private var showActionFailed = false
    @State private var actionErrorMessage = "请检查网络后重试"
    @State private var isSettingDefault = false
    @State private var isDeletingVehicle = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                DesignPageHeader(title: "车辆")
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if let garage {
                            if garage.errorMessage != nil, garage.vehicles.isEmpty {
                                NetworkErrorView(message: garage.errorMessage) {
                                    Task { await reload(garage) }
                                }
                            } else if garage.vehicles.isEmpty {
                                if isLoading {
                                    loadingPlaceholder
                                } else {
                                    emptyState.containerRelativeFrame(.vertical)
                                }
                            } else {
                                if let message = garage.errorMessage {
                                    InlineRefreshNotice(message: "车辆刷新失败，当前显示上次数据") {
                                        Task { await reload(garage) }
                                    }
                                    .accessibilityHint(message)
                                }
                                VStack(spacing: 0) {
                                    ForEach(Array(garage.vehicles.enumerated()), id: \.element.id) { index, vehicle in
                                        // 用 Button 而不是 onTapGesture：按下要有底色反馈，
                                        // 旁白也能直接拿到按钮语义，不用再手补 traits。
                                        Button {
                                            actionVehicle = vehicle
                                        } label: {
                                            vehicleRow(garage, vehicle)
                                        }
                                        .buttonStyle(RowPressStyle())
                                        .accessibilityAction { actionVehicle = vehicle }
                                        .motionAppear(delay: 0.10 + Double(index) * Motion.stagger)
                                        if index < garage.vehicles.count - 1 {
                                            Rectangle()
                                                .fill(Theme.separator)
                                                .frame(height: 1)
                                                .padding(.leading, 102)
                                        }
                                    }
                                }
                            }
                        } else {
                            loadingPlaceholder
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                // 空态主行动与其他页面统一落在底部栏：留在说明文字下面会悬在页面上半段，
                // 下面空掉大半屏，读起来像没排完。
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if showsEmptyAddBar {
                        Button {
                            showAddVehicle = true
                        } label: {
                            Text("添加车辆")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
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
                .refreshable {
                if let garage {
                    await garage.loadCatalog(force: true)
                    await reload(garage)
                }
            }
            }
            .background(Color.white)
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .hidesAppTabBar()

            // 空态已有底部主行动，右上「+」只在有车时出现，避免同一动作重复两次。
            if !showsEmptyAddBar {
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
                .position(x: UIScreen.main.bounds.width - 28, y: 74)
            }

            if isDeletingVehicle {
                deletingVehicleOverlay
            }
        }
        .ignoresSafeArea(edges: .top)
        .wellwayDialog(
            isPresented: $showDeleteConfirm,
            title: "删除这辆车？",
            // 车名可能是「本田 CB400F」也可能是纯英文，用直角引号括起来，
            // 避免「移除 本田 CB400F」这种中文里夹半角空格的怪断句。
            message: pendingDeleteVehicle.map { "将从车库移除「\(vehicleDisplayName($0))」，骑行记录会保留。" } ?? "删除后该车辆信息将从车库移除。",
            buttons: [
                WellwayDialogButton(title: "删除车辆", role: .destructive) {
                    guard let vehicle = pendingDeleteVehicle else { return }
                    pendingDeleteVehicle = nil
                    Task { await delete(vehicle) }
                }
            ],
            onCancel: { pendingDeleteVehicle = nil }
        )
        .wellwayDialog(
            isPresented: $showActionFailed,
            title: "操作失败",
            message: actionErrorMessage,
            buttons: [WellwayDialogButton(title: "知道了", role: .plain) {}]
        )
        .fullScreenCover(isPresented: $showAddVehicle) {
            if let garage {
                AddVehicleFlowView(garage: garage)
            }
        }
        .sheet(item: $editVehicle) { vehicle in
            if let garage {
                VehiclePhotoSheet(garage: garage, vehicle: vehicle)
                    .fittedSheetHeight(fallback: 400, maxHeight: 620)
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(24)
                    .presentationBackground(Color.white)
            }
        }
        .sheet(item: $actionVehicle) { vehicle in
            if let garage {
                VehicleActionsSheet(
                    title: vehicleDisplayName(vehicle),
                    isDefault: isEffectiveDefault(garage, vehicle),
                    isWorking: isSettingDefault,
                    onSetDefault: {
                        guard !isSettingDefault else { return }
                        isSettingDefault = true
                        Task {
                            let ok = await setDefault(vehicle)
                            isSettingDefault = false
                            if ok {
                                NotificationCenter.default.post(name: .defaultVehicleChanged, object: nil)
                            }
                            actionVehicle = nil
                            if !ok {
                                actionErrorMessage = garage.errorMessage ?? "请检查网络后重试"
                                showActionFailed = true
                            }
                        }
                    },
                    onEdit: {
                        actionVehicle = nil
                        editVehicle = vehicle
                    },
                    onDelete: {
                        pendingDeleteVehicle = vehicle
                        actionVehicle = nil
                        showDeleteConfirm = true
                    }
                )
                // 只保留贴合内容的自定义高度：带 .medium 时系统会落到更高的
                // 默认 detent，纯文字操作表下方会空出一大块白。
                .presentationDetents([.height(isEffectiveDefault(garage, vehicle) ? 248 : 300)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(24)
                .presentationBackground(Color.white)
            }
        }
        .task {
            let service = garage ?? GarageService(client: auth.client)
            garage = service
            // 调试：-vehiclesample 注入样例车辆并跳过网络，避免旧登录会话覆盖样例
            if ProcessInfo.processInfo.arguments.contains("-vehiclesample") {
                service.applyDebugSample()
                isLoading = false
                // 调试：-vehicleactions 直接展开第一辆车的操作弹窗，不等目录网络请求
                if ProcessInfo.processInfo.arguments.contains("-vehicleactions") {
                    actionVehicle = service.vehicles.first
                }
                // 调试：-vehiclephoto 直接展开第一辆车的照片弹窗
                if ProcessInfo.processInfo.arguments.contains("-vehiclephoto") {
                    editVehicle = service.vehicles.first
                }
                if ProcessInfo.processInfo.arguments.contains("-vehicledeleting") {
                    // 调试入口：-vehicledeleting 停在删除中浮层，复核 12pt 圆角与遮罩
                    isDeletingVehicle = true
                    try? await Task.sleep(for: .seconds(25))
                    isDeletingVehicle = false
                }
                return
            }
            await service.loadCatalog()
            await reload(service)
            // session 刚启动时可能还没把 token 挂上请求(此时 RLS 会静默返回空列表且不报错),
            // 空结果再补一次，避免「我的车辆」偶发空白
            if service.vehicles.isEmpty, service.errorMessage == nil {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await reload(service)
            }
            isLoading = false
            // 调试：-vehiclephoto 直接展开第一辆车的照片弹窗
            if ProcessInfo.processInfo.arguments.contains("-vehiclephoto") {
                editVehicle = service.vehicles.first
            }
        }
    }

    private func reload(_ service: GarageService) async {
        if let uid = auth.user?.id {
            await service.loadVehicles(userId: uid)
        }
    }

    private func setDefault(_ vehicle: Vehicle) async -> Bool {
        guard let uid = auth.user?.id, let garage else { return false }
        return await garage.setDefault(id: vehicle.id, userId: uid)
    }

    private func vehicleDisplayName(_ vehicle: Vehicle) -> String {
        guard let garage else { return "这辆车" }
        let base = "\(brandText(garage, vehicle)) \(modelText(garage, vehicle))"
        if let ordinal = sameModelOrdinal(garage, vehicle) {
            return "\(base) · 第 \(ordinal) 辆"
        }
        return base
    }

    private func delete(_ vehicle: Vehicle) async {
        guard let garage, !isDeletingVehicle else { return }
        isDeletingVehicle = true
        let ok = await garage.deleteVehicle(id: vehicle.id)
        isDeletingVehicle = false
        if !ok {
            actionErrorMessage = garage.errorMessage ?? "请检查网络后重试"
            showActionFailed = true
        }
    }

    private var deletingVehicleOverlay: some View {
        ZStack {
            Color.black.opacity(0.14).ignoresSafeArea()
            HStack(spacing: 10) {
                ProgressView().tint(Theme.textPrimary)
                Text("正在删除车辆…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.10), radius: 18, y: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("正在删除车辆")
    }

    /// 只有一辆车时，「默认车辆」就是它本身，不需要再提供「设为默认」这个无意义操作
    private func isEffectiveDefault(_ garage: GarageService, _ vehicle: Vehicle) -> Bool {
        vehicle.isDefault || garage.vehicles.count == 1
    }

    /// 空状态：只放说明，主行动在底部栏
    private var emptyState: some View {
        DesignEmptyState(
            icon: Theme.vehicleSymbol,
            title: "还没有车辆",
            message: "添加你的第一辆车，开始记录骑行"
        )
        .frame(maxWidth: .infinity)
    }

    /// 只有「确实没有车、且不是网络错误、也不是加载中」才给底部「添加车辆」：
    /// 错误态自己带「重新加载」，两个主行动会互相抢。
    private var showsEmptyAddBar: Bool {
        guard !isLoading, let garage else { return false }
        return garage.vehicles.isEmpty && garage.errorMessage == nil
    }

    /// 车辆卡片：品牌/车型在左上，车图透明底，默认标记右上
    /// 首屏加载占位：按真实卡片骨架画，避免白屏 + 一个转圈
    private var loadingPlaceholder: some View {
        let block = Theme.cardStroke
        return VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 14) {
                    block
                        .frame(width: 88, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 7) {
                        block
                            .frame(width: 58, height: 10)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        block
                            .frame(width: 112, height: 17)
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    Spacer(minLength: 8)
                    block
                        .frame(width: 34, height: 20)
                        .clipShape(Capsule())
                }
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)

                if index < 3 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 1)
                        .padding(.leading, 102)
                }
            }
        }
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private func vehicleRow(_ garage: GarageService, _ vehicle: Vehicle) -> some View {
        let model = modelText(garage, vehicle)
        return HStack(spacing: 14) {
            Group {
                if let photo = garage.photos[vehicle.id] {
                    // 用户照片是矩形，车型图是透明抠图：照片单独收圆角，
                    // 否则列表里会出现一块直角灰块，和整页的圆角语言不一致。
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    ModelImage(model: garage.model(for: vehicle.modelId), artPadding: 2)
                }
            }
            // 底部对齐：不同车型图的宽高比不一样，居中摆放时轮胎落点参差不齐，
            // 整列看起来像随手贴上去的。统一压到同一条底线，行与行才成一条视觉基线。
            .frame(width: 88, height: 58, alignment: .bottom)

            VStack(alignment: .leading, spacing: 3) {
                Text(brandLine(garage, vehicle))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(model)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    // 「默认」原来是右对齐、跟着两行文字垂直居中，落点卡在品牌行和车型行中间，
                    // 和「第 N 辆」一人一个位置。改成和车型名同一行的徽标，扫列时一眼能对上。
                    if isEffectiveDefault(garage, vehicle) {
                        Text("默认")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(Theme.lightField)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .layoutPriority(1)
                    }
                    // 同款多辆才出现的区分标记：跟在车型名后，避免被读成品牌的一部分
                    if let ordinal = sameModelOrdinal(garage, vehicle) {
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
            }

            Spacer(minLength: 8)

            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                // 整行点按就打开这辆车的操作菜单：右侧 … 是唯一的可点暗示，
                // 用 chevron 那种浅灰会淡到看不见
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("点按可设为默认车辆或删除")
    }

    /// 品牌行：自定义昵称与车型重复时(如自动写入的「春风 800NK」)不再重复展示
    private func brandLine(_ garage: GarageService, _ vehicle: Vehicle) -> String {
        let brand = brandText(garage, vehicle)
        guard let raw = vehicle.nickname?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return brand }
        let model = modelText(garage, vehicle)
        let full = garage.modelName(for: vehicle.modelId)
        func normalize(_ value: String) -> String {
            value.replacingOccurrences(of: " ", with: "").lowercased()
        }
        let candidates = [model, full, "\(brand) \(model)", "\(brand) \(full)"].map(normalize)
        if candidates.contains(normalize(raw)) { return brand }
        return "\(brand) · \(raw)"
    }

    /// 同一车型有多辆时给出序号，避免完全同名车辆无法区分。
    private func sameModelOrdinal(_ garage: GarageService, _ vehicle: Vehicle) -> Int? {
        let sameModel = garage.vehicles.filter { $0.modelId == vehicle.modelId }
        guard sameModel.count > 1,
              let index = sameModel.firstIndex(where: { $0.id == vehicle.id }) else { return nil }
        return index + 1
    }

    /// 品牌展示：优先中文名（与车型库、车库首页一致），无中文时才回退英文名
    private func brandText(_ garage: GarageService, _ vehicle: Vehicle) -> String {
        garage.displayBrandName(for: vehicle.brandId)
    }

    /// 车型展示：去掉品牌前缀(与首页车库一致)
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
}

/// 车辆操作底部弹窗：从底部弹出，黑白风格，仅「设为默认车辆 / 删除车辆」两个操作 + 取消
private struct VehicleActionsSheet: View {
    let title: String
    let isDefault: Bool
    let isWorking: Bool
    let onSetDefault: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 16)

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                if isDefault {
                    Text("默认车辆")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)

            Divider()
            if !isDefault {
                Button(action: onSetDefault) {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView().tint(Theme.textPrimary)
                            Text("正在设为默认…")
                        } else {
                            Text("设为默认车辆")
                        }
                    }
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .buttonStyle(RowPressStyle())
                .allowsHitTesting(!isWorking)

                Divider()
            }
            Button(action: onEdit) {
                Text("更换照片")
                    .font(.system(size: 16))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(RowPressStyle())
            .allowsHitTesting(!isWorking)

            Divider()
            Button(action: onDelete) {
                Text("删除车辆")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.danger)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(RowPressStyle())
            .allowsHitTesting(!isWorking)

            Divider()
            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .buttonStyle(RowPressStyle())
            .allowsHitTesting(!isWorking)
            .opacity(isWorking ? 0.4 : 1)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }
}

/// 更换车辆照片：底部弹窗，只做一件事——选图并保存
private struct VehiclePhotoSheet: View {
    let garage: GarageService
    let vehicle: Vehicle

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var item: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 18)

            Text("车辆照片")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            preview
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

            if photoData == nil {
                PhotosPicker(selection: $item, matching: .images) {
                    Text(garage.photos[vehicle.id] == nil ? "从相册选择" : "重新选择")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SolidPressStyle())
                .allowsHitTesting(!isSaving)
                .opacity(isSaving ? 0.5 : 1)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            } else {
                PhotosPicker(selection: $item, matching: .images) {
                    Text("重新选择")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .allowsHitTesting(!isSaving)
                .opacity(isSaving ? 0.4 : 1)
                .padding(.horizontal, 20)

                Button {
                    Task { await save() }
                } label: {
                    Group {
                        if isSaving {
                            // 只转圈等于没说在做什么：补一句「正在保存」，
                            // 与意见反馈面板的「正在提交…」保持同一套等待反馈。
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("正在保存…")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(Color.white)
                            }
                        } else {
                            Text("保存")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())
                .allowsHitTesting(!isSaving)
                .accessibilityLabel(isSaving ? "正在保存车辆照片" : "保存车辆照片")
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.horizontal)
        .background(Color.white)
        .interactiveDismissDisabled(isSaving)
        // 调试：-vehiclephotopicked 预置一张图看「重新选择 / 保存」层级；
        // -vehiclephotosaving 同时进入上传中禁用态。
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-vehiclephotopicked") || args.contains("-vehiclephotosaving") {
                let size = CGSize(width: 600, height: 300)
                let renderer = UIGraphicsImageRenderer(size: size)
                photoData = renderer.image { context in
                    UIColor(white: 0.85, alpha: 1).setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                }.pngData()
            }
            if args.contains("-vehiclephotosaving") { isSaving = true }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let loaded = try? await newItem.loadTransferable(type: Data.self) {
                    photoData = loaded
                }
            }
        }
    }

    private var preview: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 208)
            .overlay {
                Group {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if let saved = garage.photos[vehicle.id] {
                        Image(uiImage: saved)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ModelImage(model: garage.model(for: vehicle.modelId), artPadding: 8)
                            .padding(10)
                    }
                }
            }
            .clipped()
            // 车型图是透明抠图：垫浅灰面板会在车周围留一圈灰底，和车库首页的透明底不一致。
            // 换成白底后透明图直接落在页面上；用户自选照片会铺满整个区域，不受影响。
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    private func save() async {
        guard let userId = auth.user?.id, let photoData else { return }
        isSaving = true
        errorText = nil
        guard let path = await garage.uploadPhoto(photoData, userId: userId) else {
            errorText = garage.errorMessage ?? "照片上传失败，请重试"
            isSaving = false
            return
        }
        await garage.updateVehicle(
            id: vehicle.id,
            nickname: vehicle.nickname,
            color: vehicle.color,
            photoUrl: path,
            isDefault: vehicle.isDefault
        )
        isSaving = false
        if let message = garage.errorMessage {
            errorText = message
            return
        }
        garage.clearPhotoCache(for: vehicle.id)
        await garage.loadVehicles(userId: userId)
        NotificationCenter.default.post(name: .vehiclePhotoChanged, object: vehicle.id)
        dismiss()
    }
}
