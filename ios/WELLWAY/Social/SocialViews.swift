import SwiftUI
import UIKit
import MapKit
import CoreLocation
import Observation
import Supabase

// MARK: - 通知列表

/// 通知项(由本地数据派生：徽章 / 打卡)
struct NotifItem: Identifiable {
    enum Kind {
        case badge, checkin, ride
    }
    let id: String
    let kind: Kind
    let title: String
    let body: String
    let time: String
    let date: Date?
    var targetRecordId: UUID? = nil
    /// 徽章通知直接定位到对应徽章详情。
    var targetBadgeId: Int? = nil
}

/// 通知列表(Figma「通知列表」234:19,按节点数据 1:1 还原)
struct NotificationsView: View {
    @Environment(AuthManager.self) private var auth
    @State private var items: [NotifItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var refreshFailed = false
    @State private var loadErrorMessage = "通知加载失败，请稍后重试"
    @State private var lastSeenAt: Date?

    private static let lastSeenKey = "notificationsLastSeenAt"

    private struct BadgeNameRow: Decodable {
        let id: Int
        let name: String
    }

    private struct RouteNameRow: Decodable {
        let id: Int
        let name: String
    }

    private struct CheckpointNameRow: Decodable {
        let id: Int
        let name: String
    }

    /// 三个数据源分别保留成功 / 失败：全部失败时要能说出真实原因，
    /// 不能把服务端或权限错误一律写成「请检查网络连接」。
    private struct NotifLoadOutcome {
        private enum Payload {
            case items([NotifItem])
            case failed(String)
        }

        private let payload: Payload

        var items: [NotifItem]? {
            if case .items(let items) = payload { return items }
            return nil
        }

        var failureMessage: String? {
            if case .failed(let message) = payload { return message }
            return nil
        }

        static func success(_ items: [NotifItem]) -> NotifLoadOutcome {
            NotifLoadOutcome(payload: .items(items))
        }

        static func failure(_ error: Error) -> NotifLoadOutcome {
            NotifLoadOutcome(payload: .failed(error.wellwayUserMessage))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "通知")
                // 列表滚动时首条会贴着页头下沿被硬切；加一层同色渐隐，
                // 让内容读成滑进页头下方，而不是和标题叠在一起。
                .overlay(alignment: .bottom) {
                    if !isLoading, !loadFailed, !items.isEmpty {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white, location: 0),
                                .init(color: Color.white.opacity(0.96), location: 0.45),
                                .init(color: Color.white.opacity(0), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 24)
                        .offset(y: 24)
                        .allowsHitTesting(false)
                    }
                }
                .zIndex(1)
            Group {
                if isLoading {
                    notificationsSkeleton
                } else if loadFailed {
                    NetworkErrorView(message: loadErrorMessage) {
                        Task { await load() }
                    }
                } else if items.isEmpty {
                    // 通知随时间变化，空态也必须能下拉刷新；
                    // 否则用户停在「暂无通知」上只能退出页面再进来。
                    ScrollView(showsIndicators: false) {
                        DesignEmptyState(icon: "bell", title: "暂无通知", message: "骑行完成、打卡和徽章会出现在这里")
                            .frame(maxWidth: .infinity)
                            .containerRelativeFrame(.vertical)
                    }
                    .refreshable { await load(showLoading: false) }
                    .scrollBounceBehavior(.always, axes: .vertical)
                } else {
                    ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if refreshFailed {
                                InlineRefreshNotice(message: "通知刷新失败，当前显示上次数据") {
                                    Task { await load(showLoading: false) }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 10)
                            }
                            ForEach(Array(groupedItems.enumerated()), id: \.element.id) { groupIndex, group in
                                Text(group.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 20)
                                    .padding(.top, groupIndex == 0 ? 16 : 22)

                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink {
                                        destination(for: item)
                                    } label: {
                                        notifCard(item, timeText: cardTime(item, group: group))
                                    }
                                    .buttonStyle(RowPressStyle())
                                    .motionAppear(delay: Double(index) * Motion.stagger)

                                    if index < group.items.count - 1 {
                                        Rectangle()
                                            .fill(Theme.separator)
                                            .frame(height: 1)
                                            .padding(.leading, 56)
                                    }
                                }
                            }
                            if ProcessInfo.processInfo.arguments.contains("-notificationsbottom") {
                                Color.clear.frame(height: 1).id("notifications-bottom")
                            }
                        }
                        .padding(.bottom, 28)
                    }
                    .refreshable { await load(showLoading: false) }
                    .scrollBounceBehavior(.always, axes: .vertical)
                    .task(id: items.count) {
                        guard ProcessInfo.processInfo.arguments.contains("-notificationsbottom"),
                              !items.isEmpty else { return }
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation(.easeOut(duration: 0.24)) {
                            proxy.scrollTo("notifications-bottom", anchor: .bottom)
                        }
                    }
                    }
                }
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .task { await load() }
        .onDisappear { markAllSeen() }
        .pageMark(65)
    }

    private var notificationsSkeleton: some View {
        let block = Theme.cardStroke
        return ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(alignment: .top, spacing: 14) {
                        block
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                block.frame(width: 132, height: 15).clipShape(Capsule())
                                Spacer()
                                block.frame(width: 52, height: 10).clipShape(Capsule())
                            }
                            block.frame(width: 244, height: 12).clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    if index < 2 {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(height: 1)
                            .padding(.leading, 56)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private func destination(for item: NotifItem) -> some View {
        switch item.kind {
        case .badge:
            BadgesView(initialBadgeId: item.targetBadgeId)
        case .checkin, .ride:
            RecordsView(initialRecordId: item.targetRecordId)
        }
    }

    /// 通知行：细图标 + 标题/正文，不用图标底托
    private func notifCard(_ item: NotifItem, timeText: String) -> some View {
        let unread = isUnread(item)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon(for: item.kind))
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(color(for: item.kind))
                .frame(width: 22, height: 22)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(item.title)
                        // 未读靠字重表达(邮件/Gmail 的做法)：标题后挂一颗绿点会被读成
                        // 正文里的项目符号，既不像状态也不像分隔。
                        .font(.system(size: 15, weight: unread ? .semibold : .regular))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(timeText)
                        .font(.system(size: 12, weight: unread ? .medium : .regular))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(item.body)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // 只在外层写一次：挂在 4 个子视图的容器上时，NavigationLink 合并子元素会把
        // 同一个值复制成「未读，未读，未读，未读」。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title)，\(timeText)，\(item.body)")
        .accessibilityValue(unread ? "未读" : "")
    }

    private func icon(for kind: NotifItem.Kind) -> String {
        switch kind {
        // 三种通知用同一套线性图标：实心旗和线性徽章混排时，笔画粗细对不上
        case .badge: return "seal"
        case .checkin: return "checkmark.seal"
        // 方格旗是实心黑块，和旁边两条线描图标放在一起笔画重量差一倍；
        // 骑行类通知用线描摩托车，语义更直接，也和整套线性图标一致。
        // SF Symbols 里 motorcycle 从 iOS 18 才有：低版本写死会渲染成空白。
        // 统一走 Theme.vehicleSymbol(18+ 摩托车，17 回退自行车)。
        case .ride: return Theme.vehicleSymbol
        }
    }

    private func color(for kind: NotifItem.Kind) -> Color {
        switch kind {
        case .badge: return Theme.textPrimary
        case .checkin: return Theme.success
        case .ride: return Theme.textPrimary
        }
    }

    private func load(showLoading: Bool = true) async {
        if showLoading { isLoading = true }
        loadFailed = false
        lastSeenAt = UserDefaults.standard.object(forKey: Self.lastSeenKey) as? Date
        defer { if showLoading { isLoading = false } }
        if ProcessInfo.processInfo.arguments.contains("-notificationsempty") {
            items = []
            return
        }
        if ProcessInfo.processInfo.arguments.contains("-notifsample") {
            let now = Date()
            items = [
                NotifItem(id: "sample-1", kind: .badge, title: "点亮「环湖夜骑」徽章", body: "完成洱海环湖骑行，第 3 枚路线徽章已收入囊中。", time: "10 分钟前", date: now.addingTimeInterval(-600), targetBadgeId: 3),
                NotifItem(id: "sample-2", kind: .checkin, title: "打卡完成", body: "已打卡「双廊」，继续保持。", time: "昨天", date: Calendar.current.date(byAdding: .day, value: -1, to: now)),
                NotifItem(id: "sample-3", kind: .ride, title: "骑行完成", body: "洱海环湖骑行已保存，去查看轨迹总结吧。", time: "10月28日", date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 18, minute: 40))),
            ]
            if ProcessInfo.processInfo.arguments.contains("-notificationsbottom") {
                let base = items
                items = (0..<12).map { index in
                    let source = base[index % base.count]
                    // 每行 -1 小时，日期和右上角时间必须一起推：只改 date 会让
                    // 11 小时前的条目仍写「10 分钟前」，长列表底部版式就失去参考价值。
                    let date = Date().addingTimeInterval(-Double(index) * 3600)
                    return NotifItem(
                        id: "sample-bottom-\(index)",
                        kind: source.kind,
                        title: source.title,
                        body: source.body,
                        time: relativeTime(date),
                        date: date,
                        targetRecordId: source.targetRecordId,
                        targetBadgeId: source.targetBadgeId
                    )
                }
            }
            return
        }
        guard let uid = auth.user?.id else {
            loadErrorMessage = "登录状态已失效，请重新登录"
            loadFailed = true
            return
        }
        let client = auth.client
        async let badgeTask = loadBadgeItems(client: client, userId: uid)
        async let rideTask = loadRideItems(client: client, userId: uid)
        async let checkinTask = loadCheckinItems(client: client, userId: uid)
        let (badgeResult, rideResult, checkinResult) = await (badgeTask, rideTask, checkinTask)
        let badges = badgeResult.items
        let rides = rideResult.items
        let checkins = checkinResult.items
        let allFailed = badges == nil && rides == nil && checkins == nil
        let partiallyFailed = badges == nil || rides == nil || checkins == nil
        let result = (badges ?? []) + (rides ?? []) + (checkins ?? [])
        if allFailed {
            loadErrorMessage = [badgeResult, rideResult, checkinResult]
                .compactMap(\.failureMessage)
                .first ?? "通知加载失败，请稍后重试"
            if items.isEmpty {
                loadFailed = true
            } else {
                refreshFailed = true
            }
            return
        }
        // 已有内容时，部分数据源失败不覆盖整张列表，避免刷新后条目突然消失。
        if partiallyFailed, !showLoading, !items.isEmpty {
            refreshFailed = true
            return
        }
        loadFailed = false
        refreshFailed = partiallyFailed
        items = Array(
            result
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                .prefix(30)
        )
    }

    private func isUnread(_ item: NotifItem) -> Bool {
        guard let date = item.date else { return false }
        guard let lastSeenAt else { return true }
        return date > lastSeenAt
    }

    private struct NotifGroup: Identifiable {
        let id: String
        let title: String
        let items: [NotifItem]
    }

    /// 按自然日分组（今天 / 昨天 / 具体日期），保持后端已排序的顺序。
    private var groupedItems: [NotifGroup] {
        let calendar = Calendar.current
        var order: [String] = []
        var labels: [String: String] = [:]
        var buckets: [String: [NotifItem]] = [:]

        for item in items {
            let key: String
            let label: String
            if let date = item.date {
                if calendar.isDateInToday(date) {
                    key = "today"
                    label = "今天"
                } else if calendar.isDateInYesterday(date) {
                    key = "yesterday"
                    label = "昨天"
                } else {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "zh_CN")
                    formatter.dateFormat = calendar.isDate(date, equalTo: Date(), toGranularity: .year)
                        ? "M月d日"
                        : "yyyy年M月d日"
                    key = "day-\(formatter.string(from: date))"
                    label = formatter.string(from: date)
                }
            } else {
                key = "older"
                label = "更早"
            }

            if buckets[key] == nil {
                order.append(key)
                labels[key] = label
            }
            buckets[key, default: []].append(item)
        }

        return order.map { key in
            NotifGroup(id: key, title: labels[key] ?? "更早", items: buckets[key] ?? [])
        }
    }

    /// 旧日期已有分组标题，卡片右上角不再重复日期，改为具体时刻。
    private func cardTime(_ item: NotifItem, group: NotifGroup) -> String {
        // 「昨天」分组下再显示「3 小时前」会跨过零点，读起来自相矛盾；统一改成具体时刻。
        guard group.id == "yesterday" || group.id.hasPrefix("day-"),
              let date = item.date else { return item.time }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// 离开通知页即视为已读，保留列表内的绿点直到用户离开。
    private func markAllSeen() {
        guard let newest = items.compactMap(\.date).max() else { return }
        let stamp = max(newest, lastSeenAt ?? .distantPast)
        lastSeenAt = stamp
        UserDefaults.standard.set(stamp, forKey: Self.lastSeenKey)
    }

    private func loadBadgeItems(client: SupabaseClient, userId: UUID) async -> NotifLoadOutcome {
        let badges: [UserBadge]
        do {
            badges = try await client
                .from("user_badges")
                .select("id, badge_id, ride_id, earned_at")
                .eq("user_id", value: userId)
                .order("earned_at", ascending: false)
                .limit(10)
                .execute()
                .value
        } catch {
            return .failure(error)
        }
        guard !badges.isEmpty else { return .success([]) }

        let badgeIds = Array(Set(badges.map(\.badgeId)))
        let badgeNames: [BadgeNameRow] = (try? await client
            .from("badges")
            .select("id, name")
            .in("id", values: badgeIds)
            .execute()
            .value) ?? []
        let names = Dictionary(uniqueKeysWithValues: badgeNames.map { ($0.id, $0.name) })

        return .success(badges.map { badge in
            let date = ISO8601DateFormatter.wellwayDate(from: badge.earnedAt)
            return NotifItem(
                id: "badge-\(badge.id)",
                kind: .badge,
                title: "获得徽章",
                body: "你获得了「\(names[badge.badgeId] ?? "路线徽章")」",
                time: relativeTime(date),
                date: date,
                targetBadgeId: badge.badgeId
            )
        })
    }

    private func loadRideItems(client: SupabaseClient, userId: UUID) async -> NotifLoadOutcome {
        let rides: [RideRecord]
        do {
            rides = try await selectCompletedRides(client: client, userId: userId, includeName: true)
        } catch {
            do {
                rides = try await selectCompletedRides(client: client, userId: userId, includeName: false)
            } catch {
                return .failure(error)
            }
        }
        guard !rides.isEmpty else { return .success([]) }

        let routeIds = Array(Set(rides.compactMap(\.routeId)))
        let routeRows: [RouteNameRow] = routeIds.isEmpty ? [] : ((try? await client
            .from("routes")
            .select("id, name")
            .in("id", values: routeIds)
            .execute()
            .value) ?? [])
        let routeNames = Dictionary(uniqueKeysWithValues: routeRows.map { ($0.id, $0.name) })

        // 一分钟内、没轨迹也没移动的骑行多半是误触开始/停止，记录列表里保留即可；
        // 放进通知流会变成一屏「骑行已结束 · 未记录有效轨迹」，把真正的打卡和徽章挤下去。
        return .success(rides.filter { ride in
            !(ride.distanceM < 100 && ride.durationS < 60 && !ride.hasRecordedTrack)
        }.map { ride in
            let rawDate = ride.endedAt ?? ride.startedAt
            let date = ISO8601DateFormatter.wellwayDate(from: rawDate)
            let fallbackName = ride.routeId.flatMap { routeNames[$0] }
            let name = ride.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = (name?.isEmpty == false ? name! : (fallbackName ?? "本次骑行"))
            let metric: String
            if ride.distanceM >= 100 {
                metric = String(format: "%.1f km", Double(ride.distanceM) / 1000)
            } else if ride.durationS > 0 {
                // 与记录列表共用同一个格式化器：10 分 8 秒统一成「10 分 8 秒」，
                // 不再在这里取整成「10 分钟」，避免同一段骑行两处写法不一致。
                metric = RideDurationText.words(seconds: ride.durationS)
            } else {
                metric = "已记录"
            }
            return NotifItem(
                id: "ride-\(ride.id.uuidString)",
                kind: .ride,
                title: ride.hasRecordedTrack ? "骑行完成" : "骑行已结束",
                body: ride.hasRecordedTrack
                    ? "「\(displayName)」轨迹已保存，\(metric)"
                    : "「\(displayName)」未记录有效轨迹，\(metric)",
                time: relativeTime(date),
                date: date,
                targetRecordId: ride.id
            )
        })
    }

    private func selectCompletedRides(
        client: SupabaseClient,
        userId: UUID,
        includeName: Bool
    ) async throws -> [RideRecord] {
        let columns = includeName
            ? "id, name, user_id, route_id, vehicle_id, started_at, ended_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh, elevation_gain_m, status"
            : "id, user_id, route_id, vehicle_id, started_at, ended_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh, elevation_gain_m, status"
        return try await client
            .from("ride_records")
            .select(columns)
            .eq("user_id", value: userId)
            .eq("status", value: "completed")
            .order("ended_at", ascending: false)
            .limit(10)
            .execute()
            .value
    }

    private func loadCheckinItems(client: SupabaseClient, userId: UUID) async -> NotifLoadOutcome {
        let checkins: [RideCheckin]
        do {
            checkins = try await client
                .from("ride_checkins")
                .select("id, ride_id, checkpoint_id, checked_at")
                .eq("user_id", value: userId)
                .order("checked_at", ascending: false)
                .limit(20)
                .execute()
                .value
        } catch {
            return .failure(error)
        }
        guard !checkins.isEmpty else { return .success([]) }

        let checkpointIds = Array(Set(checkins.map(\.checkpointId)))
        let checkpointRows: [CheckpointNameRow] = (try? await client
            .from("checkpoints")
            .select("id, name")
            .in("id", values: checkpointIds)
            .execute()
            .value) ?? []
        let names = Dictionary(uniqueKeysWithValues: checkpointRows.map { ($0.id, $0.name) })

        return .success(checkins.map { checkin in
            let date = ISO8601DateFormatter.wellwayDate(from: checkin.checkedAt)
            let name = names[checkin.checkpointId] ?? "打卡点"
            return NotifItem(
                id: "checkin-\(checkin.id)",
                kind: .checkin,
                title: "打卡完成",
                body: "已打卡「\(name)」",
                time: relativeTime(date),
                date: date,
                targetRecordId: checkin.rideId
            )
        })
    }

    private func relativeTime(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.wellwayDate(from: iso) else { return "" }
        return relativeTime(date)
    }

    private func relativeTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 7 * 86400 { return "\(Int(interval / 86400)) 天前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
            ? "M月d日"
            : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - 路线骑手匿名数量

/// 路线详情里的「附近骑手」：只显示该路线当前骑行中的匿名人数，
/// 不返回车型、徽章、昵称、距离等可识别信息。
struct RidersView: View {
    @Environment(AuthManager.self) private var auth
    let route: Route
    let checkpoints: [Checkpoint]

    @State private var riderCount = 0
    @State private var isLoading = true
    @State private var loadFailed = false
    /// 服务端的「正在骑行」函数当前不可用时，退回到「计划前往同一终点」的人数；
    /// 两者口径不同，必须用不同的文案说清楚，不能混着显示。
    @State private var countsPlans = false

    /// 终点坐标(按 seq 取最后一个带坐标的打卡点)，用于计划人数统计。
    private var destCoordinate: (lat: Double, lng: Double)? {
        checkpoints
            .sorted { $0.seq < $1.seq }
            .compactMap { cp -> (Double, Double)? in
                guard let lat = cp.lat, let lng = cp.lng else { return nil }
                return (lat, lng)
            }
            .last
    }

    /// 这一页的全部内容就是「人数」或「没有骑手」一句话：两者都垂直居中，
    /// 只有加载态保持顶部对齐，避免加载结束的一瞬间整块内容上下跳。
    private var centersContent: Bool {
        !isLoading
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "路线骑手")
            GeometryReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if isLoading {
                            VStack(alignment: .leading, spacing: 16) {
                                Capsule().fill(Theme.lightField).frame(width: 92, height: 12)
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.lightField).frame(width: 74, height: 52)
                                Capsule().fill(Theme.lightField).frame(width: 120, height: 12)
                            }
                            .padding(.top, 16)
                        } else if loadFailed {
                            NetworkErrorView(message: "骑手统计暂时无法更新") {
                                Task { await load() }
                            }
                        } else if riderCount == 0 {
                            DesignEmptyState(
                                icon: "person.2",
                                title: countsPlans ? "最近两小时暂无骑手计划前往" : "这条路线暂时没有骑手",
                                message: countsPlans
                                    ? "路线热度会随骑手计划更新"
                                    : "开始骑行并保持定位后，这里只显示匿名人数"
                            )
                        } else {
                            // 居中后不再套浅灰卡片：一块灰底浮在屏幕正中会像没加载完的组件；
                            // 数字本身就是这一页唯一的内容，直接落在白底上更稳。
                            VStack(spacing: 10) {
                                Text(countsPlans ? "最近两小时计划前往" : "正在这条路线骑行")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.textSecondary)
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(riderCount)")
                                        .font(.system(size: 56, weight: .bold).monospacedDigit())
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("位骑手")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .motionAppear(delay: 0.05)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    // 本页 hidesAppTabBar()，底部没有悬浮 Tab 栏：
                    // 之前沿用了别的页面的 108pt 让位，空态会比可视区中心高 54pt 以上。
                    .frame(
                        maxWidth: .infinity,
                        minHeight: proxy.size.height,
                        alignment: centersContent ? .center : .top
                    )
                }
                .refreshable { await load() }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Text("人数为匿名汇总，存在 GPS 延迟与定位误差，不可作为道路会车、避险判断依据。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                        .background(Color.white.overlay(alignment: .top) {
                            Rectangle().fill(Theme.separator).frame(height: 1)
                        })
                }
            }
        }
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .task { await load() }
    }

    private func load() async {
        isLoading = riderCount == 0
        loadFailed = false
        defer { isLoading = false }
        if let count = await TripService.ridersOnRoute(auth.client, routeId: route.id) {
            riderCount = count
            countsPlans = false
            return
        }
        // 「正在骑行」依赖的位置心跳 RPC 还没上线时，不要让整页停在错误态：
        // 退回到同一目的地两小时内的出发计划数，文案同步改口径。
        if let dest = destCoordinate,
           let result = await TripService.riderCountToDest(
               auth.client, destLat: dest.lat, destLon: dest.lng
           ) {
            riderCount = result.count
            countsPlans = true
        } else {
            loadFailed = true
        }
    }
}


// MARK: - 队伍(Figma Tab「队伍」)

/// 对向：附近匿名骑手汇总（只显示数量，不展示任何骑手身份）
struct TeamRidersView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    var title = "对向"
    var showsBack = true
    @State private var counts: RiderNearbyCounts?
    @State private var isLoading = true
    @State private var locationUnavailable = false
    @State private var locationDenied = false
    @State private var loadFailed = false
    @State private var locationFetcher = OneShotLocationFetcher()
    @State private var lastUpdated = Date()
    @State private var hasLoadedOnce = false
    @State private var currentCoordinate: CLLocationCoordinate2D?
    @State private var coverageCamera: MapCameraPosition = .automatic

    private let radiusM = 2_000

    /// 仅错误态交给外层垂直居中；空态内部保留顶部状态行，
    /// 避免「统计范围 / 更新时间」跟着空态一起漂到屏幕中间。
    private var centersContent: Bool {
        !isLoading && loadFailed
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: title, showsBack: showsBack, compact: true)
                .background(Color.white)

            GeometryReader { proxy in
                // SE 这类矮屏：统计范围地图在首屏会被底部免责声明切掉一半，
                // 压缩数字区间距并降低地图高度，让整块地图落在首屏内。
                // SE 的实际可视高度约 500pt（667 减去页头与免责声明），
                // 460 的阈值在真机上永远命中不了；560 才能把 Pro（约 660）区分开。
                let isShort = proxy.size.height < 560
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoading {
                            VStack(spacing: 12) {
                                RiderCountSkeleton()
                                Text("正在获取位置，并统计附近骑手…")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        } else if loadFailed {
                            NetworkErrorView(message: "附近骑手统计暂时无法更新") {
                                Task { await load() }
                            }
                        } else if let counts {
                            summaryCard(counts, compact: isShort)
                                .padding(.horizontal, 20)
                                .motionAppear(delay: 0.05)
                            if counts.total == 0 {
                                emptyRidersRow
                                    .padding(.horizontal, 20)
                                    .motionAppear(delay: 0.10)
                            }
                            // 有数字时地图同样吃掉剩余高度：200pt 的固定高度会在
                            // 免责声明上方留下近 200pt 空白，整页看着像没做完。
                            // 矮屏放不下 330pt 地图，硬撑会把地图底边切在免责声明上；
                            // 矮屏只在空态（内容更少）时才让地图长到 200pt。
                            coverageSection(
                                expands: isShort ? counts.total == 0 : true,
                                compact: isShort,
                                // 零结果时上方没有大数字和三栏指标，地图可以多占一截，
                                // 否则首屏底部会空出 100pt 以上。
                                roomy: counts.total == 0
                            )
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .motionAppear(delay: 0.14)
                        } else {
                            // 即便没有骑手，也让用户知道统计范围与更新时间，
                            // 而不是只看到一句空话
                            VStack(spacing: 0) {
                                if !locationDenied && !locationUnavailable {
                                    scopeLine
                                        .padding(.top, 4)
                                }
                                Spacer(minLength: 20)
                                emptyState
                                    .motionAppear(delay: 0.05)
                                Spacer(minLength: 20)
                            }
                            .frame(
                                maxWidth: .infinity,
                                // 减去上下内边距(8)与悬浮 Tab 栏让位(108)：否则这块
                                // 会比可视区高 80pt，空态被顶到偏上、整页还能空滚一段。
                                minHeight: max(0, proxy.size.height - 124)
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 8)
                    // 对向是 Tab 根页面；统计范围地图可能滚到悬浮 Tab 栏下方。
                    .padding(.bottom, 108)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: proxy.size.height,
                        alignment: centersContent ? .center : .top
                    )
                }
                .refreshable { await load() }
            }
            .background(Color.white)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                disclaimer
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 10)
                    .background(Color.white.overlay(alignment: .top) {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    })
            }
        }
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            let debugArgs = ProcessInfo.processInfo.arguments
            if debugArgs.contains("-teamdenied") {
                locationDenied = true
                loadFailed = false
                counts = nil
                isLoading = false
                return
            }
            if debugArgs.contains("-teamfailed") {
                loadFailed = true
                counts = nil
                isLoading = false
                return
            }
            if ProcessInfo.processInfo.arguments.contains("-teamrows") {
                counts = RiderNearbyCounts(
                    total: 7,
                    behindSameDirection: 4,
                    oncoming: 3,
                    unknownDirection: 0,
                    bearing: 90,
                    radiusM: 2_000,
                    disclaimer: "位置统计存在 GPS 延迟与定位误差，骑手数量仅为匿名汇总，不可作为道路会车、避险判断依据。"
                )
                isLoading = false
                lastUpdated = Date()
                // 演示数据也要带上坐标，否则统计范围地图整块不渲染，
                // 截图评审时看到的版式和真实使用不一致。
                let demo = CLLocationCoordinate2D(latitude: 39.9087, longitude: 116.3975)
                currentCoordinate = demo
                coverageCamera = .region(MKCoordinateRegion(
                    center: demo,
                    latitudinalMeters: 5_200,
                    longitudinalMeters: 5_200
                ))
                // 演示数据不标记为「已加载」，避免 scenePhase 回调把它覆盖成真实空态
                return
            }
            await load()
        }
        // 卡片上写着「刚刚更新 / N 分钟前更新」，所以停留期间必须真的在刷新，
        // 否则数字会越来越旧却仍显示为最新。
        .task {
            let debugArgs = ProcessInfo.processInfo.arguments
            if debugArgs.contains("-teamrows") || debugArgs.contains("-teamdenied") || debugArgs.contains("-teamfailed") { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled else { break }
                guard scenePhase == .active else { continue }
                await load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 启动时 .task 已在加载，这里只处理「从后台回到前台」的刷新，
            // 避免首次进入重复请求定位导致骨架屏闪烁。
            guard phase == .active, hasLoadedOnce, !isLoading else { return }
            Task { await load() }
        }
        .pageMark(66)
    }

    private func summaryCard(_ counts: RiderNearbyCounts, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Theme.success)
                    .frame(width: 5, height: 5)
            Text("\(counts.radiusM / 1_000) km 内")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    // 屏幕上「2 km 内」更紧凑，读屏要念「公里」。
                    .accessibilityLabel("\(counts.radiusM / 1_000) 公里内")
                Spacer()
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    Text(updatedText)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle())
                .accessibilityLabel("刷新附近骑手统计")
            }

            if counts.total == 0 {
                // 0 本身就是一个结论，不必再拆成三个 0 做方向统计：
                // 空态直接说清"现在没有"和"什么时候会有"，比三行零更有信息量。
                VStack(alignment: .leading, spacing: 6) {
                    Text("附近暂无骑手")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    // 下一行就是「先选一条路线出发 / 出发后自动更新」；
                    // 这里再补一句「开始骑行后才有数据」等于同一句话说三遍。
                }
                .padding(.top, compact ? 8 : 14)
            } else {
                // 说明文字另起一行并与数字左对齐：跟在单位后面会形成缩进，
                // 数字越大缩进越明显，读起来像两段不相干的内容。
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(counts.total)")
                            .font(.system(size: 56, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Text("位骑手")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text("正在附近骑行")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.top, compact ? 8 : 14)

                HStack(spacing: 0) {
                    directionMetric(
                        counts.hasDirection ? counts.oncoming : nil,
                        label: "对向驶来",
                        dot: Theme.success
                    )
                    metricDivider
                    directionMetric(
                        counts.hasDirection ? counts.behindSameDirection : nil,
                        label: "后方同向",
                        dot: Theme.textPrimary.opacity(0.22)
                    )
                }
                .padding(.top, compact ? 12 : 18)

                if counts.hasDirection {
                    directionBar(counts)
                        .padding(.top, compact ? 10 : 14)
                        .accessibilityHidden(true)
                    // 方向条里还有一段浅灰（方向未知），文字侧必须交代，
                    // 否则用户会把两段颜色读成「对向 / 同向」。
                    if counts.unknownDirection > 0 {
                        Text("另有 \(counts.unknownDirection) 位方向未知")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 6)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "location.north.line")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text("开始骑行并移动一段距离后，方向统计会在这里更新")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 14)
                }
            }
        }
        .padding(.top, 2)
    }

    private func directionBar(_ counts: RiderNearbyCounts) -> some View {
        let oncoming = counts.oncoming ?? 0
        let behind = counts.behindSameDirection ?? 0
        let unknown = counts.unknownDirection
        return GeometryReader { proxy in
            let total = max(1, oncoming + behind + unknown)
            let gap: CGFloat = 2
            let available = max(0, proxy.size.width - gap * 2)
            HStack(spacing: gap) {
                if oncoming > 0 {
                    Capsule()
                        .fill(Theme.success)
                        .frame(width: available * CGFloat(oncoming) / CGFloat(total))
                }
                if behind > 0 {
                    Capsule()
                        .fill(Theme.textPrimary.opacity(0.22))
                        .frame(width: available * CGFloat(behind) / CGFloat(total))
                }
                if unknown > 0 {
                    Capsule()
                        .fill(Theme.separator)
                        .frame(width: available * CGFloat(unknown) / CGFloat(total))
                }
            }
        }
        .frame(height: 5)
    }

    /// 空态时页面内容少，让地图吃掉剩余高度，避免下方出现一大块空白；
    /// 有骑手数据时保持固定 200pt，数字和方向统计才是主角。
    @ViewBuilder
    private func coverageSection(expands: Bool = false, compact: Bool = false, roomy: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 半径已经在页面顶部的「2 km 内」说过一次，这里再印一遍只会
            // 在同一屏里重复同一个数字；地图本身已经把范围画出来了。
            Text("统计范围")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("统计范围 \(radiusM / 1_000) 公里")

            // 刷新间隔是实现细节，「刚刚更新 / N 分钟前」已经说明了数据新鲜度；
            // 把 45 秒写在界面上只会变成一行没人读的技术信息。
            Text("只统计人数，不显示其他骑手位置")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 2)

            if let coordinate = currentCoordinate {
                // MapKit 的图层不吃 overlay 上的 clipShape：直接给地图本体圆角，
                // 否则统计范围地图会是直角，和全站 12pt 圆角不一致。
                Group {
                        Map(position: $coverageCamera, interactionModes: []) {
                            MapCircle(center: coordinate, radius: CLLocationDistance(radiusM))
                                .foregroundStyle(Theme.success.opacity(0.08))
                                .stroke(Theme.success.opacity(0.55), lineWidth: 1.2)

                            Annotation("", coordinate: coordinate, anchor: .center) {
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 22, height: 22)
                                        .shadow(color: .black.opacity(0.14), radius: 4, y: 1)
                                    Circle()
                                        .fill(Theme.success)
                                        .frame(width: 10, height: 10)
                                }
                                .accessibilityLabel("你的位置")
                            }
                        }
                        .mapStyle(.standard(
                            elevation: .flat,
                            emphasis: .muted,
                            pointsOfInterest: .excludingAll,
                            showsTraffic: false
                        ))
                        // 与骑行中/记录详情的深色底图统一；浅色地图的绿地和水会压过品牌绿圈。
                        .environment(\.colorScheme, .dark)
                        .mapControlVisibility(.hidden)
                }
                // 矮屏零结果时地图是页面主体，给到 200pt 正好落在免责声明上方；
                // 有骑手数据时数字才是主角，地图收在 140pt。
                .frame(height: compact ? (expands ? 200 : 140) : (expands ? (roomy ? 330 : 280) : 200))
                // 同骑行页：MapKit 的 "Legal / 高德地图" 贴着底边，12pt 圆角会切掉下沿。
                .padding(.bottom, 6)
                .background(Theme.darkBackground)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                // MapKit 的原生图层不吃 clipShape / mask：用同色遮住四角，视觉上等于圆角
                .overlay { MapCornerCover(cornerRadius: 12) }
                .accessibilityLabel("你的位置与方圆 2 公里统计范围")
            }
        }
    }

    /// 零结果不是一个需要占满屏幕的异常，而是一条可以继续操作的信息。
    private var emptyRidersRow: some View {
        Button {
            NotificationCenter.default.post(name: .switchToRoutesTab, object: nil)
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("先选一条路线出发")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("出发后会自动更新附近骑手统计")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityHint("前往路线列表")
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    /// 数值下方带一个与方向条同色的圆点：没有图例时，绿/灰各自代表哪个方向
    /// 只能靠猜；颜色一旦写进图表，就必须在文字侧说明它是什么。
    private func directionMetric(_ value: Int?, label: String, dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 24, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            // 色点放在文字后面：放在前面会把 12pt 标签整体右移 12pt，
            // 和上方的 24pt 数字左边缘对不齐。
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 38)
            .padding(.horizontal, 18)
    }

    /// 统计范围 + 更新时间（空态也显示，避免「附近没有人」缺少上下文）
    private var scopeLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Theme.success)
                .frame(width: 5, height: 5)
            Text("\(radiusM / 1_000) km 内")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("\(radiusM / 1_000) 公里内")
            Spacer(minLength: 8)
            Text(updatedText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            DesignEmptyState(
                // 定位相关的问题用定位图标：⇄ 表达的是「对向」这个概念，
                // 放在「定位权限未开启」上只会让人先愣一下。
                icon: locationDenied || locationUnavailable ? "location.slash" : "arrow.left.arrow.right",
                title: locationDenied
                    ? "定位权限未开启"
                    : (locationUnavailable ? "暂时无法获取位置" : "附近暂无骑手"),
                message: locationDenied
                    ? "开启定位权限后，这里会显示\n附近匿名骑手的数量"
                    : (locationUnavailable
                        ? "请到开阔处或稍后重试。\n定位恢复后会自动刷新。"
                        : "开始骑行并保持定位，这里只显示匿名汇总数量")
            )

            if locationDenied {
                emptyActionButton("去设置开启定位") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                }
            } else if locationUnavailable {
                emptyActionButton("重新获取") {
                    Task { await load() }
                }
            } else {
                emptyActionButton("去找一条路线") {
                    NotificationCenter.default.post(name: .switchToRoutesTab, object: nil)
                }
            }
        }
        // 外层滚动容器已统一加 20pt 边距，这里不能再叠一层，
        // 否则定位失败空态会比统计范围、地图多缩进 24pt。
    }

    /// 三个空态（无骑手 / 定位关闭 / 定位失败）共用同一个主按钮样式，
    /// 分散成三份后任何一次改高度都会漏掉其中两处。
    /// 与全站空态主行动同一档：16pt / 52pt / 通栏，不用 200×46 的小黑块。
    private func emptyActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
    }

    private var disclaimer: some View {
        Text("位置统计存在 GPS 延迟与定位误差，骑手数量仅作参考。\n不可作为道路会车、避险判断依据。")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .lineSpacing(2)
            .padding(.horizontal, 2)
    }

    private var updatedText: String {
        let minutes = Int(Date().timeIntervalSince(lastUpdated) / 60)
        if minutes < 1 { return "刚刚更新" }
        return "\(minutes) 分钟前更新"
    }

    private func load() async {
        isLoading = counts == nil
        loadFailed = false
        lastUpdated = Date()
        defer {
            isLoading = false
            hasLoadedOnce = true
        }

        let status = CLLocationManager().authorizationStatus
        locationDenied = status == .denied || status == .restricted
        guard let location = await locationFetcher.fetchLocation() else {
            locationUnavailable = true
            currentCoordinate = nil
            counts = nil
            return
        }
        locationDenied = false
        locationUnavailable = false
        currentCoordinate = location.coordinate
        coverageCamera = .region(MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 5_200,
            longitudinalMeters: 5_200
        ))
        let course = location.course >= 0 ? location.course : nil
        let result = await TripService.ridersNearby(
            auth.client,
            lat: location.coordinate.latitude,
            lon: location.coordinate.longitude,
            bearing: course,
            radiusM: radiusM
        )
        counts = result
        loadFailed = result == nil
        lastUpdated = Date()
    }
}

/// 对向页加载骨架：与真实汇总卡同构
private struct RiderCountSkeleton: View {
    private let block = Theme.cardStroke

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Capsule().fill(block).frame(width: 82, height: 12)
                Spacer()
                Capsule().fill(block).frame(width: 64, height: 12)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(block)
                    .frame(width: 72, height: 52)
                VStack(alignment: .leading, spacing: 7) {
                    Capsule().fill(block).frame(width: 64, height: 14)
                    Capsule().fill(block).frame(width: 88, height: 11)
                }
            }
            HStack(spacing: 20) {
                ForEach(0..<2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(block).frame(width: 42, height: 22)
                        Capsule().fill(block).frame(width: 58, height: 11)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// MapKit 的原生图层不响应 clipShape / mask：用页面底色遮住四角，等效出圆角
private struct MapCornerCover: View {
    let cornerRadius: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color.white)
            .mask {
                Rectangle()
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}
