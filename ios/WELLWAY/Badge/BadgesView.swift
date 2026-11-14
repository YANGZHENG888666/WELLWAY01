import Supabase
import SwiftUI
import UIKit
import Observation

/// 徽章展示项(徽章 + 获得状态)
struct BadgeEntry: Identifiable, Hashable {
    let badge: Badge
    let earnedAt: String?
    var id: Int { badge.id }
}

/// 我的徽章(Figma「我的徽章」112:952,按节点数据 1:1 还原)
/// 进度卡 + 分组圆形徽章(已获得深色#24262B+白图标 / 未获得#F2F2F2) + 详情
struct BadgesView: View {
    var initialBadgeId: Int? = nil
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var store: BadgesStore?
    @State private var deepLinkEntry: BadgeEntry?

    var body: some View {
        content
            .navigationDestination(item: $deepLinkEntry) { entry in
                if let store {
                    BadgeDetailView(entry: entry, store: store)
                }
            }
            .pageMark((store?.earnedCount ?? 0) == 0 ? 40 : 5)
            .toolbar(.hidden, for: .navigationBar)
            .hidesAppTabBar()
            .task {
                let service = store ?? BadgesStore(client: auth.client, userId: auth.user?.id ?? UUID())
                store = service
                // 通知调试样例的徽章 id 来自本地样例数据；单独打开徽章页时如果去
                // 读线上数据，同一个 id 会落到另一枚徽章，通知和详情在巡检时对不上。
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-badgesample") || args.contains("-notifsample") {
                    service.applyDebugSample()
                    revealInitialBadge(in: service)
                    return
                }
                await service.load()
                revealInitialBadge(in: service)
            }
    }

    private func revealInitialBadge(in store: BadgesStore) {
        guard deepLinkEntry == nil,
              let initialBadgeId,
              let entry = store.entries.first(where: { $0.badge.id == initialBadgeId }) else { return }
        deepLinkEntry = entry
    }

    @ViewBuilder
    private var content: some View {
        if let store {
            if let errorMessage = store.errorMessage, store.entries.isEmpty {
                NetworkErrorView(message: errorMessage) {
                    Task { await store.load() }
                }
            } else if store.isLoading && store.entries.isEmpty {
                BadgesSkeletonView()
            } else if store.entries.isEmpty {
                emptyState
            } else {
                designContent(store)
            }
        } else {
            BadgesSkeletonView()
        }
    }

    /// 无徽章(Figma「无徽章」157:2045):还没有徽章 + 说明 + 去骑第一条路线
    private var emptyState: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "徽章")

            VStack {
                Spacer(minLength: 0)
                DesignEmptyState(icon: "medal", title: "还没有徽章", message: "完成路线与骑行挑战即可点亮第一枚徽章")
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                NotificationCenter.default.post(name: .switchToDepartTab, object: nil)
                dismiss()
            } label: {
                Text("去骑第一条路线")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(SolidPressStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .motionAppear(delay: 0.20)
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
    }

    /// 设计稿布局：标题 + 进度卡 + 按路线分组徽章
    private func designContent(_ store: BadgesStore) -> some View {
        let total = store.entries.count
        let earned = store.earnedCount
        let progress: CGFloat = total == 0 ? 0 : CGFloat(earned) / CGFloat(total)
        return VStack(spacing: 0) {
            // 标题 + 返回(固定，不随内容滚动)
            DesignPageHeader(title: "徽章")
            ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let warning = store.errorMessage ?? store.supplementalError {
                    InlineRefreshNotice(message: warning) {
                        Task { await store.load() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
                // 进度卡(y=104)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("徽章进度")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        // 计数与骑行总结 / HUD 的「3/3」「0/2」同一种写法，不再加大空格
                        Text("\(earned)/\(total)")
                            .font(.system(size: 15, weight: .semibold).monospacedDigit())
                            .foregroundColor(Theme.textPrimary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("徽章进度 \(earned) 个，共 \(total) 个")
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.cardStroke)
                            Capsule()
                                .fill(Theme.textPrimary)
                                .frame(width: progress > 0 ? max(geo.size.width * progress, 6) : 0)
                        }
                    }
                    // 一整条细进度条：此前按徽章数切开的白刻度，在 0/6 时会被读成
                    // 六个加载骨架块，反而不像进度。数量由右侧「0 / 6」表达。
                    .frame(height: 6)
                    .clipShape(Capsule())
                    .padding(.top, 12)

                    if let nextEntry = store.entries.first(where: { $0.earnedAt == nil }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text("下一枚")
                                    .foregroundColor(Theme.textSecondary)
                                Text(nextEntry.badge.name)
                                    .fontWeight(.semibold)
                                    .foregroundColor(Theme.textPrimary)
                            }
                            .font(.system(size: 13))
                            Text(conditionText(for: nextEntry))
                                .font(.system(size: 12.5))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .padding(.top, 12)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("下一枚：\(nextEntry.badge.name)，\(conditionText(for: nextEntry))")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .motionAppear(delay: 0.05)

                Text("全部徽章")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, 20)
                    .padding(.top, 32)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading), count: 2),
                    alignment: .leading,
                    spacing: 22
                ) {
                    ForEach(Array(store.entries.enumerated()), id: \.element.id) { index, entry in
                        NavigationLink {
                            BadgeDetailView(entry: entry, store: store)
                        } label: {
                            badgeCell(entry)
                                .motionAppear(delay: 0.12 + Double(index) * 0.04)
                                .motionPress()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .padding(.bottom, 24)
            }
            .refreshable { await store.load() }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }

    /// 徽章格：条件直接展示，避免用户逐个点开才知道要做什么。
    private func badgeCell(_ entry: BadgeEntry) -> some View {
        let earned = entry.earnedAt != nil
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                ZStack {
                    if earned {
                        Circle()
                            .fill(Theme.darkCard)
                        BadgeIcon(badge: entry.badge, size: 62)
                    } else {
                        Circle()
                            .stroke(Theme.cardStroke, lineWidth: 1)
                        Image(systemName: BadgeIcon.symbol(for: entry.badge)
                            .replacingOccurrences(of: ".fill", with: ""))
                            .font(.system(size: 24, weight: .regular))
                            .foregroundColor(Theme.listGray)
                    }
                }
                .frame(width: 64, height: 64)
                .overlay(alignment: .bottomTrailing) {
                    if earned {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color.white)
                            .frame(width: 21, height: 21)
                            .background(Theme.success)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    } else {
                        // 锁定态整格已经偏淡，锁标再浅就看不见了：
                        // 用次要文字色 + 分隔线描边，保证「这枚还没拿到」一眼可读。
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            // 与「已获得」右上角的对勾同尺寸，两种状态的角标才对齐
                            .frame(width: 21, height: 21)
                            .background(Color.white)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Theme.separator, lineWidth: 1))
                            .offset(x: 2, y: 2)
                            .accessibilityHidden(true)
                    }
                }

                Spacer(minLength: 8)
            }

            Text(entry.badge.name)
                .font(.system(size: 15, weight: earned ? .semibold : .medium))
                .foregroundColor(earned ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .padding(.top, 14)

            Text(conditionText(for: entry))
                .font(.system(size: 12.5))
                .foregroundColor(Theme.textSecondary)
                .lineLimit(2)
                .lineSpacing(2)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.badge.name)，\(earned ? "已获得" : "未获得")，\(conditionText(for: entry))")
    }

    private func conditionText(for entry: BadgeEntry) -> String {
        if let raw = entry.badge.conditionDesc?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return entry.badge.routeId == nil ? "完成对应骑行挑战" : "完成路线全部打卡点"
    }
}

/// 徽章首屏骨架：与真实页面同构，避免数据回来前先闪「还没有徽章」
private struct BadgesSkeletonView: View {
    private let block = Theme.cardStroke

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "徽章")
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            bar(width: 112, height: 16)
                            Spacer()
                            bar(width: 44, height: 15)
                        }
                        bar(width: nil, height: 5, radius: 2.5)
                            .padding(.top, 12)
                        bar(width: 58, height: 13)
                            .padding(.top, 12)
                        bar(width: 164, height: 12)
                            .padding(.top, 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 24)

                    bar(width: 72, height: 15)
                        .padding(.leading, 20)
                        .padding(.top, 32)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .topLeading), count: 2),
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(0..<9, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Circle()
                                        .fill(block)
                                        .frame(width: 64, height: 64)
                                    Spacer()
                                }
                                bar(width: 76, height: 15)
                                    .padding(.top, 14)
                                bar(width: nil, height: 12)
                                    .padding(.top, 6)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                }
                .padding(.bottom, 24)
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityHidden(true)
    }

    private func bar(width: CGFloat?, height: CGFloat, radius: CGFloat = 6) -> some View {
        block
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// 徽章图形：优先展示后台配置的 image_url，没有配置时按徽章名称取语义图标
struct BadgeIcon: View {
    let badge: Badge
    var size: CGFloat

    var body: some View {
        Group {
            if let raw = badge.imageUrl,
               let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
               !raw.isEmpty {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size * 0.62, height: size * 0.62)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
    }

    private var fallback: some View {
        Image(systemName: Self.symbol(for: badge))
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
    }

    static func symbol(for badge: Badge) -> String {
        let name = badge.name
        if name.contains("虹") { return "rainbow" }
        if name.contains("打卡") || name.contains("达人") { return "checkmark.seal.fill" }
        if name.contains("通勤") { return "building.2.fill" }
        if name.contains("新手") || name.contains("首骑") { return "sparkles" }
        if name.contains("跑山") { return "bolt.fill" }
        if name.contains("夜") { return "moon.stars.fill" }
        if name.contains("雪") { return "snowflake" }
        if name.contains("日出") || name.contains("清晨") { return "sunrise.fill" }
        if name.contains("百公里") || name.contains("里程") { return "flag.checkered" }
        if name.contains("弯") { return "arrow.triangle.turn.up.right.diamond.fill" }
        if name.contains("顶") || name.contains("山") { return "mountain.2.fill" }
        if name.contains("湖") || name.contains("海") { return "water.waves" }
        if name.contains("初") { return "sparkles" }
        return "medal.fill"
    }
}

/// 徽章分享按钮：点击时才渲染高清卡图，避免页面重绘反复生成大图。
private struct BadgeShareButton: View {
    let entry: BadgeEntry
    let conditionText: String
    let dateText: String
    let text: String
    @State private var showShare = false

    var body: some View {
        Button {
            showShare = true
        } label: {
            Text("分享")
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .sheet(isPresented: $showShare) {
            let image = BadgeShareCardRenderer.image(
                badge: entry.badge,
                name: entry.badge.name,
                condition: conditionText,
                dateText: dateText
            )
            ShareSheet(items: image.map { [$0] } ?? [text])
        }
    }
}

/// 徽章分享卡：1080×1350（4:5），与骑行分享卡保持同一套深色品牌语言。
/// 不复用详情页整页截图，避免把状态栏、返回按钮和空白一起发出去。
struct BadgeShareCard: View {
    static let size = CGSize(width: 1080, height: 1350)

    let badge: Badge
    let name: String
    let condition: String
    let dateText: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.darkBackground

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Image("Wordmark")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.white.opacity(0.92))
                        .frame(width: 160, height: 50)
                        .accessibilityLabel("WellWay")

                    Spacer(minLength: 24)

                    HStack(spacing: 10) {
                        Circle()
                            .fill(Theme.success)
                            .frame(width: 10, height: 10)
                        Text("徽章已点亮")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                    }
                }

                Spacer(minLength: 120)

                HStack {
                    Spacer(minLength: 0)
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.07))
                        Circle()
                            .stroke(Color.white.opacity(0.12), lineWidth: 2)
                        BadgeIcon(badge: badge, size: 300)
                    }
                    .frame(width: 420, height: 420)
                    Spacer(minLength: 0)
                }

                Text(name)
                    .font(.system(size: 76, weight: .bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 52)

                Text(condition)
                    .font(.system(size: 28))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 22)

                if !dateText.isEmpty {
                    Text("\(dateText) 获得")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white.opacity(0.48))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                }

                Spacer(minLength: 0)

                HStack {
                    Text("好路当骑 同行当悉")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.white.opacity(0.44))
                    Spacer(minLength: 0)
                }
            }
            .padding(80)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

@MainActor
enum BadgeShareCardRenderer {
    static func image(badge: Badge, name: String, condition: String, dateText: String) -> UIImage? {
        let card = BadgeShareCard(badge: badge, name: name, condition: condition, dateText: dateText)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

/// 徽章数据
@MainActor
@Observable
final class BadgesStore {
    private(set) var entries: [BadgeEntry] = []
    private(set) var isLoading = false

    var earnedCount: Int {
        entries.filter { $0.earnedAt != nil }.count
    }
    private(set) var routesById: [Int: Route] = [:]
    private(set) var checkpointsById: [Int: Checkpoint] = [:]
    private(set) var checkedCheckpointIds: Set<Int> = []
    var errorMessage: String?
    /// 补充数据(路线、打卡点、已打卡记录)失败时不阻断整页，仅提示可能不完整。
    var supplementalError: String?

    private let client: SupabaseClient
    private let userId: UUID

    init(client: SupabaseClient, userId: UUID) {
        self.client = client
        self.userId = userId
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        // 调试入口：-badgesempty 直接按空数据渲染「还没有徽章」
        if ProcessInfo.processInfo.arguments.contains("-badgesempty") {
            entries = []
            errorMessage = nil
            supplementalError = nil
            return
        }
        errorMessage = nil
        supplementalError = nil
        async let routesTask: () = loadRoutes()
        async let badgesTask: () = loadBadges()
        async let checkpointsTask: () = loadCheckpoints()
        async let checkinsTask: () = loadCheckins()
        _ = await (routesTask, badgesTask, checkpointsTask, checkinsTask)
    }

    private func loadRoutes() async {
        do {
            let loaded: [Route] = try await client
                .from("routes")
                .select("id, name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, map_url, cover_image_url, province, city")
                .eq("is_active", value: true)
                .execute()
                .value
            routesById = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            supplementalError = "部分路线信息暂时无法加载"
        }
    }

    /// 按路线分组(设计稿按 通勤线/跑山线 等分组),保持 seq 顺序
    var groupedEntries: [(name: String, entries: [BadgeEntry])] {
        var order: [String] = []
        var groups: [String: [BadgeEntry]] = [:]
        for entry in entries {
            let name = groupName(for: entry.badge)
            if groups[name] == nil { order.append(name) }
            groups[name, default: []].append(entry)
        }
        return order.map { (name: $0, entries: groups[$0] ?? []) }
    }

    private func groupName(for badge: Badge) -> String {
        guard let routeId = badge.routeId, let routeName = routesById[routeId]?.name else {
            return "徽章"
        }
        if routeName.hasSuffix("线"), routeName.count > 3 {
            return String(routeName.suffix(3))
        }
        return routeName
    }

    private func loadBadges() async {
        do {
            let badges: [Badge] = try await client
                .from("badges")
                .select("id, route_id, name, image_url, condition_desc, seq")
                .order("seq")
                .execute()
                .value
            let loadedUserBadges: [UserBadge] = try await client
                .from("user_badges")
                .select("id, badge_id, ride_id, earned_at")
                .eq("user_id", value: userId)
                .execute()
                .value
            let userBadges = await backfillFirstRideBadgeIfNeeded(badges: badges, owned: loadedUserBadges)
            let earnedByBadge = Dictionary(uniqueKeysWithValues: userBadges.map { ($0.badgeId, $0.earnedAt) })
            entries = badges.map { BadgeEntry(badge: $0, earnedAt: earnedByBadge[$0.id]) }
        } catch {
            errorMessage = entries.isEmpty
                ? error.wellwayUserMessage
                : "徽章刷新失败，当前显示上次数据"
        }
    }

    /// 早先版本只在「打卡点全部完成」时才发放「新手首骑」，已经骑过的用户因此一直停在 0/6。
    /// 这里按徽章自己的获得条件补发一次，发过就不再重复。
    private func backfillFirstRideBadgeIfNeeded(badges: [Badge], owned: [UserBadge]) async -> [UserBadge] {
        guard let firstRide = badges.first(where: {
            $0.routeId == nil && ($0.conditionDesc ?? "").contains("第一次骑行")
        }) else { return owned }
        guard !owned.contains(where: { $0.badgeId == firstRide.id }) else { return owned }

        struct RideRow: Decodable { let id: UUID }
        let rides: [RideRow] = (try? await client
            .from("ride_records")
            .select("id")
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "completed")
            .limit(1)
            .execute()
            .value) ?? []
        guard let ride = rides.first else { return owned }

        _ = try? await client.rpc("award_badge", params: [
            "p_user_id": userId.uuidString,
            "p_badge_id": String(firstRide.id),
            "p_ride_id": ride.id.uuidString,
        ]).execute()

        let refreshed: [UserBadge] = (try? await client
            .from("user_badges")
            .select("id, badge_id, ride_id, earned_at")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value) ?? owned
        return refreshed
    }

    private func loadCheckpoints() async {
        do {
            let loaded: [Checkpoint] = try await client
                .from("checkpoints")
                .select("id, route_id, name, seq, lat, lng, radius_m")
                .order("seq")
                .execute()
                .value
            checkpointsById = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        } catch {
            supplementalError = "部分徽章进度暂时无法加载"
        }
    }

    private func loadCheckins() async {
        do {
            let loaded: [RideCheckin] = try await client
                .from("ride_checkins")
                .select("id, ride_id, checkpoint_id, checked_at")
                .eq("user_id", value: userId)
                .execute()
                .value
            checkedCheckpointIds = Set(loaded.map(\.checkpointId))
        } catch {
            supplementalError = "部分徽章进度暂时无法加载"
        }
    }

    /// 某路线的打卡点(按 seq 排序)
    func checkpoints(for routeId: Int) -> [Checkpoint] {
        checkpointsById.values
            .filter { $0.routeId == routeId }
            .sorted { $0.seq < $1.seq }
    }

    /// 某路线下已打卡的点数
    func checkedCount(for routeId: Int?) -> Int {
        guard let routeId else { return 0 }
        return checkpointsById.values
            .filter { $0.routeId == routeId && checkedCheckpointIds.contains($0.id) }
            .count
    }

    /// 调试用(-badgesample)：注入已获得/未获得混合徽章，不访问网络
    func applyDebugSample() {
        let sampleRoutes = [
            Route(id: 1, name: "洱海环湖线", startName: "大理古城", endName: "双廊", distanceM: 42_000, elevationM: 560, difficulty: "简单", durationMin: 180, mapUrl: nil, coverImageUrl: nil, province: "云南", city: "大理"),
            Route(id: 2, name: "西山盘山线", startName: "高峣", endName: "猫猫箐", distanceM: 28_000, elevationM: 780, difficulty: "中等", durationMin: 120, mapUrl: nil, coverImageUrl: nil, province: "云南", city: "昆明"),
            Route(id: 3, name: "滨海通勤线", startName: "湿地公园", endName: "渔人码头", distanceM: 18_000, elevationM: 90, difficulty: "简单", durationMin: 60, mapUrl: nil, coverImageUrl: nil, province: "福建", city: "厦门")
        ]
        routesById = Dictionary(uniqueKeysWithValues: sampleRoutes.map { ($0.id, $0) })

        let sampleCheckpoints = [
            Checkpoint(id: 1, routeId: 1, name: "大理古城", seq: 1, lat: nil, lng: nil, radiusM: 300),
            Checkpoint(id: 2, routeId: 1, name: "喜洲古镇", seq: 2, lat: nil, lng: nil, radiusM: 300),
            Checkpoint(id: 3, routeId: 1, name: "双廊", seq: 3, lat: nil, lng: nil, radiusM: 300),
            Checkpoint(id: 4, routeId: 2, name: "高峣", seq: 1, lat: nil, lng: nil, radiusM: 300),
            Checkpoint(id: 5, routeId: 2, name: "猫猫箐", seq: 2, lat: nil, lng: nil, radiusM: 300),
            Checkpoint(id: 6, routeId: 3, name: "湿地公园", seq: 1, lat: nil, lng: nil, radiusM: 300),
            Checkpoint(id: 7, routeId: 3, name: "渔人码头", seq: 2, lat: nil, lng: nil, radiusM: 300)
        ]
        checkpointsById = Dictionary(uniqueKeysWithValues: sampleCheckpoints.map { ($0.id, $0) })
        checkedCheckpointIds = [1, 2, 3, 4, 6, 7]

        let samples: [(Badge, String?)] = [
            (Badge(id: 1, routeId: 1, name: "洱海初见", imageUrl: nil, conditionDesc: "完成洱海环湖线全部打卡点", seq: 1), "2026-10-12T08:20:00Z"),
            (Badge(id: 2, routeId: 1, name: "风花雪月", imageUrl: nil, conditionDesc: "累计骑行洱海环湖线 3 次", seq: 2), "2026-10-26T09:05:00Z"),
            (Badge(id: 3, routeId: 1, name: "环湖夜骑", imageUrl: nil, conditionDesc: "夜间完成洱海环湖线", seq: 3), nil),
            (Badge(id: 4, routeId: 2, name: "西山登顶", imageUrl: nil, conditionDesc: "完成西山盘山线全部打卡点", seq: 4), nil),
            (Badge(id: 5, routeId: 2, name: "弯道猎手", imageUrl: nil, conditionDesc: "单次骑行完成 20 个弯道", seq: 5), nil),
            (Badge(id: 6, routeId: 3, name: "海岸长虹", imageUrl: nil, conditionDesc: "完成滨海通勤线全部打卡点", seq: 6), "2026-09-30T18:40:00Z"),
            (Badge(id: 7, routeId: 3, name: "日出出发", imageUrl: nil, conditionDesc: "日出前出发完成通勤线", seq: 7), nil),
            (Badge(id: 8, routeId: 3, name: "百公里", imageUrl: nil, conditionDesc: "累计骑行 100 公里", seq: 8), nil)
        ]
        entries = samples.map { BadgeEntry(badge: $0.0, earnedAt: $0.1) }
    }

    func totalCount(for routeId: Int?) -> Int {
        guard let routeId else { return 0 }
        return checkpointsById.values.filter { $0.routeId == routeId }.count
    }
}

/// 徽章详情(Figma「徽章详情」)
struct BadgeDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: BadgeEntry
    let store: BadgesStore

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "徽章详情")

            // 徽章详情内容不多：整体垂直居中，避免下方空出四成屏幕。
            GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(entry.earnedAt == nil ? Theme.lightField : Theme.darkCard)
                        if entry.earnedAt == nil {
                            Image(systemName: BadgeIcon.symbol(for: entry.badge))
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(Theme.listGray)
                        } else {
                            BadgeIcon(badge: entry.badge, size: 120)
                        }
                    }
                    .frame(width: 120, height: 120)
                    .overlay(alignment: .bottomTrailing) {
                        if entry.earnedAt == nil {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 26, height: 26)
                                .background(Color.white)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(Theme.separator, lineWidth: 1))
                        }
                    }
                    .padding(.top, 32)
                    .motionAppear(delay: 0.08)
                    .motionPop(delay: 0.10)
                    .accessibilityHidden(true)

                    Text(entry.badge.name)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 20)
                        .motionAppear(delay: 0.16)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("获得条件")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                        Text(conditionText)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let earnedAt = entry.earnedAt {
                            Text("\(formatDate(earnedAt)) 获得")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                    .padding(.top, 24)
                    .motionAppear(delay: 0.22)

                    if entry.badge.routeId != nil,
                       store.totalCount(for: entry.badge.routeId) > 0 {
                        progressCard
                            .padding(.top, 12)
                            .motionAppear(delay: 0.28)
                    } else if let progress = globalProgress {
                        globalProgressCard(progress)
                            .padding(.top, 12)
                            .motionAppear(delay: 0.28)
                    }

                    if entry.earnedAt == nil {
                        // 打卡点已满但徽章仍未点亮时，说明还有别的条件（如夜间、里程），
                        // 直接说清楚，避免"3/3 却还锁着"看起来像 bug
                        let checked = store.checkedCount(for: entry.badge.routeId)
                        let total = store.totalCount(for: entry.badge.routeId)
                        // 上面几段都是左对齐的信息块，这句解释居中会读成空态；
                        // 它说明的是「为什么 3/3 还锁着」，属于正文而不是点缀。
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityHidden(true)
                            Text(total > 0 && checked >= total ? "打卡点已完成，还需满足上方条件" : "完成条件后会自动点亮")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 20)
                        .motionAppear(delay: 0.34)
                    }

                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            // 分享/再跑一次固定在底部：跟着内容走会让按钮停在屏幕中段、
            // 下方空掉近四成，页面看起来像没加载完
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActions
                    .padding(.bottom, 8)
                    .wellwayBottomBar()
                    .motionAppear(delay: 0.38)
            }
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .ignoresSafeArea(edges: .top)
        .pageMark(13)
    }

    /// 底部主行动：分享（已获得）+ 再跑一次 / 去骑一条路线
    private var bottomActions: some View {
        VStack(spacing: 8) {
            if entry.earnedAt != nil {
                BadgeShareButton(entry: entry, conditionText: conditionText, dateText: entry.earnedAt.map(formatDate) ?? "", text: shareText)
            }
            if let routeId = entry.badge.routeId, let route = store.routesById[routeId] {
                NavigationLink {
                    RouteDetailView(route: route, checkpoints: store.checkpoints(for: routeId))
                } label: {
                    // 次行动只保留文字行：一屏只允许一颗同尺寸大按钮。
                    // 已获得时「分享」是主行动，「再跑一次」再占一颗 52pt 浅灰按钮会把
                    // 底部读成两个并列选项；未获得时没有「分享」，它才是唯一的黑色主行动。
                    Text(entry.earnedAt == nil ? "查看这条路线" : "再跑一次这条路线")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(entry.earnedAt == nil ? Color.white : Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: entry.earnedAt == nil ? 52 : 44)
                        .background(entry.earnedAt == nil ? Color.black : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(SolidPressStyle())
            } else {
                Button {
                    NotificationCenter.default.post(name: .switchToDepartTab, object: nil)
                    dismiss()
                } label: {
                    Text(entry.earnedAt == nil ? "去骑一条路线" : "继续骑行")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    /// 通用挑战的进度：例如“累计完成 10 次路线打卡”
    /// 只展示能从现有打卡记录可靠计算的项目，避免用假进度装饰页面。
    private var globalProgress: (current: Int, total: Int, label: String)? {
        guard entry.badge.routeId == nil else { return nil }
        let condition = conditionText
        guard condition.contains("打卡") else { return nil }
        guard let target = condition.split(whereSeparator: { !$0.isNumber }).first.flatMap({ Int($0) }),
              target > 0 else { return nil }
        return (min(store.checkedCheckpointIds.count, target), target, "累计打卡")
    }

    private func globalProgressCard(_ progress: (current: Int, total: Int, label: String)) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(progress.label)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Text("\(progress.current)/\(progress.total)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.lightField)
                    Capsule()
                        .fill(Theme.textPrimary)
                        .frame(width: progress.current == 0 || progress.total == 0
                               ? 0
                               : max(geo.size.width * CGFloat(progress.current) / CGFloat(progress.total), 4))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 16)
    }

    /// 进度卡：本路线打卡进度
    private var progressCard: some View {
        let checked = store.checkedCount(for: entry.badge.routeId)
        let total = store.totalCount(for: entry.badge.routeId)
        let routeCheckpoints = entry.badge.routeId.map { store.checkpoints(for: $0) } ?? []
        let allDone = total > 0 && checked >= total
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("本路线已打卡")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                Text("\(checked)/\(total)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("本路线已打卡 \(checked) 个，共 \(total) 个")
            if allDone {
                // 全部打完时进度条已经满格、不再传达信息，改成逐个打卡点的完成明细
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 88), spacing: 10, alignment: .leading)],
                    alignment: .leading,
                    spacing: 9
                ) {
                    ForEach(routeCheckpoints) { cp in
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.success)
                            Text(cp.name.withoutEmoji)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(cp.name.withoutEmoji)，已打卡")
                    }
                }
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.lightField)
                        Capsule()
                            .fill(Theme.textPrimary)
                            .frame(width: checked == 0 || total == 0 ? 0 : max(geo.size.width * CGFloat(checked) / CGFloat(total), 4))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private var shareText: String {
        """
        WellWay
        \(entry.badge.name) 徽章
        \(conditionText)
        好路当骑 同行当悉
        """
    }

    /// 条件描述可能为空；无路线徽章不能回退成“完成路线打卡”。
    private var conditionText: String {
        if let raw = entry.badge.conditionDesc?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return entry.badge.routeId == nil ? "完成对应骑行挑战" : "完成对应路线全程打卡"
    }

    private func formatDate(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.wellwayDate(from: iso) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "M月d日 HH:mm"
            : "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
