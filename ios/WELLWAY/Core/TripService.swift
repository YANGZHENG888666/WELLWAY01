import Foundation
import Supabase

// MARK: - 城市摩托车限行规则(GET /api/moto/rules → rpc/moto_rule)

struct MotoRule: Equatable {
    let found: Bool
    let cityCode: String?
    let cityName: String?
    let ruleText: String?
    let verified: Bool
    let sourceURL: String?
    let updatedAt: String?
    let disclaimer: String

    /// 有正文才算"收录";只有城市条目、正文为空时走"暂未收录"文案
    var hasRule: Bool { found && !(ruleText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

// MARK: - 附近匿名骑手统计(GET /api/rider/nearby → rpc/riders_nearby)

/// 只包含聚合数字：不返回任何骑手 id / 昵称 / 位置
struct RiderNearbyCounts: Equatable {
    let total: Int
    let behindSameDirection: Int?
    let oncoming: Int?
    let unknownDirection: Int
    let bearing: Double?
    let radiusM: Int
    let disclaimer: String

    /// 没有航向数据时只能给出总数。
    /// 除了两项是否为 nil，还要求服务端回显了「我的航向」：
    /// 旧版 riders_nearby 在无航向时会把两项算成 0（而不是 null），
    /// 只看 nil 会把「无法判断方向」误判成「都是 0 人」。
    var hasDirection: Bool { bearing != nil && (behindSameDirection != nil || oncoming != nil) }
}

// MARK: - 行程与匿名统计服务

/// 当前行程的跨页传递：出发页 `trip_plan_create` 拿到 id → 骑行中/结束时更新状态。
@MainActor
final class TripSession {
    static let shared = TripSession()
    private init() {}
    var tripId: UUID?
}

/// 对应《V1 内测接口清单》第 6 节(trip plan / status / rider count / rider nearby)。
/// 所有方法都**不抛错**:接口不存在(迁移未执行)或网络失败时返回 nil,
/// 调用方直接把对应卡片隐藏，不影响出发/骑行主流程。
enum TripService {
    /// 兜底免责文案(与后端 public.disclaimer_text() 同文，接口拿不到时用这份)
    static let fallbackDisclaimer = """
    提示：本 APP 仅展示城市摩托车限行政策文字摘要、天气参考。点击导航将跳转至高德地图，请手动切换高德摩托车路线。位置统计存在 GPS 延迟、定位误差；骑手数量仅匿名汇总数字，不可作为道路会车、避险判断依据。政策、天气存在变动，信息仅供参考，出行请以交管、气象官方公告为准，不可作为通行唯一依据。
    """

    // MARK: 限行

    static func motoRule(_ client: SupabaseClient, cityCode: String) async -> MotoRule? {
        let key = cityCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        do {
            let response = try await client
                .rpc("moto_rule", params: MotoRuleParams(pCityCode: key))
                .execute()
            guard let dto: MotoRuleDTO = JSONOne.decode(MotoRuleDTO.self, from: response.data) else { return nil }
            return dto.toModel()
        } catch {
            return nil
        }
    }

    // MARK: 行程

    @discardableResult
    static func createPlan(_ client: SupabaseClient,
                           destLat: Double,
                           destLon: Double,
                           destName: String?,
                           startLat: Double? = nil,
                           startLon: Double? = nil) async -> UUID? {
        do {
            let response = try await client
                .rpc("trip_plan_create", params: TripPlanCreateParams(
                    pDestLat: destLat,
                    pDestLon: destLon,
                    pDestName: destName,
                    pStartLat: startLat,
                    pStartLon: startLon
                ))
                .execute()
            guard let dto: TripPlanDTO = JSONOne.decode(TripPlanDTO.self, from: response.data) else { return nil }
            return UUID(uuidString: dto.tripId)
        } catch {
            return nil
        }
    }

    @discardableResult
    static func updateStatus(_ client: SupabaseClient, tripId: UUID, status: String) async -> Bool {
        do {
            let response = try await client
                .rpc("trip_status_update", params: TripStatusParams(pTripId: tripId.uuidString, pStatus: status))
                .execute()
            let dto: TripStatusDTO? = JSONOne.decode(TripStatusDTO.self, from: response.data)
            return dto?.status == status
        } catch {
            return false
        }
    }

    // MARK: 匿名统计

    /// 计划前往该目的地的骑手总人数(去重)
    static func riderCountToDest(_ client: SupabaseClient,
                                 destLat: Double,
                                 destLon: Double,
                                 radiusM: Int = 3000) async -> (count: Int, disclaimer: String)? {
        do {
            let response = try await client
                .rpc("rider_count_to_dest", params: RiderCountParams(
                    pDestLat: destLat, pDestLon: destLon, pRadiusM: radiusM
                ))
                .execute()
            guard let dto: RiderCountDTO = JSONOne.decode(RiderCountDTO.self, from: response.data) else { return nil }
            return (dto.count, dto.disclaimer ?? fallbackDisclaimer)
        } catch {
            return nil
        }
    }

    /// 当前路线正在骑行的匿名人数：服务端只返回聚合数字。
    static func ridersOnRoute(_ client: SupabaseClient, routeId: Int) async -> Int? {
        do {
            let response = try await client
                .rpc("riders_on_route", params: ActiveRiderCountParams(pRouteId: routeId))
                .execute()
            return JSONOne.decode(ActiveRiderCountDTO.self, from: response.data)?.count
        } catch {
            return nil
        }
    }

    /// 沿途附近：后方同向 / 对向驶来(只有数字)
    static func ridersNearby(_ client: SupabaseClient,
                             lat: Double,
                             lon: Double,
                             bearing: Double?,
                             radiusM: Int = 2000) async -> RiderNearbyCounts? {
        do {
            let response = try await client
                .rpc("riders_nearby", params: RiderNearbyParams(
                    pLat: lat, pLon: lon, pBearing: bearing, pRadiusM: radiusM
                ))
                .execute()
            return JSONOne.decode(RiderNearbyDTO.self, from: response.data)?.toModel()
        } catch {
            return nil
        }
    }
}

// MARK: - jsonb 返回值解码

/// PostgREST 对 `returns jsonb` 的函数回的是**单个 JSON 对象**,对 `returns setof` 回的是数组；
/// 这里两种都兼容，免得迁移里函数返回类型改动就把 App 解崩。
enum JSONOne {
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        let decoder = JSONDecoder()
        if let one = try? decoder.decode(T.self, from: data) { return one }
        if let many = try? decoder.decode([T].self, from: data) { return many.first }
        return nil
    }
}

// MARK: - 传输结构(jsonb → Decodable)

private struct MotoRuleParams: Encodable { let pCityCode: String
    enum CodingKeys: String, CodingKey { case pCityCode = "p_city_code" } }

private struct MotoRuleDTO: Decodable {
    let found: Bool?
    let cityCode: String?
    let cityName: String?
    let ruleText: String?
    let sourceURL: String?
    let verified: Bool?
    let updatedAt: String?
    let disclaimer: String?

    enum CodingKeys: String, CodingKey {
        case found, verified, disclaimer
        case cityCode = "city_code"
        case cityName = "city_name"
        case ruleText = "rule_text"
        case sourceURL = "source_url"
        case updatedAt = "updated_at"
    }

    func toModel() -> MotoRule {
        MotoRule(
            found: found ?? false,
            cityCode: cityCode,
            cityName: cityName,
            ruleText: ruleText,
            verified: verified ?? false,
            sourceURL: sourceURL,
            updatedAt: updatedAt,
            disclaimer: disclaimer ?? TripService.fallbackDisclaimer
        )
    }
}

private struct TripPlanCreateParams: Encodable {
    let pDestLat: Double
    let pDestLon: Double
    let pDestName: String?
    let pStartLat: Double?
    let pStartLon: Double?

    enum CodingKeys: String, CodingKey {
        case pDestLat = "p_dest_lat"
        case pDestLon = "p_dest_lon"
        case pDestName = "p_dest_name"
        case pStartLat = "p_start_lat"
        case pStartLon = "p_start_lon"
    }
}

private struct TripPlanDTO: Decodable {
    let tripId: String
    enum CodingKeys: String, CodingKey { case tripId = "trip_id" }
}

private struct TripStatusParams: Encodable {
    let pTripId: String
    let pStatus: String
    enum CodingKeys: String, CodingKey {
        case pTripId = "p_trip_id"
        case pStatus = "p_status"
    }
}

private struct TripStatusDTO: Decodable {
    let status: String?
}

private struct RiderCountParams: Encodable {
    let pDestLat: Double
    let pDestLon: Double
    let pRadiusM: Int
    enum CodingKeys: String, CodingKey {
        case pDestLat = "p_dest_lat"
        case pDestLon = "p_dest_lon"
        case pRadiusM = "p_radius_m"
    }
}

private struct RiderCountDTO: Decodable {
    let count: Int
    let disclaimer: String?
}

private struct ActiveRiderCountParams: Encodable {
    let pRouteId: Int
    enum CodingKeys: String, CodingKey { case pRouteId = "p_route_id" }
}

private struct ActiveRiderCountDTO: Decodable {
    let count: Int?
}

private struct RiderNearbyParams: Encodable {
    let pLat: Double
    let pLon: Double
    let pBearing: Double?
    let pRadiusM: Int
    enum CodingKeys: String, CodingKey {
        case pLat = "p_lat"
        case pLon = "p_lon"
        case pBearing = "p_bearing"
        case pRadiusM = "p_radius_m"
    }
}

private struct RiderNearbyDTO: Decodable {
    let total: Int?
    let behindSameDirection: Int?
    let oncoming: Int?
    let unknownDirection: Int?
    let bearing: Double?
    let radiusM: Int?
    let disclaimer: String?

    enum CodingKeys: String, CodingKey {
        case total, oncoming, bearing, disclaimer
        case behindSameDirection = "behind_same_direction"
        case unknownDirection = "unknown_direction"
        case radiusM = "radius_m"
    }

    func toModel() -> RiderNearbyCounts {
        RiderNearbyCounts(
            total: total ?? 0,
            behindSameDirection: behindSameDirection,
            oncoming: oncoming,
            unknownDirection: unknownDirection ?? 0,
            bearing: bearing,
            radiusM: radiusM ?? 2000,
            disclaimer: disclaimer ?? TripService.fallbackDisclaimer
        )
    }
}
