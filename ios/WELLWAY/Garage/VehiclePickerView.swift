import SwiftUI

/// 品牌/车型选择器：搜索 → 选品牌 → 选车型(类型/排量筛选)
/// 统一设计语言：白底、16 边距、分组卡 + 分隔线
struct VehiclePickerView: View {
    let garage: GarageService
    @Binding var selectedModelId: Int?
    var initialBrandId: Int? = nil
    /// 已经在「添加车辆」待添加列表里的车型 id。
    /// 再加一次不会产生任何变化（上层绑定会去重），所以这些行要标成「已添加」并禁止点按，
    /// 否则用户点了一辆已经加过的车，面板关掉、列表没变，读成「点了没反应」。
    var existingModelIds: Set<Int> = []
    @Environment(\.dismiss) private var dismiss

    @State private var selectedBrandId: Int?
    @State private var searchText = ""
    @State private var typeFilter = "全部"
    @State private var displacementFilter = "全部"
    @FocusState private var searchFocused: Bool
    @State private var showBrandRequested = false
    @State private var isSubmittingBrandRequest = false
    @State private var showBrandRequestFailed = false
    @State private var brandRequestErrorMessage = "请检查网络后重试"

    private let types = ["全部", "跑车", "街车", "踏板", "巡航", "复古", "ADV", "越野", "旅行", "MINI"]
    private let displacements = ["全部", "250cc以下", "250-500cc", "500cc以上"]

    private var filteredBrands: [Brand] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty { return garage.brands }
        let pinyinKeyword = keyword.lowercased().replacingOccurrences(of: " ", with: "")
        return garage.brands.filter {
            if $0.name.localizedCaseInsensitiveContains(keyword) { return true }
            if ($0.nameEn ?? "").localizedCaseInsensitiveContains(keyword) { return true }
            // 中文品牌名支持拼音全拼与首字母：输入 ben / bt 都能找到「本田」。
            // 品牌库有几百条，用户往往记得发音而不是准确汉字。
            let keys = Self.pinyinKeys($0.name)
            return keys.full.contains(pinyinKeyword) || keys.initials.contains(pinyinKeyword)
        }
    }

    /// 品牌名的拼音检索键（全拼 / 首字母），按名字缓存，避免每次输入都重新转换。
    private final class PinyinKeys: NSObject {
        let full: String
        let initials: String
        init(full: String, initials: String) {
            self.full = full
            self.initials = initials
        }
    }

    private static let pinyinCache = NSCache<NSString, PinyinKeys>()

    private static func pinyinKeys(_ name: String) -> (full: String, initials: String) {
        if let cached = pinyinCache.object(forKey: name as NSString) {
            return (cached.full, cached.initials)
        }
        let mutable = NSMutableString(string: name) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformMandarinLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripDiacritics, false)
        let syllables = (mutable as String)
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "'" })
            .map(String.init)
        let full = syllables.joined()
        let initials = syllables.compactMap(\.first).map(String.init).joined()
        let keys = PinyinKeys(full: full, initials: initials)
        pinyinCache.setObject(keys, forKey: name as NSString)
        return (full, initials)
    }

    private var modelsForBrand: [VehicleModel] {
        guard let brandId = selectedBrandId else { return [] }
        var list = garage.modelsByBrand[brandId] ?? []
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(keyword) }
        }
        if typeFilter != "全部" {
            list = list.filter { $0.modelType == typeFilter }
        }
        switch displacementFilter {
        case "250cc以下":
            list = list.filter { $0.displacementCc.map { $0 < 250 } ?? false }
        case "250-500cc":
            list = list.filter { $0.displacementCc.map { (250...500).contains($0) } ?? false }
        case "500cc以上":
            list = list.filter { $0.displacementCc.map { $0 > 500 } ?? false }
        default:
            break
        }
        return list.sorted { lhs, rhs in
            if (lhs.rating ?? 0) != (rhs.rating ?? 0) { return (lhs.rating ?? 0) > (rhs.rating ?? 0) }
            if lhs.sort != rhs.sort { return lhs.sort < rhs.sort }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            searchField

            if selectedBrandId == nil {
                if garage.isCatalogLoading && garage.brands.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 80)
                } else if filteredBrands.isEmpty {
                    if garage.brands.isEmpty, garage.errorMessage != nil {
                        catalogErrorView
                    } else {
                        noResultView(isBrandMode: true)
                    }
                } else {
                    brandList
                }
            } else {
                // 筛选条常驻：把「排量 500cc以上」筛到 0 条时，用户要能看见自己选了什么、
                // 就地改回来；整页换成空态会让人以为只能退回品牌列表。
                modelPane
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            if selectedBrandId == nil, let initialBrandId { selectedBrandId = initialBrandId }
            let args = ProcessInfo.processInfo.arguments
            if selectedBrandId == nil, args.contains("-pickerbrandempty") {
                searchText = "不存在的品牌"
            }
            if selectedBrandId == nil, args.contains("-pickerpinyin") {
                searchText = "ben"
            }
            if selectedBrandId != nil, args.contains("-pickermodelempty") {
                searchText = "不存在的车型"
            }
        }
        .modifier(KeyboardPageFix())
        .toolbar(.hidden, for: .navigationBar)
        .wellwayDialog(
            isPresented: $showBrandRequested,
            title: "已收到你的品牌建议",
            message: "车型库由官方维护，品牌加入后会第一时间出现在列表里",
            buttons: []
        )
        .wellwayDialog(
            isPresented: $showBrandRequestFailed,
            title: "品牌建议提交失败",
            message: brandRequestErrorMessage,
            buttons: [WellwayDialogButton(title: "知道了", role: .plain) {}]
        )
        .pageMark(
            selectedBrandId == nil
                ? (searchText.isEmpty ? 33 : 80)
                : (modelsForBrand.isEmpty ? 82 : 32)
        )
    }

    // MARK: - 头部

    private var headerBar: some View {
        HStack(spacing: 12) {
            Button {
                if selectedBrandId != nil {
                    selectedBrandId = nil
                    searchText = ""
                    typeFilter = "全部"
                    displacementFilter = "全部"
                } else {
                    dismiss()
                }
            } label: {
                BackChevron()
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconPressStyle())
            .accessibilityLabel("返回")

            Text(selectedBrandId == nil ? "选择品牌" : garage.brandName(for: selectedBrandId!))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 58)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField(selectedBrandId == nil ? "搜索品牌" : "搜索车型", text: $searchText)
                .font(.system(size: 14))
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.chevron)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    // MARK: - 品牌

    /// 搜索时只保留一个平铺结果；不搜索时按「常用品牌 / 全部品牌」分段。
    /// 品牌库有 300+ 条，26 个常用品牌本来就在 is_hot 里，平铺会让用户以为要一直往下翻。
    private var hotBrands: [Brand] { filteredBrands.filter(\.isHot) }
    private var otherBrands: [Brand] { filteredBrands.filter { !$0.isHot } }
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var brandList: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if isSearching {
                    brandGroup(filteredBrands, startIndex: 0)
                } else {
                    if !hotBrands.isEmpty {
                        brandSectionTitle("常用品牌", top: 4)
                        brandGroup(hotBrands, startIndex: 0)
                    }
                    if !otherBrands.isEmpty {
                        brandSectionTitle("全部品牌", top: hotBrands.isEmpty ? 4 : 24)
                        brandGroup(otherBrands, startIndex: hotBrands.count)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        // 车型目录有 24h 缓存：后台补了新车型 / 换了抠图，用户下拉就能拿到，
        // 不用杀进程等缓存过期。品牌页和车型页都要能刷新。
        .refreshable { await garage.loadCatalog(force: true) }
        .scrollDismissesKeyboard(.immediately)
    }

    private func brandSectionTitle(_ title: String, top: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, top)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    private func brandGroup(_ brands: [Brand], startIndex: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(brands.enumerated()), id: \.element.id) { index, brand in
                VStack(spacing: 0) {
                    brandRow(brand)
                    if index < brands.count - 1 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)
                    }
                }
                .motionAppear(delay: min(0.04 + Double(startIndex + index) * 0.02, 0.18))
            }
        }
    }
    private func brandRow(_ brand: Brand) -> some View {
        Button {
            selectedBrandId = brand.id
            searchText = ""
        } label: {
            HStack(spacing: 12) {
                Text(brand.name)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textPrimary)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            .frame(height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    // MARK: - 车型

    private var modelPane: some View {
        VStack(spacing: 0) {
            filterBar

            if modelsForBrand.isEmpty {
                // 空态不能放进 ScrollView：ScrollView 只按内容高度布局，
                // 主行动会贴在筛选条下面，下方留出一整屏空白。
                noResultView(isBrandMode: false)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(modelsForBrand.enumerated()), id: \.element.id) { index, model in
                            VStack(spacing: 0) {
                                modelRow(model)
                                if index < modelsForBrand.count - 1 {
                                    Rectangle()
                                        .fill(Theme.separator)
                                        .frame(height: 1)
                                        .padding(.leading, 102)
                                }
                            }
                            .motionAppear(delay: min(0.04 + Double(index) * 0.02, 0.18))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .refreshable { await garage.loadCatalog(force: true) }
                .scrollDismissesKeyboard(.immediately)
            }

            if selectedModelId != nil {
                confirmBar
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 20) {
            filterMenuChip("类型", selection: $typeFilter, options: types)
            filterMenuChip("排量", selection: $displacementFilter, options: displacements)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }

    private func filterMenuChip(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        let active = selection.wrappedValue != options.first
        return Menu {
            Picker(label, selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selection.wrappedValue == options.first ? label : selection.wrappedValue)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
    }

    /// 排量与指导价：有则拼成一行，用「·」分隔，与其它副标题写法一致
    private func modelMeta(_ model: VehicleModel) -> String {
        [model.displacementCc.map { "\($0)cc" },
         model.priceMin.map { "¥\($0.formatted())" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private func modelRow(_ model: VehicleModel) -> some View {
        let selected = selectedModelId == model.id
        let alreadyAdded = existingModelIds.contains(model.id)
        return Button {
            guard !alreadyAdded else { return }
            Haptics.selection()
            selectedModelId = model.id
        } label: {
            HStack(spacing: 12) {
                ModelThumbnail(model: model, size: 72)
                    .opacity(alreadyAdded ? 0.45 : 1)

                VStack(alignment: .leading, spacing: 5) {
                    Text(model.displayName(removingBrand: garage.brands.first { $0.id == model.brandId }))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(alreadyAdded ? Theme.textSecondary : Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(modelMeta(model))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 8)

                // 未选中也给出可点击的圆形提示，避免「多选」入口不可发现
                if alreadyAdded {
                    // 已经在待添加列表里：状态用文字说清楚，不再给一个按不动的圆圈
                    // 「已添加」会被读成已经进了车库；这里只是进了本页的待添加列表。
                    Text("已选")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                } else if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Circle()
                        .stroke(Theme.chevron, lineWidth: 1.5)
                        .frame(width: 20, height: 20)
                }
            }
            // 与搜索框、筛选条和车辆列表共用 20pt 页边距；
            // 这里不再加行内缩进，否则车型图会比其他列表标题明显右移。
            .frame(height: 92)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(alreadyAdded)
        .accessibilityHint(alreadyAdded ? "这辆车已在待添加列表里" : "")
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            Button {
                dismiss()
            } label: {
                Text("完成选择")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(
            Color.white.overlay(alignment: .top) {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
        )
    }

    // MARK: - 空态

    private var catalogErrorView: some View {
        stateView(
            title: "车型库加载失败",
            message: "请检查网络连接后重试",
            primaryTitle: "重新加载",
            primaryAction: { Task { await garage.loadCatalog() } }
        )
    }

    private func noResultView(isBrandMode: Bool) -> some View {
        if isBrandMode {
            let keyword = searchText.trimmingCharacters(in: .whitespaces)
            let canRequestBrand = !keyword.isEmpty
            return stateView(
                title: canRequestBrand ? "未找到相关结果" : "车型库暂时为空",
                message: canRequestBrand
                    ? "换个关键词，或直接提交这个品牌"
                    : "可以尝试重新加载车型库",
                primaryTitle: canRequestBrand ? "提交品牌建议" : "重新加载",
                primaryAction: {
                    guard canRequestBrand else {
                        Task { await garage.loadCatalog() }
                        return
                    }
                    guard !isSubmittingBrandRequest else { return }
                    isSubmittingBrandRequest = true
                    Task {
                        let ok = await garage.submitBrandRequest(name: keyword)
                        isSubmittingBrandRequest = false
                        if ok {
                            showBrandRequested = true
                        } else {
                            brandRequestErrorMessage = garage.errorMessage ?? "请检查网络后重试"
                            showBrandRequestFailed = true
                        }
                    }
                },
                primaryLoading: canRequestBrand && isSubmittingBrandRequest,
                primaryDisabled: canRequestBrand && isSubmittingBrandRequest,
                secondaryTitle: canRequestBrand ? "清除搜索" : nil,
                secondaryAction: canRequestBrand ? { searchText = "" } : nil
            )
        } else {
            return stateView(
                title: "没有符合条件的车型",
                message: "换个关键词，或清除筛选条件试试",
                primaryTitle: "清除筛选",
                primaryAction: {
                    searchText = ""
                    typeFilter = "全部"
                    displacementFilter = "全部"
                }
            )
        }
    }

    private func stateView(
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () -> Void,
        primaryLoading: Bool = false,
        primaryDisabled: Bool = false,
        secondaryTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button(action: primaryAction) {
                    Group {
                        if primaryLoading {
                            HStack(spacing: 8) {
                                ProgressView().tint(primaryDisabled ? Theme.listGray : .white)
                                Text("提交中…")
                            }
                        } else {
                            Text(primaryTitle)
                        }
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(primaryDisabled ? Theme.listGray : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(primaryDisabled ? Theme.lightField : Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())
                .allowsHitTesting(!primaryDisabled && !primaryLoading)

                if let secondaryTitle, let secondaryAction {
                    Button(action: secondaryAction) {
                        Text(secondaryTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 选择器入口：显示已选车型 + 打开选择器(编辑流程使用，sheet 承载)
struct VehicleSelectField: View {
    let garage: GarageService
    @Binding var modelId: Int?
    @State private var showPicker = false

    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                if let modelId, let model = garage.modelsByBrand.values.flatMap({ $0 }).first(where: { $0.id == modelId }) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.cleanedName)
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.textPrimary)
                        if let priceMin = model.priceMin {
                            Text("指导价 ¥\(priceMin.formatted())")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                } else {
                    Text("选择品牌及车辆")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .fullScreenCover(isPresented: $showPicker) {
            VehiclePickerView(garage: garage, selectedModelId: $modelId)
        }
    }
}

