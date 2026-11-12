import SwiftUI
import PhotosUI

/// 添加车辆全屏流程(Figma「添加车辆」135:574 1:1 还原)
/// 页面：返回 + 添加车辆标题 + 选择品牌及车辆副标题 + 车辆卡片(您已选择/删除/照片区)+ 添加到车库
/// 点卡片 → push「筛选品牌」→「筛选车型」→ 选中后返回本页显示已选车辆
struct AddVehicleFlowView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let garage: GarageService
    /// 调试/预填：进入时默认选中的车型
    var preselectedModelIds: [Int] = []

    @State private var modelIds: [Int] = []
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var showPicker = false
    /// 选择器当前高亮(用于「已选」徽标，与 modelIds 分开，便于选择器内即时反馈)
    @State private var pickerSelection: Int?
    /// 每辆车单独的照片(按车型 id 暂存，保存时逐辆上传)
    @State private var photoData: [Int: Data] = [:]

    private var selectedModels: [VehicleModel] {
        garage.modelsByBrand.values.flatMap { $0 }.filter { modelIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 子页页头统一走 DesignPageHeader：手写 HStack 会把返回箭头推到 28pt、
                // 标题推到 56pt，从本页跳回「车辆」时标题会横跳 8pt。
                DesignPageHeader(title: "添加车辆", onBack: { dismiss() })

                GeometryReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        // 空态时不要再摆一行同名入口：页面正中已经有主按钮，
                        // 两个「选择品牌及车辆」会让用户不知道点哪个。
                        // 选中之后这一行才出现，承担「继续添加车型 / 已选 N 辆」。
                        if !selectedModels.isEmpty {
                            pickerRow
                        }

                        if selectedModels.isEmpty {
                            // 空态在整个可选区域里垂直居中，不要贴着车型库入口、
                            // 把下面三分之二留成一大片空白。
                            emptyHint
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: max(0, proxy.size.height - 32), alignment: .center)
                        } else {
                            ForEach(Array(selectedModels.enumerated()), id: \.element.id) { index, model in
                                selectedCard(model, showsDivider: index < selectedModels.count - 1)
                                    .motionAppear(delay: 0.06 + Double(index) * Motion.stagger)
                            }
                        }

                        if let errorText {
                            Text(errorText)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.danger)
                                .padding(.leading, 2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    // 本页是 fullScreenCover，没有悬浮 Tab 栏；沿用 108pt 会让空态整体上浮 50pt 以上
                    .padding(.bottom, 32)
                }
                }
            }
            .background(Color.white)
            .ignoresSafeArea(edges: .top)
            // 主行动恒定在底部：空态是「选择品牌及车辆」，选好之后同一位置变成
            // 「添加到车库」。原来空态的按钮跟着空文案浮在页面中段，选完车型返回
            // 后按钮突然掉到底部，同一颗按钮两次出现的位置差 300pt 以上。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .pageMark(24)
            .task {
                if modelIds.isEmpty, !preselectedModelIds.isEmpty {
                    modelIds = preselectedModelIds
                }
            }
            .navigationDestination(isPresented: $showPicker) {
                VehiclePickerView(garage: garage, selectedModelId: pickerModelId, existingModelIds: Set(modelIds))
            }
        }
    }

    // MARK: - 车型库入口

    private var pickerRow: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedModels.isEmpty ? "选择品牌及车辆" : "继续添加车型")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if selectedModels.isEmpty {
                        Text("从车型库挑选，可一次添加多辆")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 8)
                if !selectedModels.isEmpty {
                    // 只写「2 辆」挂在「继续添加车型」右侧会被读成「还能加 2 辆」，
                    // 加上「已选」才是这一行真正要说的数量
                    Text("已选 \(selectedModels.count) 辆")
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            .padding(.horizontal, 0)
            .frame(height: selectedModels.isEmpty ? 64 : 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    /// 空态本身就是入口：整块可点，并给一颗黑色主按钮。
    /// 之前只有顶部一行「选择品牌及车辆」能点，页面正中是一大片不可交互的空白，
    /// 第一次进来的用户会以为这页坏了（也正是「按钮点不动」那类反馈的来源）。
    private var emptyHint: some View {
        // 主行动已经挂在底部 safeAreaInset，这里只留「图标 + 一句说明」，
        // 与车库空态分工一致，页面中段不再出现第二颗同样的按钮。
        DesignEmptyState(
            icon: Theme.vehicleSymbol,
            title: "还没有选择车型",
            message: "从车型库挑选，可一次添加多辆"
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - 已选车辆卡片

    /// 已选车型:紧凑行卡(缩略图 + 品牌/车型 + 移除),避免大图占位造成的大面积空白
    private func selectedCard(_ model: VehicleModel, showsDivider: Bool = true) -> some View {
        let brandName = brandText(for: model)
        // 操作区改成两段：照片入口跟着车型走（在名字下面），移除收到右上角。
        // 原来两个操作并排在名字右侧，和车型信息抢一条水平线，读起来很挤。
        return HStack(alignment: .top, spacing: 12) {
            ModelThumbnail(model: model, size: 68)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if !brandName.isEmpty {
                    Text(brandName)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityHidden(true)
                }
                Text(displayName(model))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .accessibilityLabel("\(brandName) \(displayName(model))")

                SelectedVehiclePhotoButton(data: Binding(
                    get: { photoData[model.id] },
                    set: { photoData[model.id] = $0 }
                ), itemName: "\(brandName) \(displayName(model))")
                .padding(.top, 2)
            }

            Spacer(minLength: 8)

            Button {
                withAnimation { modelIds.removeAll { $0 == model.id } }
            } label: {
                Text("移除")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.danger)
                    .frame(minWidth: 44)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("移除 \(displayName(model))")
        }
        .padding(.vertical, 12)
        // 最后一张不再画分隔线：否则列表底部会多出一条悬空的横线
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        }
    }

    /// 卡片里已有品牌名，车型名去掉重复的品牌前缀
    private func displayName(_ model: VehicleModel) -> String {
        model.displayName(removingBrand: garage.brands.first { $0.id == model.brandId })
    }

    /// 品牌名与「我的车辆」「车库首页」同一口径：优先中文，无中文时才回退英文。
    /// 不再拼「中文 ENGLISH」也不做全大写——11pt 大写在中文界面里像装饰性标签。
    private func brandText(for model: VehicleModel) -> String {
        guard garage.brands.contains(where: { $0.id == model.brandId }) else { return "" }
        return garage.displayBrandName(for: model.brandId)
    }

    // MARK: - 底部

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                if selectedModels.isEmpty {
                    showPicker = true
                } else {
                    Task { await save() }
                }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text(selectedModels.isEmpty ? "选择品牌及车辆" : "添加到车库")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(isSaving ? 0.6 : 1)
            }
            .buttonStyle(SolidPressStyle())
            .allowsHitTesting(!isSaving)
            .accessibilityHint(selectedModels.isEmpty ? "打开车型库挑选车辆" : "")
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        // 车型库可以滚动：统一用 wellwayBottomBar()，切断处才有 18pt 渐变
        .wellwayBottomBar()
    }

    // MARK: - 保存

    private func save() async {
        // 会话失效时之前是静默 return：按钮点下去毫无反应，用户只会以为 App 卡住。
        guard let userId = auth.user?.id else {
            errorText = "登录状态已失效，请重新登录后再添加车辆"
            return
        }
        guard !selectedModels.isEmpty else { return }
        isSaving = true
        errorText = nil
        garage.errorMessage = nil
        let total = selectedModels.count
        var success = 0
        var successfulIds = Set<Int>()
        var lastCreatedId: UUID?
        var failureMessage: String?
        for model in selectedModels {
            var photoUrl: String?
            if let data = photoData[model.id] {
                guard let path = await garage.uploadPhoto(data, userId: userId) else {
                    if failureMessage == nil {
                        failureMessage = garage.errorMessage ?? "照片上传失败，请重试"
                    }
                    continue
                }
                photoUrl = path
            }
            let vehicle = VehicleInsert(
                userId: userId,
                brandId: model.brandId,
                modelId: model.id,
                nickname: nil,
                color: nil,
                photoUrl: photoUrl
            )
            if let created = await garage.addVehicle(vehicle) {
                success += 1
                successfulIds.insert(model.id)
                lastCreatedId = created.id
            } else if failureMessage == nil {
                failureMessage = garage.errorMessage ?? "添加失败，请重试"
            }
        }
        if success == total {
            // 保存成功到关闭之间保持「保存中」：中间还要重新拉一次车辆列表，
            // 提前恢复按钮会让用户在等待期间再次点按，把同一辆车重复写进车库。
            await garage.loadVehicles(userId: userId)
            if let lastCreatedId { garage.markJustAdded(lastCreatedId) }
            // 成功后立刻清空已选列表：即使关闭动画期间被再次点按，
            // save() 也会因为 selectedModels 为空直接返回，不会写出第二条重复车辆。
            modelIds.removeAll()
            photoData.removeAll()
            isSaving = false
            dismiss()
        } else if success > 0 {
            isSaving = false
            // 部分成功时不能直接关闭，否则用户会误以为所有车辆都已添加。
            // 已成功的车型从选择列表移除，避免重试时重复插入。
            await garage.loadVehicles(userId: userId)
            modelIds.removeAll { successfulIds.contains($0) }
            let failed = total - success
            let reason = failureMessage.map { "（\($0)）" } ?? ""
            errorText = "已添加 \(success) 辆，\(failed) 辆添加失败\(reason)。请重试剩余车辆。"
        } else {
            isSaving = false
            errorText = failureMessage ?? "添加失败，请重试"
        }
    }

    /// 供 picker 使用的绑定：选中后追加到列表并关闭选择器
    private var pickerModelId: Binding<Int?> {
        Binding(
            get: { pickerSelection },
            set: { newValue in
                pickerSelection = newValue
                if let newValue, !modelIds.contains(newValue) {
                    modelIds.append(newValue)
                }
            }
        )
    }
}

/// 已选车型行内的照片入口：未选时是相机占位，选了显示缩略图，点击可更换
private struct SelectedVehiclePhotoButton: View {
    @Binding var data: Data?
    var hasPhoto = false
    var itemName: String = ""

    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            Group {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        // 缩略图本身就是「再点可更换」的入口，加相机角标说明它可点
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 7, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .frame(width: 15, height: 15)
                                .background(Circle().fill(Color.black))
                                .offset(x: 4, y: 4)
                        }
                } else {
                    // 次级操作不该和车型名同样重：收成浅灰胶囊，行高也随之变紧
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 12, weight: .medium))
                        Text("添加照片")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Theme.lightField)
                    .clipShape(Capsule())
                    .fixedSize()
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle(scale: 0.96))
        .accessibilityLabel((data == nil ? "添加车辆照片" : "更换车辆照片") + (itemName.isEmpty ? "" : "，\(itemName)"))
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            Task {
                if let loaded = try? await newItem.loadTransferable(type: Data.self) {
                    data = loaded
                }
                item = nil
            }
        }
    }
}


