import SwiftUI
import MapKit
import UIKit
import CoreImage

/// 路线列表(Figma「路线列表-卡片模式」/「路线列表-列表模式」/「搜索无结果」)
/// 统一白色主题：白底 + 白色圆角卡片(深色地图预览 + 白色轨迹 + 快慢翻滚动效)
/// 卡片模式：纵向卡片流，向上滑动时卡片收缩淡出；列表模式：搜索框 + 省份/城市/难度/里程筛选
struct RoutesView: View {
    @Environment(AuthManager.self) private var auth
    /// 以 sheet 弹出时传入，用于显示右上角关闭按钮
    var onClose: (() -> Void)?

    @State private var routes: [Route] = []
    @State private var checkpointsByRoute: [Int: [Checkpoint]] = [:]
    @State private var ridersByRoute: [Int: Int] = [:]
    @State private var ridersLoaded = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// 路线本体已加载、仅打卡点失败时单独提示，不误报成「整页刷新失败」
    @State private var checkpointWarning: String?
    /// 折叠详情「添加到出发页」直接弹出的全屏路线图
    @State private var fullscreenRoute: Route?
    /// 折叠卡内的路线若缺少起终点坐标，明确提示并阻止写入出发页
    @State private var showRouteCoordinatesUnavailable = false

    @State private var searchText = ""
    @State private var difficultyFilter = "全部"
    @State private var provinceFilter = "全部"
    @State private var cityFilter = "全部"
    @State private var distanceFilter = "不限"
    @State private var favorites: FavoritesStore?
    @State private var favoritesOnly = false
    /// 全国 34 个省级行政区及对应地级市(筛选选项，与路线数据无关)
    private let regions: [(name: String, cities: [String])] = [
        ("北京", ["北京市"]),
        ("天津", ["天津市"]),
        ("河北", ["石家庄市", "唐山市", "秦皇岛市", "邯郸市", "邢台市", "保定市", "张家口市", "承德市", "沧州市", "廊坊市", "衡水市"]),
        ("山西", ["太原市", "大同市", "阳泉市", "长治市", "晋城市", "朔州市", "晋中市", "运城市", "忻州市", "临汾市", "吕梁市"]),
        ("内蒙古", ["呼和浩特市", "包头市", "乌海市", "赤峰市", "通辽市", "鄂尔多斯市", "呼伦贝尔市", "巴彦淖尔市", "乌兰察布市", "兴安盟", "锡林郭勒盟", "阿拉善盟"]),
        ("辽宁", ["沈阳市", "大连市", "鞍山市", "抚顺市", "本溪市", "丹东市", "锦州市", "营口市", "阜新市", "辽阳市", "盘锦市", "铁岭市", "朝阳市", "葫芦岛市"]),
        ("吉林", ["长春市", "吉林市", "四平市", "辽源市", "通化市", "白山市", "松原市", "白城市", "延边朝鲜族自治州"]),
        ("黑龙江", ["哈尔滨市", "齐齐哈尔市", "鸡西市", "鹤岗市", "双鸭山市", "大庆市", "伊春市", "佳木斯市", "七台河市", "牡丹江市", "黑河市", "绥化市", "大兴安岭地区"]),
        ("上海", ["上海市"]),
        ("江苏", ["南京市", "无锡市", "徐州市", "常州市", "苏州市", "南通市", "连云港市", "淮安市", "盐城市", "扬州市", "镇江市", "泰州市", "宿迁市"]),
        ("浙江", ["杭州市", "宁波市", "温州市", "嘉兴市", "湖州市", "绍兴市", "金华市", "衢州市", "舟山市", "台州市", "丽水市"]),
        ("安徽", ["合肥市", "芜湖市", "蚌埠市", "淮南市", "马鞍山市", "淮北市", "铜陵市", "安庆市", "黄山市", "滁州市", "阜阳市", "宿州市", "六安市", "亳州市", "池州市", "宣城市"]),
        ("福建", ["福州市", "厦门市", "莆田市", "三明市", "泉州市", "漳州市", "南平市", "龙岩市", "宁德市"]),
        ("江西", ["南昌市", "景德镇市", "萍乡市", "九江市", "新余市", "鹰潭市", "赣州市", "吉安市", "宜春市", "抚州市", "上饶市"]),
        ("山东", ["济南市", "青岛市", "淄博市", "枣庄市", "东营市", "烟台市", "潍坊市", "济宁市", "泰安市", "威海市", "日照市", "临沂市", "德州市", "聊城市", "滨州市", "菏泽市"]),
        ("河南", ["郑州市", "开封市", "洛阳市", "平顶山市", "安阳市", "鹤壁市", "新乡市", "焦作市", "濮阳市", "许昌市", "漯河市", "三门峡市", "南阳市", "商丘市", "信阳市", "周口市", "驻马店市", "济源市"]),
        ("湖北", ["武汉市", "黄石市", "十堰市", "宜昌市", "襄阳市", "鄂州市", "荆门市", "孝感市", "荆州市", "黄冈市", "咸宁市", "随州市", "恩施土家族苗族自治州", "仙桃市", "潜江市", "天门市", "神农架林区"]),
        ("湖南", ["长沙市", "株洲市", "湘潭市", "衡阳市", "邵阳市", "岳阳市", "常德市", "张家界市", "益阳市", "郴州市", "永州市", "怀化市", "娄底市", "湘西土家族苗族自治州"]),
        ("广东", ["广州市", "韶关市", "深圳市", "珠海市", "汕头市", "佛山市", "江门市", "湛江市", "茂名市", "肇庆市", "惠州市", "梅州市", "汕尾市", "河源市", "阳江市", "清远市", "东莞市", "中山市", "潮州市", "揭阳市", "云浮市"]),
        ("广西", ["南宁市", "柳州市", "桂林市", "梧州市", "北海市", "防城港市", "钦州市", "贵港市", "玉林市", "百色市", "贺州市", "河池市", "来宾市", "崇左市"]),
        ("海南", ["海口市", "三亚市", "三沙市", "儋州市"]),
        ("重庆", ["重庆市"]),
        ("四川", ["成都市", "自贡市", "攀枝花市", "泸州市", "德阳市", "绵阳市", "广元市", "遂宁市", "内江市", "乐山市", "南充市", "眉山市", "宜宾市", "广安市", "达州市", "雅安市", "巴中市", "资阳市", "阿坝藏族羌族自治州", "甘孜藏族自治州", "凉山彝族自治州"]),
        ("贵州", ["贵阳市", "六盘水市", "遵义市", "安顺市", "毕节市", "铜仁市", "黔西南布依族苗族自治州", "黔东南苗族侗族自治州", "黔南布依族苗族自治州"]),
        ("云南", ["昆明市", "曲靖市", "玉溪市", "保山市", "昭通市", "丽江市", "普洱市", "临沧市", "楚雄彝族自治州", "红河哈尼族彝族自治州", "文山壮族苗族自治州", "西双版纳傣族自治州", "大理白族自治州", "德宏傣族景颇族自治州", "怒江傈僳族自治州", "迪庆藏族自治州"]),
        ("西藏", ["拉萨市", "日喀则市", "昌都市", "林芝市", "山南市", "那曲市", "阿里地区"]),
        ("陕西", ["西安市", "铜川市", "宝鸡市", "咸阳市", "渭南市", "延安市", "汉中市", "榆林市", "安康市", "商洛市"]),
        ("甘肃", ["兰州市", "嘉峪关市", "金昌市", "白银市", "天水市", "武威市", "张掖市", "平凉市", "酒泉市", "庆阳市", "定西市", "陇南市", "临夏回族自治州", "甘南藏族自治州"]),
        ("青海", ["西宁市", "海东市", "海北藏族自治州", "黄南藏族自治州", "海南藏族自治州", "果洛藏族自治州", "玉树藏族自治州", "海西蒙古族藏族自治州"]),
        ("宁夏", ["银川市", "石嘴山市", "吴忠市", "固原市", "中卫市"]),
        ("新疆", ["乌鲁木齐市", "克拉玛依市", "吐鲁番市", "哈密市", "昌吉回族自治州", "博尔塔拉蒙古自治州", "巴音郭楞蒙古自治州", "阿克苏地区", "克孜勒苏柯尔克孜自治州", "喀什地区", "和田地区", "伊犁哈萨克自治州", "塔城地区", "阿勒泰地区"]),
        ("香港", ["香港"]),
        ("澳门", ["澳门"]),
        ("台湾", ["台北市", "新北市", "台中市", "台南市", "高雄市"])
    ]

    /// 地区筛选按钮文案：全部 / 省份 / 省份·城市
    private var regionDisplay: String {
        if provinceFilter == "全部" { return "地区 全部" }
        if cityFilter == "全部" { return provinceFilter }
        return "\(provinceFilter)·\(cityFilter)"
    }

    /// 路线库里的城市名通常不带「市」，筛选器来自行政区划表则带「市」。
    /// 只统一末尾这个行政后缀，避免「北京市」永远匹配不到「北京」。
    private func normalizedRegionName(_ value: String?) -> String {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasSuffix("市") ? String(text.dropLast()) : text
    }

    private var filteredRoutes: [Route] {
        routes.filter { route in
            if favoritesOnly, favorites?.isFavorite(route.id) != true {
                return false
            }
            let matchesDifficulty = difficultyFilter == "全部" || route.difficulty == difficultyFilter
            let normalizedProvince = normalizedRegionName(provinceFilter)
            let normalizedCity = normalizedRegionName(cityFilter)
            let matchesProvince = provinceFilter == "全部"
                || normalizedRegionName(route.province) == normalizedProvince
                || (route.startName ?? "").hasPrefix(normalizedProvince)
                || (route.endName ?? "").hasPrefix(normalizedProvince)
            let matchesCity = cityFilter == "全部"
                || normalizedRegionName(route.city) == normalizedCity
                || (route.startName ?? "").contains(normalizedCity)
                || (route.endName ?? "").contains(normalizedCity)
            let km = Double(route.distanceM) / 1000
            let matchesDistance: Bool
            if distanceFilter == "不限" {
                matchesDistance = true
            } else {
                // 选项文案形如 "50 km 内"，直接取数字，新增档位不用再改这里
                let limit = Double(distanceFilter.filter(\.isNumber)) ?? .infinity
                matchesDistance = km <= limit
            }
            let keyword = searchText.trimmingCharacters(in: .whitespaces)
            // 搜索「北京市」也要能找到路线库里的「北京」。
            // 只输入「市」时归一化结果为空，不能因此匹配全部路线。
            let regionKeyword = normalizedRegionName(keyword)
            let matchesRegionKeyword = !regionKeyword.isEmpty
                && (normalizedRegionName(route.province).localizedCaseInsensitiveContains(regionKeyword)
                    || normalizedRegionName(route.city).localizedCaseInsensitiveContains(regionKeyword))
            let matchesKeyword = keyword.isEmpty
                || route.name.localizedCaseInsensitiveContains(keyword)
                || matchesRegionKeyword
                || (route.difficulty).localizedCaseInsensitiveContains(keyword)
                || (route.startName ?? "").localizedCaseInsensitiveContains(keyword)
                || (route.endName ?? "").localizedCaseInsensitiveContains(keyword)
            return matchesDifficulty && matchesProvince && matchesCity && matchesDistance && matchesKeyword
        }
    }

    /// 收藏为空与普通筛选无结果需要不同文案和出口，避免用户误以为路线库没有内容。
    private var hasKeyword: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasOnlyFavoriteFilter: Bool {
        favoritesOnly
            && !hasKeyword
            && difficultyFilter == "全部"
            && provinceFilter == "全部"
            && cityFilter == "全部"
            && distanceFilter == "不限"
    }

    private func resetRouteFilters() {
        searchText = ""
        difficultyFilter = "全部"
        provinceFilter = "全部"
        cityFilter = "全部"
        distanceFilter = "不限"
        favoritesOnly = false
    }

    /// 筛选无结果时把唯一出口固定在页底，和车库、换车、徽章、记录空态保持一致。
    private var showsFilteredEmptyAction: Bool {
        !isLoading && errorMessage == nil && !routes.isEmpty && filteredRoutes.isEmpty
    }

    private var filteredEmptyAction: some View {
        Button {
            resetRouteFilters()
        } label: {
            Text(hasOnlyFavoriteFilter ? "查看全部路线" : "清除筛选")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .accessibilityHint(hasOnlyFavoriteFilter ? "关闭收藏筛选并显示全部路线" : "清除搜索词和全部筛选条件")
    }

    /// 后台补了新路线时，空态必须能原地重新拉取；不能只让用户切 Tab 碰运气。
    private var showsRouteEmptyAction: Bool {
        !isLoading && errorMessage == nil && routes.isEmpty
    }

    private var routeEmptyAction: some View {
        Button {
            Task { await load() }
        } label: {
            Text("刷新路线")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .accessibilityHint("重新加载路线列表")
    }

    var body: some View {
        ZStack {
                // 统一白底
                Color.white
                    .ignoresSafeArea(edges: .all)

                VStack(spacing: 0) {
                    controls
                    cardContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                routeDestination(route)
            }
            .fullScreenCover(item: $fullscreenRoute) { route in
                RouteMapFullscreenView(
                    route: route,
                    checkpoints: checkpointsByRoute[route.id] ?? []
                )
            }
            .wellwayDialog(
                isPresented: $showRouteCoordinatesUnavailable,
                title: "路线坐标未就绪",
                message: "这条路线缺少起点或终点坐标，暂时无法添加到出发页。请稍后刷新路线再试。",
                buttons: [WellwayDialogButton(title: "知道了", role: .plain) {}]
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if showsFilteredEmptyAction {
                    filteredEmptyAction
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(Color.white)
                } else if showsRouteEmptyAction {
                    routeEmptyAction
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                        .background(Color.white)
                }
            }
            .task {
                if favorites == nil, let uid = auth.user?.id {
                    let store = FavoritesStore(client: auth.client, userId: uid)
                    favorites = store
                    await store.load()
                }
                await load()
            }
        .pageMark(
            errorMessage != nil ? 43
            : isLoading ? 63
            : filteredRoutes.isEmpty && !routes.isEmpty ? 36
            : 31
        )
    }

    /// 内容区：错误/加载/空态 / 卡片模式整屏卡片流 / 列表模式
    @ViewBuilder
    private var cardContent: some View {
        if let errorMessage, routes.isEmpty {
            NetworkErrorView(message: errorMessage) {
                Task { await load() }
            }
        } else if isLoading, routes.isEmpty {
            RouteSkeletonList(dark: false)
        } else if routes.isEmpty {
            VStack {
                Spacer(minLength: 0)
                DesignEmptyState(icon: "map", title: "暂无路线", message: "新路线正在准备中，稍后再来看看")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredRoutes.isEmpty {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                if hasOnlyFavoriteFilter {
                    DesignEmptyState(
                        icon: "star",
                        title: "还没有收藏路线",
                        message: "在路线详情点亮星标后，收藏的路线会显示在这里"
                    )
                } else {
                    DesignEmptyState(
                        icon: "line.3.horizontal.decrease.circle",
                        title: "没有符合筛选的路线",
                        message: hasKeyword ? "换个关键词，或清除筛选条件试试" : "调整筛选条件，或清除筛选后再看看"
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if errorMessage != nil {
                    InlineRefreshNotice(message: "路线刷新失败，当前显示上次数据") {
                        Task { await load() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                } else if checkpointWarning != nil {
                    InlineRefreshNotice(message: checkpointWarning ?? "路线坐标未更新") {
                        Task { await load() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                listContent
            }
        }
    }

    // MARK: - 顶部控件

    private var controls: some View {
        VStack(spacing: 10) {
            // 与出发、我的统一使用 compact 页头；选择目的地模式右侧补关闭按钮。
            ZStack(alignment: .topTrailing) {
                DesignPageHeader(
                    title: onClose == nil ? "路线" : "选择目的地",
                    showsBack: false,
                    compact: true
                )
                if onClose != nil {
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.black)
                            .frame(width: 30, height: 30)
                            .background(Theme.lightField)
                            .clipShape(Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle(scale: 0.94))
                    .accessibilityLabel("关闭")
                    .padding(.trailing, 16)
                    // 与标题同一条基线：直接居中在 48pt 页头里会低 12pt 以上
                    .offset(y: DesignPageHeader.compactTitleCenterY - 22)
                }
            }

            // 没有路线可筛时，搜索与筛选只会制造可点但不产生结果的控件。
            // 加载中也先不占位，等首批路线到达后一起出现，避免先亮后收的跳动。
            if !routes.isEmpty {
                searchField
                filterChips
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(Color.white)
    }

    /// 与车型库搜索框共用同一套参数：14pt 文字、8pt 图标间距、14pt 内边距、
    /// theme.textSecondary 图标。两处写不同(13pt / 6pt / listGray)时，
    /// 同样一个搜索框在路线页和选车页看起来是两个控件。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            TextField("搜索路线 / 城市", text: $searchText)
                .font(.system(size: 14))
                .autocorrectionDisabled()
                .foregroundStyle(Theme.ink)
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
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var filterChips: some View {
        // 地区筛选可能变成「内蒙古·呼和浩特市」这类长文案；
        // 固定 HStack 会把难度/里程挤到只剩省略号，改成横向滚动保留完整选项。
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                regionChip
                filterChip("难度", selection: $difficultyFilter, options: ["全部", "简单", "中等", "困难"])
                filterChip("里程", selection: $distanceFilter, options: ["不限", "20 km 内", "50 km 内", "100 km 内"])
                favoriteChip
            }
            .padding(.horizontal, 20)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// 地区筛选：下拉菜单(全部 + 34 省级，进入省份子菜单再选城市),纯文字无图标
    private var regionChip: some View {
        AccessibleFilterMenu(
            title: regionDisplay,
            accessibilityLabel: regionDisplay,
            accessibilityHint: "选择省份和城市",
            fontSize: 12,
            fontWeight: .bold,
            color: provinceFilter != "全部" ? Theme.textPrimary : Theme.textSecondary,
            menu: regionMenu
        )
        .frame(height: 44)
    }

    private var regionMenu: UIMenu {
        let all = UIAction(
            title: "全部",
            state: provinceFilter == "全部" ? .on : .off
        ) { _ in
            provinceFilter = "全部"
            cityFilter = "全部"
        }
        let provinces = regions.map { region in
            let allCities = UIAction(
                title: "全部城市",
                state: provinceFilter == region.name && cityFilter == "全部" ? .on : .off
            ) { _ in
                provinceFilter = region.name
                cityFilter = "全部"
            }
            let cities = region.cities.map { city in
                UIAction(
                    title: city,
                    state: provinceFilter == region.name && cityFilter == city ? .on : .off
                ) { _ in
                    provinceFilter = region.name
                    cityFilter = city
                }
            }
            return UIMenu(title: region.name, children: [allCities] + cities)
        }
        return UIMenu(children: [all] + provinces)
    }

    private var favoriteChip: some View {
        Button {
            favoritesOnly.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: favoritesOnly ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .bold))
                Text("收藏")
                    .font(.system(size: 12, weight: .bold))
            }
            .foregroundStyle(favoritesOnly ? Theme.textPrimary : Theme.textSecondary)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CardPressStyle(scale: 0.96))
        .accessibilityLabel("只看收藏路线")
        .accessibilityValue(favoritesOnly ? "已开启" : "已关闭")
        .accessibilityHint("显示或隐藏收藏的路线")
    }

    /// 把屏幕文案里的「20 km 内」换成读屏用的「20 公里内」，其余选项原样返回。
    private func spokenDistanceOption(_ option: String) -> String {
        option.replacingOccurrences(of: " km 内", with: " 公里内")
    }

    private func filterChip(_ label: String, selection: Binding<String>, options: [String]) -> some View {
        let active = selection.wrappedValue != options.first
        let actions = options.map { option in
            UIAction(
                title: "\(label) \(option)",
                state: option == selection.wrappedValue ? .on : .off
            ) { _ in
                selection.wrappedValue = option
            }
        }
        return AccessibleFilterMenu(
            title: "\(label) \(selection.wrappedValue)",
            accessibilityLabel: "\(label) \(spokenDistanceOption(selection.wrappedValue))",
            accessibilityHint: "筛选\(label)",
            fontSize: 12,
            fontWeight: .bold,
            color: active ? Theme.textPrimary : Theme.textSecondary,
            menu: UIMenu(children: actions)
        )
        .frame(height: 44)
    }


    /// 路线详情页
    private func routeDestination(_ route: Route) -> some View {
        RouteDetailView(
            route: route,
            checkpoints: checkpointsByRoute[route.id] ?? [],
            ridersCount: ridersByRoute[route.id] ?? 0,
            pageNumber: 83,
            pickDestinationMode: onClose != nil,
            favoritesStore: favorites
        )
    }

    // MARK: - 列表模式

    private var listContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredRoutes) { route in
                    NavigationLink(value: route) {
                        listRow(route)
                    }
                    // 路线卡是整屏最大的可点面：按下要有一点收缩，否则点下去没有回音
                    .buttonStyle(CardPressStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 120)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .modifier(RoutesBottomScrollEdgeEffect())
        .refreshable { await load() }
    }

    private func listRow(_ route: Route) -> some View {
        let checkpoints = checkpointsByRoute[route.id] ?? []
        return RouteListCard(
            route: route,
            checkpoints: checkpoints,
            subtitle: subtitleText(route),
            accessibilityLabel: accessibilityText(route),
            isFavorite: favorites?.isFavorite(route.id) == true
        )
    }

    /// 卡片副标题：省 · 市(两者相同时只显示一次),缺失时回退到起点/终点
    private func regionText(_ route: Route) -> String {
        let province = route.province?.trimmingCharacters(in: .whitespaces) ?? ""
        let city = route.city?.trimmingCharacters(in: .whitespaces) ?? ""
        if !province.isEmpty, !city.isEmpty {
            return province == city ? province : "\(province) · \(city)"
        }
        if !province.isEmpty { return province }
        if !city.isEmpty { return city }
        let start = route.startName ?? ""
        let end = route.endName ?? ""
        if !start.isEmpty, !end.isEmpty { return "\(start) → \(end)" }
        return ""
    }

    /// 卡片副标题：省市可能缺失，缺失时不能把「省市未填写」这种后台占位文案露给用户
    /// spoken == true 时用中文单位（读屏不能念成「k m」）；屏幕上一律 km，
    /// 与路线详情的「北京 · 12.6 km」保持一致。
    private func subtitleText(_ route: Route, spoken: Bool = false) -> String {
        let km = Double(route.distanceM) / 1000
        let value = km == km.rounded() ? String(format: "%.0f", km) : String(format: "%.1f", km)
        let distance = value + (spoken ? " 公里" : " km")
        return [regionText(route), distance, route.difficulty]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " · ")
    }

    private func accessibilityText(_ route: Route) -> String {
        let parts = [route.name, subtitleText(route, spoken: true)]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let favorite = favorites?.isFavorite(route.id) == true ? "，已收藏" : ""
        return parts.joined(separator: "，") + favorite
    }

    // MARK: - 文案

    private func metaText(_ route: Route) -> String {
        String(format: "%.1f km · 爬升 %d m · 难度 %@", Double(route.distanceM) / 1000, route.elevationM, route.difficulty)
    }

    private func listMetaText(_ route: Route) -> String {
        String(format: "%.1f km · 爬升 %d m", Double(route.distanceM) / 1000, route.elevationM)
    }

    /// 难度评级：简单 2 / 中等 3 / 困难 4(共 5 格，与设计稿难度文案一致)
    private func difficultyLevel(_ route: Route) -> Int {
        switch route.difficulty {
        case "简单": return 2
        case "中等": return 3
        case "困难": return 4
        default: return 2
        }
    }

    /// 出发建议：依据拥堵峰值时段给出提示(纯本地启发式，不依赖网络)
    private func departureSuggestion(for level: Int) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let isRushHour = (7...9).contains(hour) || (17...19).contains(hour)
        if level >= 2, isRushHour {
            return "当前正值高峰，建议错峰出发"
        }
        if level >= 2 {
            return "建议避开早晚高峰出发"
        }
        return "预估路况顺畅，请以实际道路为准"
    }

    private func heatText(_ route: Route) -> String {
        guard ridersLoaded else { return "骑手数据暂不可用" }
        let count = ridersByRoute[route.id] ?? 0
        return count > 0 ? "今天有 \(count) 位骑手骑行" : "今天暂无骑手骑行"
    }

    // MARK: - 数据

    private func load() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-routesempty") {
            routes = []
            ridersByRoute = [:]
            isLoading = false
            errorMessage = nil
            checkpointWarning = nil
            return
        }
        if args.contains("-routeserror") {
            routes = []
            ridersByRoute = [:]
            isLoading = false
            errorMessage = "服务暂时不可用，请稍后重试"
            checkpointWarning = nil
            return
        }
        // 留一个稳定的筛选空态入口；真实筛选需要点按，截图巡检无法复现。
        if args.contains("-routesfilterempty") {
            searchText = "不存在的路线"
        }
        // 固定一个带单位的筛选档位，用来复检数值与 km 的排版。
        if args.contains("-routesfilterdistance") {
            distanceFilter = "50 km 内"
        }
        let isFirstLoad = routes.isEmpty
        if isFirstLoad { isLoading = true }
        defer { if isFirstLoad { isLoading = false } }
        errorMessage = nil
        checkpointWarning = nil
        let client = auth.client
        async let routesTask: [Route] = client
            .from("routes")
            .select("id, name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, map_url, cover_image_url, province, city")
            .eq("is_active", value: true)
            .order("id")
            .execute()
            .value
        async let checkpointsTask: [Checkpoint] = client
            .from("checkpoints")
            .select("id, route_id, name, seq, lat, lng, radius_m")
            .order("seq")
            .execute()
            .value

        do {
            routes = try await routesTask
        } catch {
            errorMessage = error.wellwayUserMessage
            // 列表已有内容时不打断页面：正文顶部的 InlineRefreshNotice 已经说明
            // 「刷新失败 + 仍显示上次数据」，这里再弹一条 3 秒轻提示就是同一件事说两遍，
            // 而且两句措辞还不一样。
        }

        do {
            let checkpoints = try await checkpointsTask
            var grouped: [Int: [Checkpoint]] = [:]
            for cp in checkpoints {
                grouped[cp.routeId, default: []].append(cp)
            }
            checkpointsByRoute = grouped
        } catch {
            checkpointWarning = "路线坐标未更新，缩略图与导航可能不完整"
        }

        // 真实骑行人数：后台安全聚合函数(今天北京时间，去重用户)
        if let counts: [RouteRiderCount] = try? await client
            .rpc("count_route_riders_today")
            .execute()
            .value {
            ridersByRoute = Dictionary(uniqueKeysWithValues: counts.map { ($0.routeId, $0.riderCount) })
            ridersLoaded = true
        } else {
            ridersByRoute = [:]
            ridersLoaded = false
        }
    }
}

/// iOS 26 的底部滚动边缘效果默认把内容软化成灰雾，
/// 深色路线卡滑到悬浮 Tab 上方时会被读成「没加载出来」。
/// 用 hard 边缘只做实边裁切、不再淡化内容；不要改回自定义 `.mask`。
private struct RoutesBottomScrollEdgeEffect: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .bottom)
        } else {
            content
        }
    }
}

// MARK: - 轨迹

/// 把打卡点经纬度归一化为 0~1 单位点(纬度翻转，保证 y 向下)
private func trackUnitPoints(_ checkpoints: [Checkpoint]) -> [CGPoint] {
    let coords = checkpoints.compactMap { cp -> (lat: Double, lng: Double)? in
        guard let lat = cp.lat, let lng = cp.lng else { return nil }
        return (lat, lng)
    }
    guard coords.count >= 2 else { return [] }
    let minLat = coords.map(\.lat).min()!
    let maxLat = coords.map(\.lat).max()!
    let minLng = coords.map(\.lng).min()!
    let maxLng = coords.map(\.lng).max()!
    let latSpan = max(maxLat - minLat, 0.0001)
    let lngSpan = max(maxLng - minLng, 0.0001)
    return coords.map { coord in
        CGPoint(x: (coord.lng - minLng) / lngSpan, y: 1 - (coord.lat - minLat) / latSpan)
    }
}

/// 轨迹预览：起点(粉) + 轨迹 + 终点；颜色可配置(卡片白底用黑色轨迹)
struct TrackPreview: View {
    let unitPoints: [CGPoint]
    let trackRect: CGRect
    let startDot: CGPoint
    let endDot: CGPoint
    let dotSize: CGFloat
    var trackColor: Color = Color.white
    var startColor: Color = Theme.success
    var endColor: Color = Color.white
    /// 没有真实轨迹时用虚线画路线示意
    var dashed: Bool = false
    /// 赛道缩略图用方块收尾，和起点圆点形成明确的方向层级
    var endSquare: Bool = false

    private var start: CGPoint {
        guard let first = unitPoints.first else { return startDot }
        return CGPoint(x: trackRect.minX + first.x * trackRect.width,
                       y: trackRect.minY + first.y * trackRect.height)
    }

    private var end: CGPoint {
        guard let last = unitPoints.last else { return endDot }
        return CGPoint(x: trackRect.minX + last.x * trackRect.width,
                       y: trackRect.minY + last.y * trackRect.height)
    }

    /// 只有起终点两个点时插一个侧向中点，避免画成一条直线(未配图的路线大多如此)
    private var displayPoints: [CGPoint] {
        if unitPoints.isEmpty { return TrackShape.fallbackUnit }
        guard unitPoints.count == 2 else { return unitPoints }
        let a = unitPoints[0]
        let b = unitPoints[1]
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let bend: CGFloat = 0.14
        let offset = CGPoint(x: -dy / length * bend, y: dx / length * bend)
        return [a, CGPoint(x: mid.x + offset.x, y: mid.y + offset.y), b]
    }

    var body: some View {
        ZStack {
            TrackShape(points: displayPoints, endInset: endSquare ? dotSize * 0.62 : 0)
                .stroke(trackColor, style: StrokeStyle(
                    lineWidth: dotSize * 0.29,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: dashed ? [6, 6] : []
                ))
                // Shape 自己不知道 trackRect:必须显式约束到这个区域，否则会按整张卡片铺满
                .frame(width: trackRect.width, height: trackRect.height)
                .position(x: trackRect.midX, y: trackRect.midY)
            Circle()
                .fill(startColor)
                .frame(width: dotSize, height: dotSize)
                .position(start)
            if endSquare {
                // 实心方块在 8pt 时只剩一个黑块，像渲染错误；
                // 改成描边方框，既有「终点」语义，又能看清是图形而不是脏点。
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .stroke(endColor, lineWidth: max(1.6, dotSize * 0.22))
                    .frame(width: dotSize, height: dotSize)
                    .position(end)
            } else {
                Circle()
                    .fill(endColor)
                    .frame(width: dotSize, height: dotSize)
                    .position(end)
            }
        }
    }
}

private struct TrackShape: Shape {
    let points: [CGPoint]
    /// 终点画成描边方框时，轨迹线要停在方框外沿：否则 8pt 的方框里会多出一截
    /// 白色圆头，看起来像方框里被画了一道斜线。
    var endInset: CGFloat = 0

    /// 无坐标时的示例轨迹(左下 → 右上，对应设计稿里的轨迹线)
    static let fallbackUnit: [CGPoint] = [
        CGPoint(x: 0.08, y: 0.92),
        CGPoint(x: 0.32, y: 0.86),
        CGPoint(x: 0.42, y: 0.58),
        CGPoint(x: 0.68, y: 0.46),
        CGPoint(x: 0.92, y: 0.12),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }

        func mapped(_ point: CGPoint) -> CGPoint {
            CGPoint(x: rect.minX + point.x * rect.width,
                    y: rect.minY + point.y * rect.height)
        }
        var pts = points.map(mapped)
        guard pts.count >= 2 else { return path }
        if endInset > 0, pts.count >= 2 {
            let last = pts[pts.count - 1]
            let prev = pts[pts.count - 2]
            let dx = last.x - prev.x
            let dy = last.y - prev.y
            let len = max(sqrt(dx * dx + dy * dy), 0.0001)
            let inset = min(endInset, len * 0.9)
            pts[pts.count - 1] = CGPoint(x: last.x - dx / len * inset,
                                         y: last.y - dy / len * inset)
        }
        path.move(to: pts[0])
        // Catmull-Rom → 贝塞尔：过点平滑，不会像二次曲线那样在手柄处打折
        for index in 0..<(pts.count - 1) {
            let p0 = pts[max(index - 1, 0)]
            let p1 = pts[index]
            let p2 = pts[index + 1]
            let p3 = pts[min(index + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// 路线图：后台上传的 map_url(高清 PNG)优先显示；无图时回退画线轨迹，
/// 保证旧数据与未配图路线仍正常展示。图片按卡片比例填满裁剪。
struct RouteMapImage: View {
    let route: Route
    let checkpoints: [Checkpoint]
    let trackRect: CGRect
    let startDot: CGPoint
    let endDot: CGPoint
    let dotSize: CGFloat
    var trackColor: Color = Color.white
    var startColor: Color = Theme.success
    var endColor: Color = Color.white
    /// 全屏黑底场景：对上传图做反色(白底→黑底、黑线→白线),贴合「黑底白色纯路线」设计
    var invertImage: Bool = false

    var body: some View {
        if let urlString = route.mapUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    Group {
                        if invertImage {
                            image.resizable().scaledToFit().clipped().colorInvert()
                        } else {
                            image.resizable().scaledToFit().clipped()
                        }
                    }
                case .failure:
                    fallback
                case .empty:
                    Color.clear
                        .overlay(ProgressView().tint(invertImage ? .white : Theme.listGray))
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        TrackPreview(
            unitPoints: trackUnitPoints(checkpoints),
            trackRect: trackRect,
            startDot: startDot,
            endDot: endDot,
            dotSize: dotSize,
            trackColor: trackColor,
            startColor: startColor,
            endColor: endColor
        )
    }
}

/// 可缩放路线图(纯路线感):捏合 1x~8x 缩放、缩放后可拖拽平移、双击 1x↔3x。
/// 矢量画线回退时任意缩放不糊；后台上传图放大到图片分辨率上限为止。
struct ZoomableRouteMap: View {
    let route: Route
    let checkpoints: [Checkpoint]
    let trackRect: CGRect
    let startDot: CGPoint
    let endDot: CGPoint
    let dotSize: CGFloat
    var trackColor: Color = Color.white
    var endColor: Color = Color.white
    var invertImage: Bool = false
    /// 可平移边界用整个地图区的尺寸(默认取 trackRect 尺寸)
    var viewportSize: CGSize? = nil
    var maxScale: CGFloat = 8

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1

    var body: some View {
        RouteMapImage(
            route: route,
            checkpoints: checkpoints,
            trackRect: trackRect,
            startDot: startDot,
            endDot: endDot,
            dotSize: dotSize,
            trackColor: trackColor,
            endColor: endColor,
            invertImage: invertImage
        )
        .contentShape(Rectangle())
        .scaleEffect(scale)
        .offset(offset)
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = min(max(lastScale * value, minScale), maxScale)
                }
                .onEnded { _ in
                    lastScale = scale
                    clampOffset()
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard scale > 1.001 else { return }
                    offset = clamped(
                        CGSize(width: lastOffset.width + value.translation.width,
                               height: lastOffset.height + value.translation.height)
                    )
                }
                .onEnded { _ in
                    lastOffset = offset
                }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
                .onEnded {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        if scale > 1.01 {
                            scale = 1
                            offset = .zero
                        } else {
                            scale = 3
                        }
                        lastScale = scale
                        lastOffset = offset
                    }
                }
        )
    }

    private func clamped(_ proposed: CGSize) -> CGSize {
        let size = viewportSize ?? trackRect.size
        let maxX = max(0, size.width * (scale - 1) / 2)
        let maxY = max(0, size.height * (scale - 1) / 2)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func clampOffset() {
        offset = clamped(offset)
        lastOffset = offset
    }
}

/// 全屏路线查看：点路线图进入。黑底 + 白色纯路线(品牌风格),
/// 手指捏合缩放 / 双击缩放复位 / 缩放后拖拽平移；矢量画线任意放大不糊。
struct RouteMapFullscreenView: View {
    let route: Route
    let checkpoints: [Checkpoint]
    @Environment(\.dismiss) private var dismiss

    @State private var camera: MapCameraPosition = .automatic
    @State private var roadCoordinates: [CLLocationCoordinate2D] = []

    private var checkpointCoordinates: [CLLocationCoordinate2D] {
        checkpoints
            .sorted { $0.seq < $1.seq }
            .compactMap { checkpoint in
                guard let lat = checkpoint.lat, let lng = checkpoint.lng,
                      lat != 0, lng != 0 else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
    }

    private var displayCoordinates: [CLLocationCoordinate2D] {
        roadCoordinates.count >= 2 ? roadCoordinates : checkpointCoordinates
    }

    var body: some View {
        ZStack {
            Map(position: $camera) {
                if displayCoordinates.count >= 2 {
                    MapPolyline(coordinates: displayCoordinates)
                        .stroke(Color.black.opacity(0.55), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: displayCoordinates)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(checkpointCoordinates.enumerated()), id: \.offset) { index, coordinate in
                    Annotation("", coordinate: coordinate, anchor: .center) {
                        checkpointMarker(index: index, total: checkpointCoordinates.count)
                    }
                }
            }
            .mapStyle(.standard(
                elevation: .flat,
                emphasis: .muted,
                pointsOfInterest: .excludingAll,
                showsTraffic: false
            ))
            .mapControlVisibility(.hidden)
            .preferredColorScheme(.dark)
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.black.opacity(0.78), Color.black.opacity(0.30), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 210)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.64)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.black.opacity(0.42))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(CardPressStyle(scale: 0.94))
                    .accessibilityLabel("关闭")

                    Spacer()
                }
                .padding(.horizontal, 15)
                .padding(.top, 7)

                Text(route.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    // 全屏地图顶部只有一行预算：长名最多折两行，再多就截断，
                    // 否则会把返回按钮和底部「返回路线详情」挤出可视区
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 26)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("返回路线详情")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 200, height: 48)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())

                Text("双指缩放 · 拖动地图")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.56))
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                    .allowsHitTesting(false)
            }
        }
        .statusBarHidden()
        .task {
            await loadRoadRoute()
        }
        .onAppear {
            let fallback = checkpointCoordinates
            guard fallback.count >= 2 else { return }
            camera = .region(fittedRegion(for: fallback))
        }
    }

    private func checkpointMarker(index: Int, total: Int) -> some View {
        let isStart = index == 0
        let isEnd = index == total - 1
        let background: Color = isStart
            ? Theme.success
            : (isEnd ? .white : .black.opacity(0.88))
        let foreground: Color = isStart ? .white : (isEnd ? .black : .white)
        let label = isStart ? "起" : (isEnd ? "终" : "\(index + 1)")
        let spoken = isStart ? "起点" : (isEnd ? "终点" : "第 \(index + 1) 个途经点")
        return Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(foreground)
            .frame(width: 24, height: 24)
            .background(background)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
    }

    /// 全览优先使用真实道路算路，失败时退回途经点连线，保证页面始终可用。
    private func loadRoadRoute() async {
        let points = checkpointCoordinates
        guard points.count >= 2 else { return }

        do {
            var merged: [CLLocationCoordinate2D] = []
            for index in 0..<(points.count - 1) {
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: points[index]))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: points[index + 1]))
                request.transportType = .automobile
                request.requestsAlternateRoutes = false

                let response = try await MKDirections(request: request).calculate()
                guard let first = response.routes.first, first.polyline.pointCount >= 2 else { continue }
                let count = first.polyline.pointCount
                var segment = [CLLocationCoordinate2D](repeating: points[index], count: count)
                first.polyline.getCoordinates(&segment, range: NSRange(location: 0, length: count))
                if !merged.isEmpty { segment.removeFirst() }
                merged.append(contentsOf: segment)
            }
            guard merged.count >= 2 else { return }
            let simplified = sampleRoute(merged, limit: 260)
            await MainActor.run {
                roadCoordinates = simplified
                camera = .region(fittedRegion(for: simplified))
            }
        } catch {
            return
        }
    }

    private func sampleRoute(_ coordinates: [CLLocationCoordinate2D], limit: Int) -> [CLLocationCoordinate2D] {
        guard coordinates.count > limit, limit > 1 else { return coordinates }
        let step = Double(coordinates.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            coordinates[min(Int(round(Double(index) * step)), coordinates.count - 1)]
        }
    }

    private func fittedRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude)
        let lngs = coordinates.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                                      span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08))
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.7, 0.012),
                                    longitudeDelta: max((maxLng - minLng) * 1.7, 0.012))
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - 加载骨架屏

struct RouteSkeletonList: View {
    var dark = false

    var body: some View {
        let block = dark ? Theme.darkCard : Theme.lightField
        let line = dark ? Theme.darkMeta.opacity(0.18) : Theme.cardStroke
        return ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in
                    // 与真实路线卡同构：16:9 全宽地图/封面，标题与元信息悬浮在右下。
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(block)

                        VStack(alignment: .trailing, spacing: 7) {
                            line
                                .frame(width: 124, height: 14)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            line
                                .frame(width: 164, height: 10)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                    .frame(height: 120)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 120)
        }
        .scrollDisabled(true)
        .background(Color.white)
        .accessibilityHidden(true)
    }
}


/// 路线列表卡：路线页与「我的收藏」共用，避免两处视觉和压暗逻辑各写一遍。
struct RouteListCard: View {
    let route: Route
    let checkpoints: [Checkpoint]
    let subtitle: String
    let accessibilityLabel: String
    let isFavorite: Bool

    /// 只有后台上传了封面/路线图时才需要压暗层：照片和反色的白底路线图都可能偏亮。
    private var needsImageScrim: Bool {
        route.displayImageURL != nil
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.darkBackground

            RouteThumbnailView(route: route, checkpoints: checkpoints)

            // 只压右侧：左半屏保留真实地图/封面的亮度，右半屏逐步压深，
            // 让白字在浅色地图和摄影封面上都能站住。
            // 没有上传封面时卡片是深色底(深色地图快照或纯轨迹)，再压一层会把落在右半边的
            // 终点方块压成灰色，同一列表里终点颜色忽深忽浅，所以这种情况直接省掉。
            if needsImageScrim {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.18),
                        .init(color: .black.opacity(0.16), location: 0.48),
                        .init(color: .black.opacity(0.40), location: 0.74),
                        .init(color: .black.opacity(0.58), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }

            // 没有封面时卡片是深色地图快照：右半边常压着地图自带的白字路名，
            // 整幅压暗会把终点方块一起压灰，所以只在文字所在的右中区域垫暗角。
            // 宽度用比例而不是定值：120pt 高的卡片在 SE(335pt 宽) 和 Pro(362pt 宽)
            // 上都要让「赛道图 → 文字」的过渡落在同一个位置，定值会随卡宽偏移。
            if !needsImageScrim {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.34),
                        .init(color: .black.opacity(0.26), location: 0.50),
                        .init(color: .black.opacity(0.68), location: 0.74),
                        .init(color: .black.opacity(0.84), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)
            }

            VStack(alignment: .trailing, spacing: 3) {
                Text(route.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                // 选路线时"在哪、多远、难度"是决策信息，保留一行副标题
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.90))
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.30), radius: 3, y: 1)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.trailing, 16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .overlay(alignment: .topTrailing) {
            if isFavorite {
                Image(systemName: "star.fill")
                    // 9pt 星在深色卡片上几乎看不出形状；抬高一级并换浅色底托住，
                    // 只做「已收藏」指示，不加点击态，避免暗示这里能直接切换收藏。
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.18))
                    .clipShape(Circle())
                    .padding(10)
                    .accessibilityHidden(true)
            }
        }
    }
}


// MARK: - 路线缩略图（上传封面 / 赛道轨迹）

/// 列表与出发页共用：后台上传封面优先，没有封面时用打卡点画纯赛道轨迹。
/// 不使用地图截图，避免每张卡片重复 Apple Maps 版权标，也让路线索引更像赛历。
struct RouteThumbnailView: View {
    let route: Route
    let checkpoints: [Checkpoint]
    /// 文字浮在右侧时给赛道留出左半屏；文字在图片下方时赛道居中
    var reservesTextArea: Bool = true
    var loadsRemoteImage: Bool = true

    /// 后台上传的封面：下载完成后必须写回状态，否则首帧渲染不会刷新
    @State private var coverImage: UIImage?

    private var remoteURL: URL? {
        // map_url 是整页导出的旧路线图：铺满会把两端裁掉，也会盖住起终点标记。
        // 这类路线直接画打卡点轨迹，卡片才算「赛道缩略图」，和赛历风格一致。
        guard loadsRemoteImage, !invertsMapImage else { return nil }
        return route.displayImageURL
    }

    private var downloadedCover: UIImage? {
        if let coverImage { return coverImage }
        guard let remoteURL else { return nil }
        return RouteCoverPhotoLoader.shared.cached(remoteURL)
    }

    /// 老路线的 map_url 是白底黑线的路线图；反色后与深色赛道卡统一。
    private var invertsMapImage: Bool {
        let cover = route.coverImageUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let map = route.mapUrl?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return cover.isEmpty && !map.isEmpty
    }

    private var unitPoints: [CGPoint] {
        trackUnitPoints(checkpoints.sorted { $0.seq < $1.seq })
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let rect = reservesTextArea
                ? CGRect(
                    x: size.width * 0.075,
                    y: size.height * 0.18,
                    width: size.width * 0.50,
                    height: size.height * 0.64
                )
                : CGRect(
                    x: size.width * 0.12,
                    y: size.height * 0.16,
                    width: size.width * 0.76,
                    height: size.height * 0.68
                )

            ZStack {
                Theme.darkBackground

                    // 地图快照还没回来时只剩一条线，纯黑底会被读成「图挂了」；
                    // 加一层很淡的中心辉光，让占位看起来是设计，而不是失败
                    RadialGradient(
                        colors: [Color.white.opacity(0.055), .clear],
                        center: .center,
                        startRadius: 6,
                        endRadius: max(size.width, size.height) * 0.62
                    )

                    TrackPreview(
                        unitPoints: unitPoints,
                        trackRect: rect,
                        startDot: CGPoint(x: rect.minX, y: rect.maxY),
                        endDot: CGPoint(x: rect.maxX, y: rect.minY),
                        dotSize: max(13, size.height * 0.12),
                        trackColor: .white,
                        startColor: Theme.success,
                        endColor: .white,
                        endSquare: true
                    )

                if let downloadedCover {
                    Image(uiImage: downloadedCover)
                        .resizable()
                        .scaledToFill()
                }
            }
        }
        .clipped()
        .task(id: remoteURL) {
            guard let remoteURL else { return }
            let image: UIImage?
            if let cached = RouteCoverPhotoLoader.shared.cached(remoteURL) {
                image = cached
            } else {
                image = await RouteCoverPhotoLoader.shared.image(for: remoteURL)
            }
            guard let image else { return }
            coverImage = image
        }
    }
}

