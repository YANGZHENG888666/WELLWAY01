import Foundation

// MARK: - 车型库

struct Brand: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let nameEn: String?
    let isHot: Bool
    let sort: Int

    enum CodingKeys: String, CodingKey {
        case id, name, sort
        case nameEn = "name_en"
        case isHot = "is_hot"
    }
}

struct VehicleModel: Codable, Identifiable, Hashable {
    let id: Int
    let brandId: Int
    let name: String
    let series: String?
    let modelType: String
    let displacementCc: Int?
    let priceMin: Int?
    let priceMax: Int?
    let rating: Double?
    let isNew: Bool
    let sort: Int
    /// 云端车型真图(Storage `catalog-images` / 后台可上传)。为空时 App 回落到分类插画
    let imageUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, series, rating, sort
        case brandId = "brand_id"
        case modelType = "model_type"
        case displacementCc = "displacement_cc"
        case priceMin = "price_min"
        case priceMax = "price_max"
        case isNew = "is_new"
        case imageUrl = "image_url"
    }
}

extension VehicleModel {
    /// 车型名统一出口：后台个别车型名带结尾冒号（「Dax e:」），直接展示像没录完。
    var cleanedName: String {
        var value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = value.last, last == ":" || last == "：" {
            value.removeLast()
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? name : value
    }

    /// 车型名当品牌标题已经出现时，去掉重复的品牌前缀。
    func displayName(removingBrand brand: Brand?) -> String {
        rawDisplayName(removingBrand: brand)
    }

    private func rawDisplayName(removingBrand brand: Brand?) -> String {
        let full = cleanedName
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "-_·"))

        var prefixCandidates: [String] = []
        for raw in [brand?.name, brand?.nameEn].compactMap({ $0 }) {
            let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            prefixCandidates.append(clean)
            prefixCandidates.append(contentsOf: clean.components(separatedBy: separators))
            // 品牌名常写成「凯威MBP」这种中英连写，车型却以 MBP 开头；
            // 把其中的英文片段也作为可去除前缀。
            if let regex = try? NSRegularExpression(pattern: "[A-Za-z][A-Za-z0-9]*") {
                let range = NSRange(clean.startIndex..<clean.endIndex, in: clean)
                for match in regex.matches(in: clean, range: range) {
                    if let tokenRange = Range(match.range, in: clean) {
                        prefixCandidates.append(String(clean[tokenRange]))
                    }
                }
            }
        }

        var seen = Set<String>()
        let exactPrefixes = prefixCandidates
            .map { $0.trimmingCharacters(in: separators) }
            .filter { $0.count >= 2 && seen.insert($0.lowercased()).inserted }
            .sorted { $0.count > $1.count }
        // 少数后台数据把品牌写了两遍（「雷虎 雷虎 150」），单次剥离后仍会重复显示，
        // 因此循环剥离，直到名字不再以品牌开头。
        var current = full
        for _ in 0..<3 {
            var didStrip = false
            for prefix in exactPrefixes {
                guard let range = current.range(of: prefix, options: [.anchored, .caseInsensitive]) else { continue }
                let rest = String(current[range.upperBound...]).trimmingCharacters(in: separators)
                if !rest.isEmpty {
                    current = rest
                    didStrip = true
                    break
                }
            }
            if !didStrip { break }
        }
        if current != full { return current }

        if let localName = brand?.name.trimmingCharacters(in: .whitespacesAndNewlines),
           !localName.isEmpty {
            let lhs = Array(full)
            let rhs = Array(localName)
            var common = 0
            while common < min(lhs.count, rhs.count), lhs[common] == rhs[common] {
                common += 1
            }
            if common >= 2, common < lhs.count {
                let rest = String(lhs[common...]).trimmingCharacters(in: separators)
                if !rest.isEmpty { return rest }
            }
        }
        return full
    }
}

// MARK: - 用户数据

struct Profile: Codable, Identifiable {
    let id: UUID
    let nickname: String
    let avatarUrl: String?
    var emailBound: Bool

    enum CodingKeys: String, CodingKey {
        case id, nickname
        case avatarUrl = "avatar_url"
        case emailBound = "email_bound"
    }
}

struct Vehicle: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let brandId: Int
    let modelId: Int
    let nickname: String?
    let color: String?
    let photoUrl: String?
    let isDefault: Bool

    enum CodingKeys: String, CodingKey {
        case id, nickname, color
        case userId = "user_id"
        case brandId = "brand_id"
        case modelId = "model_id"
        case photoUrl = "photo_url"
        case isDefault = "is_default"
    }
}

/// 车辆展示名：全站统一「品牌(英文优先) + 车型」。
/// 车型库名称本身通常带品牌前缀(如「本田 CB400F」)，拼接前先去掉，避免出现
/// 「HONDA 本田 CB400F」；只有拿不到品牌/车型时才回退到昵称。
enum VehicleDisplayName {
    static func make(brandName: String?,
                     brandNameEn: String?,
                     rawModelName: String?,
                     nickname: String?) -> String {
        func clean(_ value: String?) -> String {
            (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let brandZh = clean(brandName)
        let brandEn = clean(brandNameEn)
        let brand = brandZh.isEmpty ? brandEn : brandZh
        let rawModel = clean(rawModelName)

        var model = rawModel
        if let head = rawModel.split(separator: " ").first.map(String.init), !head.isEmpty {
            let known = [brandZh, brandEn, "春风动力", "春风"].filter { !$0.isEmpty }
            if known.contains(where: { $0 == head || head.hasPrefix($0) || $0.hasPrefix(head) }) {
                model = rawModel.split(separator: " ").dropFirst().joined(separator: " ")
            }
        }

        let composed = [brand, model].filter { !$0.isEmpty }.joined(separator: " ")
        if !composed.isEmpty { return composed }
        let nick = clean(nickname)
        return nick.isEmpty ? "我的爱车" : nick
    }
}

struct VehicleInsert: Encodable {
    let userId: UUID
    let brandId: Int
    let modelId: Int
    let nickname: String?
    let color: String?
    let photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case nickname, color
        case userId = "user_id"
        case brandId = "brand_id"
        case modelId = "model_id"
        case photoUrl = "photo_url"
    }
}

// MARK: - 路线

struct Route: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let startName: String?
    let endName: String?
    let distanceM: Int
    let elevationM: Int
    let difficulty: String
    let durationMin: Int?
    let mapUrl: String?
    /// 列表卡片封面(后台 route-images 上传),为空时用 mapUrl 或内置线稿兜底
    let coverImageUrl: String?
    /// 所在省市(后台维护),用于卡片副标题与地区筛选
    let province: String?
    let city: String?

    enum CodingKeys: String, CodingKey {
        case id, name, difficulty, province, city
        case startName = "start_name"
        case endName = "end_name"
        case distanceM = "distance_m"
        case elevationM = "elevation_m"
        case durationMin = "duration_min"
        case mapUrl = "map_url"
        case coverImageUrl = "cover_image_url"
    }
}

extension Route {
    /// 后台可上传封面图，旧数据可能只有 map_url；同时兼容绝对 URL 与 Storage 对象路径。
    var displayImageURL: URL? {
        for raw in [coverImageUrl, mapUrl] {
            guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            if let url = URL(string: raw),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return url
            }
            // 兼容后台只存 Storage 对象路径的情况，例如 "<uid>/cover.jpg"
            let key = raw.hasPrefix("route-images/") ? raw : "route-images/\(raw)"
            let cleaned = key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let base = AppConfig.supabaseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if let url = URL(string: "\(base)/storage/v1/object/public/\(cleaned)") {
                return url
            }
        }
        return nil
    }
}

struct Checkpoint: Codable, Identifiable, Hashable {
    let id: Int
    let routeId: Int
    let name: String
    let seq: Int
    let lat: Double?
    let lng: Double?
    let radiusM: Int

    enum CodingKeys: String, CodingKey {
        case id, name, seq, lat, lng
        case routeId = "route_id"
        case radiusM = "radius_m"
    }
}

/// 后台安全聚合：今天(北京时间)每条路线的真实骑行人数(去重用户)
struct RouteRiderCount: Codable, Hashable {
    let routeId: Int
    let riderCount: Int

    enum CodingKeys: String, CodingKey {
        case routeId = "route_id"
        case riderCount = "rider_count"
    }
}

/// 骑行中位置上报(同路骑士实时列表)
struct RidePresence: Codable, Identifiable, Hashable {
    let userId: UUID
    let routeId: Int
    let lat: Double
    let lng: Double
    let vehicleName: String?
    let nickname: String?
    let updatedAt: String

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case lat, lng, nickname
        case userId = "user_id"
        case routeId = "route_id"
        case vehicleName = "vehicle_name"
        case updatedAt = "updated_at"
    }
}

struct RidePresenceInsert: Encodable {
    let userId: UUID
    let routeId: Int
    let lat: Double
    let lng: Double
    let vehicleName: String?
    let nickname: String?
    /// 航向角(迁移 0019 新增):用于「后方同向 / 对向驶来」分类；为空则不发送该键
    var bearing: Double? = nil
    /// 当前行程 id(迁移 0019 新增);为空则不发送该键
    var tripId: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case lat, lng, nickname, bearing
        case userId = "user_id"
        case routeId = "route_id"
        case vehicleName = "vehicle_name"
        case tripId = "trip_id"
    }

    /// 可选键用 encodeIfPresent:迁移没执行(列不存在)时也能正常写入
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userId, forKey: .userId)
        try c.encode(routeId, forKey: .routeId)
        try c.encode(lat, forKey: .lat)
        try c.encode(lng, forKey: .lng)
        try c.encodeIfPresent(vehicleName, forKey: .vehicleName)
        try c.encodeIfPresent(nickname, forKey: .nickname)
        try c.encodeIfPresent(bearing, forKey: .bearing)
        try c.encodeIfPresent(tripId, forKey: .tripId)
    }
}

/// 意见反馈(App 内提交)
struct FeedbackInsert: Encodable {
    let content: String
    let contact: String?
    let appVersion: String?

    enum CodingKeys: String, CodingKey {
        case content, contact
        case appVersion = "app_version"
    }
}

// MARK: - 徽章

struct Badge: Codable, Identifiable, Hashable {
    let id: Int
    let routeId: Int?
    let name: String
    let imageUrl: String?
    let conditionDesc: String?
    let seq: Int

    enum CodingKeys: String, CodingKey {
        case id, name, seq
        case routeId = "route_id"
        case imageUrl = "image_url"
        case conditionDesc = "condition_desc"
    }
}

// MARK: - 骑行记录 / 轨迹

struct RideRecord: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let routeId: Int?
    let vehicleId: UUID?
    let name: String?
    let startedAt: String
    let endedAt: String?
    let distanceM: Int
    let durationS: Int
    let avgSpeedKmh: Double?
    let maxSpeedKmh: Double?
    let elevationGainM: Int
    let status: String

    enum CodingKeys: String, CodingKey {
        case id, name, status
        case userId = "user_id"
        case routeId = "route_id"
        case vehicleId = "vehicle_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case distanceM = "distance_m"
        case durationS = "duration_s"
        case avgSpeedKmh = "avg_speed_kmh"
        case maxSpeedKmh = "max_speed_kmh"
        case elevationGainM = "elevation_gain_m"
    }
}

extension RideRecord {
    /// 少于 50 米通常意味着没有拿到有效 GPS 点，而不是骑了 0 公里。
    /// 展示层应明确写「轨迹未记录」，避免把定位失败伪装成正常骑行数据。
    var hasRecordedTrack: Bool { distanceM >= 50 }

    /// App 被系统终止或网络中断时，记录可能永久停留在 riding。
    /// 超过 24 小时仍未结束的记录不再显示成「进行中」，避免误导用户。
    var isStaleRiding: Bool {
        guard status == "riding",
              let started = ISO8601DateFormatter.wellwayDate(from: startedAt) else { return false }
        return Date().timeIntervalSince(started) > 24 * 60 * 60
    }

    var isCompleted: Bool { status == "completed" }

    /// 列表与详情共用同一个状态文案，避免两处对同一条记录给出不同结论。
    var displayStatus: String {
        if isCompleted { return "已完成" }
        if status == "riding", !isStaleRiding { return "进行中" }
        return "未完成"
    }
}

struct RideRecordInsert: Encodable {
    let userId: UUID
    let routeId: Int?
    let vehicleId: UUID?
    let startedAt: String
    let endedAt: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case status
        case userId = "user_id"
        case routeId = "route_id"
        case vehicleId = "vehicle_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct RidePointInsert: Encodable {
    let rideId: UUID
    let lat: Double
    let lng: Double
    let speedKmh: Double
    let recordedAt: String
    /// 航向角(迁移 0019 新增列):为空则不发送该键，避免列不存在时整批插入失败
    var bearing: Double? = nil

    enum CodingKeys: String, CodingKey {
        case lat, lng, bearing
        case rideId = "ride_id"
        case speedKmh = "speed_kmh"
        case recordedAt = "recorded_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rideId, forKey: .rideId)
        try c.encode(lat, forKey: .lat)
        try c.encode(lng, forKey: .lng)
        try c.encode(speedKmh, forKey: .speedKmh)
        try c.encode(recordedAt, forKey: .recordedAt)
        try c.encodeIfPresent(bearing, forKey: .bearing)
    }
}

/// 已保存的骑行轨迹点（只读回放）
struct RidePoint: Decodable, Hashable {
    let lat: Double
    let lng: Double
    let speedKmh: Double?
    let recordedAt: String

    enum CodingKeys: String, CodingKey {
        case lat, lng
        case speedKmh = "speed_kmh"
        case recordedAt = "recorded_at"
    }
}

struct RideCheckinInsert: Encodable {
    let rideId: UUID
    let checkpointId: Int
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case rideId = "ride_id"
        case checkpointId = "checkpoint_id"
        case userId = "user_id"
    }
}

struct RideCheckin: Codable, Identifiable, Hashable {
    let id: Int
    let rideId: UUID
    let checkpointId: Int
    let checkedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case rideId = "ride_id"
        case checkpointId = "checkpoint_id"
        case checkedAt = "checked_at"
    }
}

// MARK: - 徽章

struct UserBadge: Codable, Identifiable, Hashable {
    let id: Int
    let badgeId: Int
    let rideId: UUID?
    let earnedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case badgeId = "badge_id"
        case rideId = "ride_id"
        case earnedAt = "earned_at"
    }
}
