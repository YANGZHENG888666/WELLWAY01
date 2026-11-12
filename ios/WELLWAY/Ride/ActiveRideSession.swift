import Foundation
import CoreLocation
import Supabase
import os

/// 骑行中的单个轨迹样本。快照与待补传队列共用同一种结构，
/// 进程被系统回收后仍能还原里程、轨迹和上传所需的时间戳。
struct RideTrackSample: Codable, Hashable {
    let lat: Double
    let lng: Double
    let recordedAt: Date
    let speedKmh: Double
    let bearing: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// 一次仍在进行中的骑行快照。
///
/// `RideService` 只活在 `RidingView` 的内存里，App 被系统终止后无法自行续跑。
/// 没有快照时只能把数据库里的 `riding` 记录收尾成「未完成」；有快照时，
/// 冷启动可以告诉用户上次骑到了哪里，并给出「继续记录 / 结束并保存」。
struct ActiveRideSession: Codable, Identifiable {
    static let currentVersion = 1

    var version: Int = ActiveRideSession.currentVersion
    let userId: UUID
    let rideId: UUID?
    let route: Route
    let checkpoints: [Checkpoint]
    let vehicleId: UUID?
    let vehicleName: String?
    let startedAt: Date
    var updatedAt: Date
    /// "riding" / "paused"
    var phase: String
    /// 已累计时长（含快照时刻仍在进行的段落），暂停时间不计入
    var durationS: Int
    var distanceM: Double
    /// 最近一段轨迹，只保留尾部，用于面板和地图的即时回显
    var track: [RideTrackSample]
    /// 尚未确认上传成功的轨迹点，恢复后补传
    var pendingPoints: [RideTrackSample]
    var checkedCheckpointIds: [Int]

    var id: String {
        if let rideId { return rideId.uuidString }
        return "pending-\(route.id)-\(Int(startedAt.timeIntervalSince1970))"
    }

    var isPaused: Bool { phase == "paused" }

    var lastSample: RideTrackSample? { track.last }

    /// 骑了多久、走到哪里，都用快照里的同一份数据，避免面板和记录页对不上。
    var distanceText: String {
        distanceM >= 1000
            ? String(format: "%.1f km", distanceM / 1000)
            : "\(Int(distanceM.rounded())) m"
    }

    var durationText: String {
        let seconds = max(durationS, 0)
        if seconds < 60 { return "\(seconds) 秒" }
        let minutes = seconds / 60
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分" }
        return "\(minutes) 分钟"
    }

    /// 上次快照距今多久。用于解释「这不是现在正在骑」。
    var staleText: String? {
        let seconds = Date().timeIntervalSince(updatedAt)
        guard seconds > 90 else { return nil }
        let minutes = Int(seconds / 60)
        if minutes >= 60 { return "最后记录于 \(minutes / 60) 小时前" }
        return "最后记录于 \(minutes) 分钟前"
    }
}

/// 快照落盘。写入放在串行队列，避免定位回调里同步写文件卡住主线程；
/// 读取用 sync 保证冷启动一定能看到上一次已完成的写入。
enum ActiveRideSessionStore {
    private static let queue = DispatchQueue(label: "com.wellway.active-ride-session")
    private static let logger = Logger(subsystem: "com.wellway.app", category: "ActiveRideSession")
    /// 不能再用 `WELLWAY`：它与车库缓存的 `Wellway` 在大小写不敏感的 APFS 上
    /// 是同一个目录，创建目录会返回 EIO，导致快照永远写不进去。
    private static let directoryName = "RideSessions"
    private static let fileName = "active-ride.json"

    private static var directoryURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static var fileURL: URL {
        directoryURL.appendingPathComponent(fileName)
    }

    static func load() -> ActiveRideSession? {
        queue.sync {
            let data: Data
            do {
                data = try Data(contentsOf: fileURL)
            } catch {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    logger.error("Failed to read active ride snapshot: \(String(describing: error), privacy: .public)")
                }
                return nil
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let session = try decoder.decode(ActiveRideSession.self, from: data)
                guard session.version <= ActiveRideSession.currentVersion else {
                    logger.error("Active ride snapshot version \(session.version) is newer than supported")
                    return nil
                }
                return session
            } catch {
                logger.error("Failed to decode active ride snapshot: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }

    static func save(_ session: ActiveRideSession) {
        queue.async {
            do {
                let data = try encode(session)
                try ensureDirectory()
                try data.write(to: fileURL, options: [.atomic])
                try? FileManager.default.setAttributes(
                    [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                    ofItemAtPath: fileURL.path
                )
            } catch {
                // 快照失败意味着进程被回收后无法恢复骑行，必须留下可排查的日志，
                // 不能再像之前那样用 `try?` 把错误静默吞掉。
                logger.error("Failed to save active ride snapshot: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func ensureDirectory() throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return
        }
        do {
            try fm.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        } catch {
            // 模拟器对文件保护属性支持不稳定，目录可能已创建但调用仍抛错。
            if fm.fileExists(atPath: directoryURL.path) { return }
            try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
    }

    static func clear() {
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// 需要确认已经删干净时使用（例如立即展示新的骑行面板前）
    static func clearNow() {
        queue.sync {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private static func encode(_ session: ActiveRideSession) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(session)
    }
}

/// 「结束并保存」的结果，供恢复页决定提示文案。
struct RideRecoveryOutcome {
    let rideId: UUID
    let distanceM: Int
    let durationS: Int
    let savedTrack: Bool
    let warning: String?
    /// 云端记录此前已经是 completed，本次只是补传轨迹/打卡。
    let alreadySaved: Bool
}

/// 不进入骑行 HUD，直接把快照收尾成一条完成记录。
enum RecoveredRideFinalizer {
    static func finish(
        session: ActiveRideSession,
        client: SupabaseClient
    ) async throws -> RideRecoveryOutcome {
        let ensured = try await ensureRecord(session: session, client: client)
        let rideId = ensured.rideId

        var savedTrack = true
        if !session.pendingPoints.isEmpty {
            savedTrack = await uploadPendingPoints(session, rideId: rideId, client: client)
        }

        if !session.checkedCheckpointIds.isEmpty {
            let rows = session.checkedCheckpointIds.map {
                RideCheckinInsert(rideId: rideId, checkpointId: $0, userId: session.userId)
            }
            try? await client
                .from("ride_checkins")
                .upsert(rows, onConflict: "ride_id,checkpoint_id")
                .execute()
        }

        let endedAt = ISO8601DateFormatter().string(from: session.updatedAt)
        let fallbackDistance = Int(session.distanceM.rounded())
        // 已完成的记录不再覆盖结束时间与统计；只补轨迹、打卡和缺失的零值，
        // 这样“部分轨迹失败后重试”不会因为 alreadyCompleted 永久卡住。
        if !ensured.alreadyCompleted {
            try await client
                .from("ride_records")
                .update(["ended_at": endedAt, "status": "completed"])
                .eq("id", value: rideId)
                .execute()
            // Supabase 的 update 字典要求同类型；字符串和数字分开写。
            try await client
                .from("ride_records")
                .update(["distance_m": fallbackDistance, "duration_s": session.durationS])
                .eq("id", value: rideId)
                .execute()
        }

        try? await client
            .rpc("recalculate_ride_stats", params: ["p_ride_id": rideId.uuidString])
            .execute()

        // 没有轨迹点时 recalc 会把里程/时长写成 0；用快照值兜底，别把骑过的路抹掉。
        try? await client.from("ride_records")
            .update(["duration_s": session.durationS])
            .eq("id", value: rideId)
            .eq("duration_s", value: 0)
            .execute()
        try? await client.from("ride_records")
            .update(["distance_m": fallbackDistance])
            .eq("id", value: rideId)
            .eq("distance_m", value: 0)
            .execute()

        let allDone = !session.checkpoints.isEmpty
            && session.checkpoints.allSatisfy { session.checkedCheckpointIds.contains($0.id) }
        _ = try? await RideService.awardBadgeIfNeeded(
            client: client,
            userId: session.userId,
            routeId: session.route.id,
            rideId: rideId,
            allCheckpointsDone: allDone
        )

        return RideRecoveryOutcome(
            rideId: rideId,
            distanceM: fallbackDistance,
            durationS: session.durationS,
            savedTrack: savedTrack,
            warning: savedTrack ? nil : "部分轨迹未上传，里程可能不完整",
            alreadySaved: ensured.alreadyCompleted
        )
    }

    private static func ensureRecord(
        session: ActiveRideSession,
        client: SupabaseClient
    ) async throws -> (rideId: UUID, alreadyCompleted: Bool) {
        if let rideId = session.rideId {
            let rows: [RideStatusRow] = (try? await client
                .from("ride_records")
                .select("id, status")
                .eq("id", value: rideId)
                .limit(1)
                .execute()
                .value) ?? []
            if let row = rows.first {
                return (row.id, row.status == "completed")
            }
        }

        let insert = RideRecordInsert(
            userId: session.userId,
            routeId: session.route.id,
            vehicleId: session.vehicleId,
            startedAt: ISO8601DateFormatter().string(from: session.startedAt),
            endedAt: ISO8601DateFormatter().string(from: session.updatedAt),
            status: "riding"
        )
        let record: RideStatusRow = try await client
            .from("ride_records")
            .insert(insert)
            .select("id, status")
            .single()
            .execute()
            .value
        return (record.id, false)
    }

    private static func uploadPendingPoints(
        _ session: ActiveRideSession,
        rideId: UUID,
        client: SupabaseClient
    ) async -> Bool {
        let formatter = ISO8601DateFormatter()
        let samples = session.pendingPoints
        let times = samples.map(\.recordedAt)
        guard let lower = times.min(), let upper = times.max() else { return true }

        // 快照写入与真正上传之间存在竞态：同一批点可能已经进库。
        // 拉取该时间窗内已有的 recorded_at，按秒级容差去重，避免轨迹重复。
        let existing: [RidePointTimeRow] = (try? await client
            .from("ride_points")
            .select("recorded_at")
            .eq("ride_id", value: rideId)
            .gte("recorded_at", value: formatter.string(from: lower.addingTimeInterval(-1)))
            .lte("recorded_at", value: formatter.string(from: upper.addingTimeInterval(1)))
            .execute()
            .value) ?? []
        let existingDates = existing.compactMap {
            ISO8601DateFormatter.wellwayDate(from: $0.recordedAt)
        }

        let filtered = samples.filter { sample in
            !existingDates.contains { abs($0.timeIntervalSince(sample.recordedAt)) < 0.5 }
        }
        guard !filtered.isEmpty else { return true }

        let inserts = filtered.map {
            RidePointInsert(
                rideId: rideId,
                lat: $0.lat,
                lng: $0.lng,
                speedKmh: $0.speedKmh,
                recordedAt: formatter.string(from: $0.recordedAt),
                bearing: $0.bearing
            )
        }
        do {
            for chunk in inserts.chunked(into: 100) {
                try await client.from("ride_points").insert(chunk).execute()
            }
            return true
        } catch {
            return false
        }
    }
}

private struct RideStatusRow: Decodable {
    let id: UUID
    let status: String
}

struct RidePointTimeRow: Decodable {
    let recordedAt: String

    enum CodingKeys: String, CodingKey {
        case recordedAt = "recorded_at"
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
