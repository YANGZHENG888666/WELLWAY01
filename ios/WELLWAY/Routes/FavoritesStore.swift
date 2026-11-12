import Foundation
import Observation
import Supabase

/// 路线收藏：优先云端 route_favorites 表；表未建/无权限时回退本地 UserDefaults(功能不中断)
@MainActor
@Observable
final class FavoritesStore {
    private(set) var favoriteRouteIds: Set<Int> = []
    private(set) var cloudAvailable = true

    private let client: SupabaseClient
    private let userId: UUID
    private var localKey: String { "routeFavorites-\(userId.uuidString)" }
    private var pendingKey: String { "routeFavoritesPending-\(userId.uuidString)" }
    /// 尚未同步到云端的收藏变更：true=收藏，false=取消收藏。
    /// 持久化后即使杀进程也会在下次加载时重试，避免本地收藏被云端旧数据覆盖。
    private var pendingMutations: [Int: Bool] = [:]

    init(client: SupabaseClient, userId: UUID) {
        self.client = client
        self.userId = userId
        favoriteRouteIds = Set((UserDefaults.standard.stringArray(forKey: localKey) ?? []).compactMap { Int($0) })
        if let stored = UserDefaults.standard.dictionary(forKey: pendingKey) {
            pendingMutations = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
                guard let routeId = Int(key), let shouldFavorite = value as? Bool else { return nil }
                return (routeId, shouldFavorite)
            })
        }
    }

    func load() async {
        do {
            let rows: [FavoriteRow] = try await client
                .from("route_favorites")
                .select("route_id")
                .eq("user_id", value: userId)
                .execute()
                .value
            var merged = Set(rows.map(\.routeId))
            // 云端返回后，再叠加尚未同步成功的本地意图，避免收藏闪烁或被覆盖。
            for (routeId, shouldFavorite) in pendingMutations {
                if shouldFavorite {
                    merged.insert(routeId)
                } else {
                    merged.remove(routeId)
                }
            }
            favoriteRouteIds = merged
            saveLocal()
            cloudAvailable = true
            await flushPendingMutations()
        } catch {
            // 表未建/无权限 → 回退本地，保证收藏功能可用
            cloudAvailable = false
            favoriteRouteIds = Set((UserDefaults.standard.stringArray(forKey: localKey) ?? []).compactMap { Int($0) })
        }
    }

    func isFavorite(_ routeId: Int) -> Bool {
        favoriteRouteIds.contains(routeId)
    }

    func toggle(_ routeId: Int) async {
        let shouldFavorite = !favoriteRouteIds.contains(routeId)
        if shouldFavorite {
            favoriteRouteIds.insert(routeId)
        } else {
            favoriteRouteIds.remove(routeId)
        }
        pendingMutations[routeId] = shouldFavorite
        saveLocal()
        savePendingMutations()
        await flushPendingMutations()
    }

    private func saveLocal() {
        UserDefaults.standard.set(favoriteRouteIds.map(String.init).sorted(), forKey: localKey)
    }

    private func savePendingMutations() {
        let stored = Dictionary(uniqueKeysWithValues: pendingMutations.map { (String($0.key), $0.value) })
        UserDefaults.standard.set(stored, forKey: pendingKey)
    }

    private func flushPendingMutations() async {
        guard !pendingMutations.isEmpty else { return }
        let snapshot = pendingMutations
        var synced: [Int] = []
        var failed = false
        for (routeId, shouldFavorite) in snapshot {
            do {
                if shouldFavorite {
                    // 先删再插：即使上一次请求实际成功但响应丢失，也不会因唯一键冲突永久卡住队列。
                    try await client.from("route_favorites")
                        .delete()
                        .eq("user_id", value: userId)
                        .eq("route_id", value: routeId)
                        .execute()
                    try await client.from("route_favorites")
                        .insert(FavoriteInsert(userId: userId, routeId: routeId))
                        .execute()
                } else {
                    try await client.from("route_favorites")
                        .delete()
                        .eq("user_id", value: userId)
                        .eq("route_id", value: routeId)
                        .execute()
                }
                // 请求期间如果用户又切换了同一路线，保留更新的意图交给下一轮。
                if pendingMutations[routeId] == shouldFavorite {
                    synced.append(routeId)
                }
            } catch {
                failed = true
            }
        }
        for routeId in synced {
            pendingMutations.removeValue(forKey: routeId)
        }
        savePendingMutations()
        if failed {
            cloudAvailable = false
        } else if pendingMutations.isEmpty {
            cloudAvailable = true
        }
        if !synced.isEmpty, !pendingMutations.isEmpty {
            await flushPendingMutations()
        }
    }
}

private struct FavoriteRow: Codable {
    let routeId: Int
    enum CodingKeys: String, CodingKey {
        case routeId = "route_id"
    }
}

private struct FavoriteInsert: Encodable {
    let userId: UUID
    let routeId: Int
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case routeId = "route_id"
    }
}
