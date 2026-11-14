import SwiftUI

/// 我的收藏：只展示当前账号收藏的路线，复用路线列表的卡片与详情页。
/// 收藏状态与详情页共用同一个 `FavoritesStore`，取消收藏返回后列表立即同步。
struct FavoriteRoutesView: View {
    @Environment(AuthManager.self) private var auth

    @State private var favorites: FavoritesStore?
    @State private var routes: [Route] = []
    @State private var checkpointsByRoute: [Int: [Checkpoint]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var checkpointWarning: String?

    private var favoriteRoutes: [Route] {
        guard let favorites else { return [] }
        return routes.filter { favorites.isFavorite($0.id) }
    }

    private var showsEmptyAction: Bool {
        !isLoading && errorMessage == nil && favoriteRoutes.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "我的收藏")
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .toolbar(.hidden, for: .navigationBar)
        .hidesAppTabBar()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsEmptyAction {
                emptyAction
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(Color.white)
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, routes.isEmpty {
            NetworkErrorView(message: errorMessage) {
                Task { await load() }
            }
            // 错误态高度固定；不撑满剩余空间时，外层 VStack 会在整屏居中，
            // 页头会跟着掉到屏幕中部，与空态/列表态不一致。
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isLoading, routes.isEmpty {
            RouteSkeletonList(dark: false)
        } else if favoriteRoutes.isEmpty {
            VStack {
                Spacer(minLength: 0)
                DesignEmptyState(
                    icon: "star",
                    title: "还没有收藏路线",
                    message: "在路线详情点亮星标后，收藏的路线会显示在这里"
                )
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                if errorMessage != nil {
                    InlineRefreshNotice(message: "收藏刷新失败，当前显示上次数据") {
                        Task { await load() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                } else if let checkpointWarning {
                    InlineRefreshNotice(message: checkpointWarning) {
                        Task { await load() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
                listContent
            }
        }
    }

    private var listContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 10) {
                ForEach(favoriteRoutes) { route in
                    NavigationLink {
                        RouteDetailView(
                            route: route,
                            checkpoints: checkpointsByRoute[route.id] ?? [],
                            favoritesStore: favorites
                        )
                    } label: {
                        RouteListCard(
                            route: route,
                            checkpoints: checkpointsByRoute[route.id] ?? [],
                            subtitle: subtitleText(route),
                            accessibilityLabel: accessibilityText(route),
                            isFavorite: true
                        )
                    }
                    .buttonStyle(CardPressStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 120)
        }
        .scrollBounceBehavior(.always, axes: .vertical)
        .refreshable { await load() }
    }

    private var emptyAction: some View {
        Button {
            NotificationCenter.default.post(name: .switchToRoutesTab, object: nil)
        } label: {
            Text("浏览路线")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .accessibilityHint("前往路线页挑选并收藏路线")
    }

    // MARK: - 数据

    private func load() async {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-favoriteserror") {
            isLoading = false
            errorMessage = "服务暂时不可用，请稍后重试"
            checkpointWarning = nil
            return
        }
        if args.contains("-favoritesempty") {
            routes = []
            checkpointsByRoute = [:]
            isLoading = false
            errorMessage = nil
            checkpointWarning = nil
            return
        }
        guard let userId = auth.user?.id else {
            isLoading = false
            errorMessage = "登录状态已失效，请重新登录"
            return
        }

        let isFirstLoad = routes.isEmpty
        if isFirstLoad { isLoading = true }
        defer { if isFirstLoad { isLoading = false } }
        errorMessage = nil
        checkpointWarning = nil

        let store: FavoritesStore
        if let favorites {
            store = favorites
        } else {
            store = FavoritesStore(client: auth.client, userId: userId)
            favorites = store
        }
        await store.load()

        let ids = store.favoriteRouteIds.sorted()
        guard !ids.isEmpty else {
            routes = []
            checkpointsByRoute = [:]
            return
        }

        let client = auth.client
        do {
            let fetched: [Route] = try await client
                .from("routes")
                .select("id, name, start_name, end_name, distance_m, elevation_m, difficulty, duration_min, map_url, cover_image_url, province, city")
                .in("id", values: ids)
                .eq("is_active", value: true)
                .order("id")
                .execute()
                .value
            routes = fetched
        } catch {
            errorMessage = error.wellwayUserMessage
            return
        }

        guard !routes.isEmpty else {
            checkpointsByRoute = [:]
            return
        }

        do {
            let checkpoints: [Checkpoint] = try await client
                .from("checkpoints")
                .select("id, route_id, name, seq, lat, lng, radius_m")
                .in("route_id", values: ids)
                .order("seq")
                .execute()
                .value
            var grouped: [Int: [Checkpoint]] = [:]
            for checkpoint in checkpoints {
                grouped[checkpoint.routeId, default: []].append(checkpoint)
            }
            checkpointsByRoute = grouped
        } catch {
            checkpointWarning = "路线坐标未更新，缩略图与导航可能不完整"
        }
    }

    // MARK: - 文案

    /// 与路线列表保持同一套副标题口径；省市缺失时回退到起终点。
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
        return parts.joined(separator: "，") + "，已收藏"
    }
}
