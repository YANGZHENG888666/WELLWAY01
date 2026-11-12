import CoreLocation
import Foundation
import Observation
import Supabase

/// 骑行阶段
enum RidePhase {
    case idle
    case riding
    case paused
}

private struct RideRecordStatusRow: Decodable {
    let id: UUID
    let status: String
}

/// 一次骑行结束后的总结
struct RideSummary {
    let record: RideRecord?
    let checkedCheckpointIds: Set<Int>
    let awardedBadge: Badge?
    let allCheckpointsDone: Bool
    /// 本次真实 GPS 轨迹；少于 2 个点时总结页回退到路线打卡点形状
    var track: [CLLocationCoordinate2D] = []
    /// 记录状态写库最终失败时的提示，nil 表示已正常保存
    var saveWarning: String? = nil
    /// 记录已建起来、只是收尾没写完时才谈得上「重试同步」；
    /// 记录本身没创建成功时，重试没有可补写的对象，不能给用户假希望
    var canRetrySave: Bool = false
}

/// 骑行引擎：后台定位 → 轨迹点 → 打卡判定 → 结束保存 → 徽章发放
@MainActor
@Observable
final class RideService: NSObject, CLLocationManagerDelegate {
    private let client: SupabaseClient
    private let route: Route
    private let checkpoints: [Checkpoint]
    private let userId: UUID
    private let vehicleId: UUID?
    private let vehicleName: String?
    /// 冷启动恢复时传入；nil 表示一次全新骑行
    private let resumeSession: ActiveRideSession?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let isoFormatter: ISO8601DateFormatter

    private(set) var phase: RidePhase = .idle
    private(set) var speedKmh: Double = 0
    private(set) var distanceM: Double = 0
    private(set) var durationS: Int = 0
    private(set) var lastLat: Double?
    private(set) var lastLng: Double?
    private(set) var track: [CLLocationCoordinate2D] = []
    private(set) var checkedCheckpointIds: Set<Int> = []
    private(set) var isSaving = false
    /// 沿途匿名骑手统计(后方同向 / 对向驶来),仅数字
    private(set) var nearbyRiders: RiderNearbyCounts?
    var errorMessage: String?

    /// 云端表是否已加 bearing / trip_id 等新列(迁移未执行时自动降级)
    @ObservationIgnored private var supportsExtras: Bool?
    private var rideId: UUID?
    private var startedAt = Date()
    private var lastLocation: CLLocation?
    private var lastBearing: Double?
    private var pendingPoints: [RidePointInsert] = []
    private var pendingCheckins: [RideCheckinInsert] = []
    /// 轨迹样本与 track 同步增长，快照需要原始时间戳，不能只留坐标
    private var trackSamples: [RideTrackSample] = []
    private var lastSnapshotAt = Date.distantPast
    private var ticker: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?
    /// 已结算的骑行秒数。进入后台时 ticker 可能被挂起，不能靠每秒 +1 计时；
    /// 当前段用 segmentStartedAt 按墙钟时间结算，回前台后一次补齐。
    private var settledDurationS: TimeInterval = 0
    private var segmentStartedAt: Date?
    /// 上一轮同路线匿名骑手数，用于检测是否有人新加入
    private var lastCompanionCount = 0
    private var companionsPrimed = false

    init(
        client: SupabaseClient,
        route: Route,
        checkpoints: [Checkpoint],
        userId: UUID,
        vehicleId: UUID?,
        vehicleName: String? = nil,
        resumeSession: ActiveRideSession? = nil
    ) {
        self.client = client
        self.route = route
        self.checkpoints = checkpoints
        self.userId = userId
        self.vehicleId = vehicleId
        self.vehicleName = vehicleName
        self.resumeSession = resumeSession
        self.isoFormatter = ISO8601DateFormatter()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
    }

    // MARK: - 开始 / 暂停 / 结束

    func start() async {
        if let resumeSession {
            await restore(from: resumeSession)
            return
        }
        Task { await NotificationHelper.requestAuthorizationIfNeeded() }
        phase = .riding
        trackSamples.removeAll()
        startedAt = Date()
        distanceM = 0
        durationS = 0
        settledDurationS = 0
        segmentStartedAt = Date()
        speedKmh = 0
        track.removeAll()
        pendingPoints.removeAll()
        pendingCheckins.removeAll()
        checkedCheckpointIds.removeAll()

        // 先建骑行记录(状态 riding),后续轨迹都挂到它下面
        let insert = RideRecordInsert(
            userId: userId,
            routeId: route.id,
            vehicleId: vehicleId,
            startedAt: isoFormatter.string(from: startedAt),
            endedAt: isoFormatter.string(from: startedAt),
            status: "riding"
        )
        do {
            let record: RideRecord = try await client
                .from("ride_records")
                .insert(insert)
                .select("id, user_id, route_id, vehicle_id, started_at, ended_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh, elevation_gain_m, status")
                .single()
                .execute()
                .value
            rideId = record.id
        } catch {
            rideId = nil
            errorMessage = error.wellwayUserMessage
        }

        manager.startUpdatingLocation()
        startTicker()
        await probeSchemaSupport()
        persistSnapshot(force: true)
        if let tripId = TripSession.shared.tripId {
            _ = await TripService.updateStatus(client, tripId: tripId, status: "riding")
        }
        startPresenceReporting()
    }

    /// 冷启动恢复：复用原 rideId 和开始时间，不重复建记录。
    ///
    /// 进程被杀期间可能已经过去一段时间，但没有任何定位数据。这里不把
    /// 关机时间算进骑行时长，而是以最后一次快照的累计时长为准，从恢复这一刻
    /// 重新开启计时段，避免给用户凭空多出几小时。
    private func restore(from session: ActiveRideSession) async {
        Task { await NotificationHelper.requestAuthorizationIfNeeded() }

        startedAt = session.startedAt
        distanceM = session.distanceM
        settledDurationS = TimeInterval(session.durationS)
        durationS = session.durationS
        speedKmh = 0
        track = session.track.map(\.coordinate)
        trackSamples = session.track
        checkedCheckpointIds = Set(session.checkedCheckpointIds)
        pendingPoints.removeAll()
        pendingCheckins.removeAll()
        if let last = session.track.last {
            lastLat = last.lat
            lastLng = last.lng
        }

        rideId = session.rideId
        await verifyRestoredRecord()
        if rideId == nil {
            await createRestoredRecord()
        }

        await probeSchemaSupport()
        await restorePendingPoints(session.pendingPoints)
        await loadRecentTrack()

        phase = session.isPaused ? .paused : .riding
        if phase == .riding {
            segmentStartedAt = Date()
            manager.startUpdatingLocation()
            startTicker()
            startPresenceReporting()
        } else {
            segmentStartedAt = nil
        }
        persistSnapshot(force: true)
    }

    /// 快照里的记录可能已被别的路径收尾（例如上次结束保存成功的最后一秒被杀）。
    /// 只有仍然处于 riding 的记录才值得继续，否则重新建一条，不覆盖已保存的数据。
    private func verifyRestoredRecord() async {
        guard let rideId else { return }
        let rows: [RideRecordStatusRow] = (try? await client
            .from("ride_records")
            .select("id, status")
            .eq("id", value: rideId)
            .limit(1)
            .execute()
            .value) ?? []
        guard let row = rows.first, row.status == "riding" else {
            self.rideId = nil
            return
        }
    }

    private func createRestoredRecord() async {
        let insert = RideRecordInsert(
            userId: userId,
            routeId: route.id,
            vehicleId: vehicleId,
            startedAt: isoFormatter.string(from: startedAt),
            endedAt: isoFormatter.string(from: Date()),
            status: "riding"
        )
        do {
            let record: RideRecord = try await client
                .from("ride_records")
                .insert(insert)
                .select("id, user_id, route_id, vehicle_id, started_at, ended_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh, elevation_gain_m, status")
                .single()
                .execute()
                .value
            rideId = record.id
        } catch {
            rideId = nil
            errorMessage = error.wellwayUserMessage
        }
    }

    /// 进程被杀瞬间还没上传成功的轨迹点，恢复后补传；先按时间窗去重，
    /// 避免「快照已写、上传也已成功」的那一批重复入库。
    private func restorePendingPoints(_ samples: [RideTrackSample]) async {
        guard let rideId, !samples.isEmpty else { return }
        let times = samples.map(\.recordedAt)
        guard let lower = times.min(), let upper = times.max() else { return }
        let existing: [RidePointTimeRow] = (try? await client
            .from("ride_points")
            .select("recorded_at")
            .eq("ride_id", value: rideId)
            .gte("recorded_at", value: isoFormatter.string(from: lower.addingTimeInterval(-1)))
            .lte("recorded_at", value: isoFormatter.string(from: upper.addingTimeInterval(1)))
            .execute()
            .value) ?? []
        let existingDates = existing.compactMap { ISO8601DateFormatter.wellwayDate(from: $0.recordedAt) }
        let filtered = samples.filter { sample in
            !existingDates.contains { abs($0.timeIntervalSince(sample.recordedAt)) < 0.5 }
        }
        pendingPoints = filtered.map {
            RidePointInsert(
                rideId: rideId,
                lat: $0.lat,
                lng: $0.lng,
                speedKmh: $0.speedKmh,
                recordedAt: isoFormatter.string(from: $0.recordedAt),
                bearing: supportsExtras == true ? $0.bearing : nil
            )
        }
        if !pendingPoints.isEmpty {
            await flushPoints()
        }
    }

    /// 用服务端最近 1000 个点补全地图轨迹。PostgREST 默认只返回 1000 行，
    /// 因此按时间倒序取尾部再反转，足够覆盖绝大多数单次骑行。
    private func loadRecentTrack() async {
        guard let rideId else { return }
        let points: [RidePoint] = (try? await client
            .from("ride_points")
            .select("lat, lng, speed_kmh, recorded_at")
            .eq("ride_id", value: rideId)
            .order("recorded_at", ascending: false)
            .limit(1000)
            .execute()
            .value) ?? []
        guard !points.isEmpty else { return }
        let sorted = points.reversed().compactMap { point -> RideTrackSample? in
            guard let date = ISO8601DateFormatter.wellwayDate(from: point.recordedAt) else { return nil }
            return RideTrackSample(
                lat: point.lat,
                lng: point.lng,
                recordedAt: date,
                speedKmh: point.speedKmh ?? 0,
                bearing: nil
            )
        }
        guard let serverLast = sorted.last else { return }
        if let snapshotLast = trackSamples.last, snapshotLast.recordedAt > serverLast.recordedAt {
            return
        }
        trackSamples = sorted
        track = sorted.map(\.coordinate)
        if let last = sorted.last {
            lastLat = last.lat
            lastLng = last.lng
        }
    }

    // MARK: - 会话快照

    /// 当前状态压成快照。`durationS` 按墙钟时间结算，暂停时冻结。
    private func makeSnapshot() -> ActiveRideSession {
        let now = Date()
        let openSegment = phase == .riding
            ? max(0, now.timeIntervalSince(segmentStartedAt ?? now))
            : 0
        let liveDuration = settledDurationS + openSegment
        let pending = pendingPoints.compactMap { insert -> RideTrackSample? in
            guard let date = isoFormatter.date(from: insert.recordedAt) else { return nil }
            return RideTrackSample(
                lat: insert.lat,
                lng: insert.lng,
                recordedAt: date,
                speedKmh: insert.speedKmh,
                bearing: insert.bearing
            )
        }
        return ActiveRideSession(
            userId: userId,
            rideId: rideId,
            route: route,
            checkpoints: checkpoints,
            vehicleId: vehicleId,
            vehicleName: vehicleName,
            startedAt: startedAt,
            updatedAt: now,
            phase: phase == .paused ? "paused" : "riding",
            durationS: Int(liveDuration.rounded(.down)),
            distanceM: distanceM,
            track: Array(trackSamples.suffix(2000)),
            pendingPoints: Array(pending.suffix(5000)),
            checkedCheckpointIds: Array(checkedCheckpointIds)
        )
    }

    /// 定位回调频率约 1Hz，快照最多每 8 秒写一次；暂停/恢复/开始时强制写。
    private func persistSnapshot(force: Bool = false) {
        guard phase != .idle else { return }
        let now = Date()
        if !force, now.timeIntervalSince(lastSnapshotAt) < 8 { return }
        lastSnapshotAt = now
        ActiveRideSessionStore.save(makeSnapshot())
    }

    /// 进入后台前调用，尽量减少被杀时丢失的轨迹。
    func persistNow() {
        guard phase != .idle else { return }
        lastSnapshotAt = Date()
        ActiveRideSessionStore.save(makeSnapshot())
    }

    func pause() {
        guard phase == .riding else { return }
        settleDuration()
        segmentStartedAt = nil
        phase = .paused
        persistSnapshot(force: true)
        manager.stopUpdatingLocation()
        // 暂停后不再收定位，speedKmh 会停在暂停前那一秒：暂停页上继续顶着
        // 「48 km/h」的大数字，读起来像还在骑行。速度归零，时长由 ticker 的
        // phase 判断自动冻结，两处口径一致。
        speedKmh = 0
        lastLocation = nil
    }

    func resume() {
        guard phase == .paused else { return }
        phase = .riding
        segmentStartedAt = Date()
        manager.startUpdatingLocation()
        persistSnapshot(force: true)
    }

    /// 结束骑行：保存轨迹/打卡 → 重算统计 → 发放徽章 → 返回总结
    func end() async -> RideSummary {
        settleDuration()
        segmentStartedAt = nil
        // 先把最终里程/时长写进快照，再离开 riding 状态。
        // 云端收尾失败时保留快照，下次冷启动还能补存这次骑行；
        // 只有确认同步成功后才清除，避免静默丢记录。
        persistSnapshot(force: true)
        phase = .idle
        ticker?.cancel()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isSaving = true
        defer { isSaving = false }
        presenceTask?.cancel()
        presenceTask = nil
        lastCompanionCount = 0
        companionsPrimed = false
        nearbyRiders = nil

        let endedAt = isoFormatter.string(from: Date())

        // 结束保存包含消除在线状态、行程状态、轨迹补传、统计重算、徽章等多次串行请求。
        // 网络不可达时必须在限定时间内返回本地总结，否则用户会觉得“结束骑行没反应”。
        if let wrapped = await AsyncDeadline.run(seconds: 4.5, { @MainActor in
            await self.performCompletion(endedAt: endedAt)
        }), let summary = wrapped {
            if summary.saveWarning == nil {
                ActiveRideSessionStore.clear()
            } else {
                persistEndedSnapshot()
            }
            return summary
        }

        // 4.5 秒超时兜底：收尾可能还在后台继续，快照必须留到确认保存为止。
        persistEndedSnapshot()
        let fallbackId = rideId ?? UUID()
        return RideSummary(
            record: localSummaryRecord(id: fallbackId, endedAt: endedAt),
            checkedCheckpointIds: checkedCheckpointIds,
            awardedBadge: nil,
            allCheckpointsDone: !checkpoints.isEmpty && checkpoints.allSatisfy { checkedCheckpointIds.contains($0.id) },
            track: track,
            saveWarning: rideId == nil
                ? "骑行记录未能创建，本次轨迹与打卡没有保存"
                : "网络较慢，记录尚未同步完成，返回后可在骑行总结中重试",
            canRetrySave: rideId != nil
        )
    }

    /// 云端收尾未确认成功时保存的终态快照，冷启动只允许补存，不再继续记录。
    private func persistEndedSnapshot() {
        var snapshot = makeSnapshot()
        snapshot.phase = "ended"
        ActiveRideSessionStore.save(snapshot)
    }

    /// 逐项完成云端收尾。任何一步失败都不阻塞总结页返回。
    private func performCompletion(endedAt: String) async -> RideSummary? {
        await removePresence()
        // 行程结束：不再参与附近骑手统计
        if let tripId = TripSession.shared.tripId {
            _ = await TripService.updateStatus(client, tripId: tripId, status: "finished")
            TripSession.shared.tripId = nil
        }

        guard let rideId else {
            errorMessage = "骑行记录创建失败，请重试"
            return RideSummary(
                record: localSummaryRecord(id: UUID(), endedAt: endedAt),
                checkedCheckpointIds: checkedCheckpointIds,
                awardedBadge: nil,
                allCheckpointsDone: false,
                track: track,
                saveWarning: "骑行记录未能创建，本次轨迹与打卡没有保存"
            )
        }

        var saveWarning: String?
        // 轨迹点可能在网络抖动时留在内存里，结束前重试几轮再判定失败
        for _ in 0..<3 {
            await flushPoints()
            if pendingPoints.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(500))
        }
        if !pendingPoints.isEmpty {
            saveWarning = "部分轨迹点未同步，里程与轨迹可能不完整"
        }

        if !pendingCheckins.isEmpty {
            do {
                try await client.from("ride_checkins").insert(pendingCheckins).execute()
                pendingCheckins.removeAll()
            } catch {
                if saveWarning == nil {
                    saveWarning = "打卡记录未同步，徽章可能延迟到账"
                }
                errorMessage = error.wellwayUserMessage
            }
        }

        for attempt in 0..<3 {
            do {
                try await client.from("ride_records")
                    .update(["ended_at": endedAt, "status": "completed"])
                    .eq("id", value: rideId)
                    .execute()
                break
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(600 + attempt * 600))
                } else {
                    saveWarning = "骑行记录未能同步到服务器"
                    errorMessage = error.wellwayUserMessage
                }
            }
        }

        try? await client.rpc("recalculate_ride_stats", params: ["p_ride_id": rideId.uuidString]).execute()

        // 兜底：无 GPS 轨迹点时统计为 0,用本地计时补上骑行时长
        if durationS > 0 {
            try? await client.from("ride_records")
                .update(["duration_s": durationS])
                .eq("id", value: rideId)
                .eq("duration_s", value: 0)
                .execute()
        }

        var record: RideRecord?
        do {
            record = try await client
                .from("ride_records")
                .select("id, user_id, route_id, vehicle_id, started_at, ended_at, distance_m, duration_s, avg_speed_kmh, max_speed_kmh, elevation_gain_m, status")
                .eq("id", value: rideId)
                .single()
                .execute()
                .value
        } catch {
            errorMessage = error.wellwayUserMessage
            record = localSummaryRecord(id: rideId, endedAt: endedAt)
        }

        if saveWarning == nil, !NotificationHelper.isForeground && NotificationHelper.isEnabled("notifyRide") {
            if let record, !record.hasRecordedTrack {
                NotificationHelper.post(title: "骑行已结束", body: "\(route.name) 本次未记录有效轨迹")
            } else {
                NotificationHelper.post(title: "骑行完成", body: "\(route.name) 骑行已保存，去查看轨迹总结吧")
            }
        }

        let allDone = !checkpoints.isEmpty && checkpoints.allSatisfy { checkedCheckpointIds.contains($0.id) }
        var awarded: Badge?
        do {
            awarded = try await Self.awardBadgeIfNeeded(
                client: client,
                userId: userId,
                routeId: route.id,
                rideId: rideId,
                allCheckpointsDone: allDone
            )
        } catch {
            errorMessage = error.wellwayUserMessage
        }

        return RideSummary(
            record: record,
            checkedCheckpointIds: checkedCheckpointIds,
            awardedBadge: awarded,
            allCheckpointsDone: allDone,
            track: track,
            saveWarning: saveWarning,
            canRetrySave: true
        )
    }

    /// 结束骑行时发放徽章：全部打卡走路线徽章，否则兜底「新手首骑」。
    /// 正常结束和冷启动「结束并保存」共用，避免两条收尾路径给出不同结果。
    static func awardBadgeIfNeeded(
        client: SupabaseClient,
        userId: UUID,
        routeId: Int,
        rideId: UUID,
        allCheckpointsDone: Bool
    ) async throws -> Badge? {
        let owned: [UserBadge] = try await client
            .from("user_badges")
            .select("id, badge_id, ride_id, earned_at")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        let ownedIds = Set(owned.map(\.badgeId))

        var target: Badge?
        if allCheckpointsDone {
            let routeBadges: [Badge] = try await client
                .from("badges")
                .select("id, route_id, name, image_url, condition_desc, seq")
                .eq("route_id", value: routeId)
                .limit(1)
                .execute()
                .value
            target = routeBadges.first
        }
        // 「新手首骑」的条件是「完成第一次骑行记录」，和打卡点无关：
        // 之前只在打卡点全部完成时才尝试发放，导致骑了很多次徽章仍是 0/6。
        if target == nil {
            let global: [Badge] = try await client
                .from("badges")
                .select("id, route_id, name, image_url, condition_desc, seq")
                .is("route_id", value: nil)
                .order("seq")
                .limit(1)
                .execute()
                .value
            target = global.first
        }
        guard let badge = target, !ownedIds.contains(badge.id) else { return nil }
        _ = try await client.rpc("award_badge", params: [
            "p_user_id": userId.uuidString,
            "p_badge_id": String(badge.id),
            "p_ride_id": rideId.uuidString,
        ]).execute()
        return badge
    }

    private func localSummaryRecord(id: UUID, endedAt: String) -> RideRecord {
        let seconds = max(durationS, 0)
        let averageSpeed: Double? = {
            guard seconds > 0, distanceM > 0 else { return nil }
            return (distanceM / 1000) / (Double(seconds) / 3600)
        }()
        return RideRecord(
            id: id,
            userId: userId,
            routeId: route.id,
            vehicleId: vehicleId,
            name: nil,
            startedAt: isoFormatter.string(from: startedAt),
            endedAt: endedAt,
            distanceM: Int(distanceM.rounded()),
            durationS: seconds,
            avgSpeedKmh: averageSpeed,
            maxSpeedKmh: nil,
            elevationGainM: 0,
            status: "completed"
        )
    }

    /// 总结页「重试同步」：补传剩余轨迹/打卡，再把记录标记为 completed
    @discardableResult
    func retryCompletion() async -> Bool {
        guard let rideId else { return false }
        let ok = await AsyncDeadline.run(seconds: 8) { @MainActor [weak self] () -> Bool in
            guard let self else { return false }
            for _ in 0..<2 {
                await self.flushPoints()
                if self.pendingPoints.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if !self.pendingCheckins.isEmpty {
                do {
                    try await self.client.from("ride_checkins").insert(self.pendingCheckins).execute()
                    self.pendingCheckins.removeAll()
                } catch {
                    self.errorMessage = error.wellwayUserMessage
                }
            }
            let endedAt = self.isoFormatter.string(from: Date())
            for attempt in 0..<3 {
                do {
                    try await self.client.from("ride_records")
                        .update(["ended_at": endedAt, "status": "completed"])
                        .eq("id", value: rideId)
                        .execute()
                    ActiveRideSessionStore.clear()
                    self.errorMessage = nil
                    return true
                } catch {
                    self.errorMessage = error.wellwayUserMessage
                    if attempt < 2 {
                        try? await Task.sleep(for: .milliseconds(600 + attempt * 600))
                    }
                }
            }
            return false
        }
        return ok ?? false
    }

    // MARK: - 定位代理

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.handleLocation(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = "定位失败，请到开阔处或稍后重试"
        }
    }

    private func handleLocation(_ loc: CLLocation) {
        guard phase == .riding else { return }
        lastLat = loc.coordinate.latitude
        lastLng = loc.coordinate.longitude
        if loc.speed >= 0 {
            speedKmh = min(loc.speed * 3.6, 300)
        }
        // CoreLocation 正北会给 360.0(而非 0),统一归一到 [0,360),否则读取方按角度区间判断会漏掉正北
        if loc.course >= 0 { lastBearing = loc.course.truncatingRemainder(dividingBy: 360) }
        let delta: Double
        if let last = lastLocation {
            delta = loc.distance(from: last)
        } else {
            delta = 0
        }
        lastLocation = loc

        // 定位跳变过滤：相邻定位点位移超过 300m 视为漂移/异常(如首次修复错误),跳过该点，不累计里程也不记录轨迹
        guard delta <= 300 else { return }

        if delta > 2 {
            distanceM += delta
        }
        track.append(loc.coordinate)
        trackSamples.append(RideTrackSample(
            lat: loc.coordinate.latitude,
            lng: loc.coordinate.longitude,
            recordedAt: loc.timestamp,
            speedKmh: speedKmh,
            bearing: lastBearing
        ))

        guard let rideId else {
            persistSnapshot()
            return
        }
        pendingPoints.append(RidePointInsert(
            rideId: rideId,
            lat: loc.coordinate.latitude,
            lng: loc.coordinate.longitude,
            speedKmh: speedKmh,
            recordedAt: isoFormatter.string(from: loc.timestamp),
            bearing: supportsExtras == true ? lastBearing : nil
        ))

        checkCheckpoints(at: loc)

        if pendingPoints.count >= 30 {
            Task { await self.flushPoints() }
        }
        persistSnapshot()
    }

    private func checkCheckpoints(at loc: CLLocation) {
        for cp in checkpoints {
            guard !checkedCheckpointIds.contains(cp.id), let lat = cp.lat, let lng = cp.lng else { continue }
            let target = CLLocation(latitude: lat, longitude: lng)
            if loc.distance(from: target) <= Double(cp.radiusM) {
                checkedCheckpointIds.insert(cp.id)
                if let rideId {
                    pendingCheckins.append(RideCheckinInsert(
                        rideId: rideId,
                        checkpointId: cp.id,
                        userId: userId
                    ))
                }
                if !NotificationHelper.isForeground && NotificationHelper.isEnabled("notifyCheckin") {
                    NotificationHelper.post(title: "打卡完成", body: "已打卡 \(cp.name),加油!")
                }
            }
        }
    }

    private func flushPoints() async {
        guard let rideId, !pendingPoints.isEmpty else { return }
        let batch = Array(pendingPoints.prefix(100))
        pendingPoints.removeFirst(batch.count)
        do {
            try await client.from("ride_points").insert(batch).execute()
        } catch {
            pendingPoints.insert(contentsOf: batch, at: 0)
            errorMessage = error.wellwayUserMessage
        }
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.phase == .riding else { continue }
                self.settleDuration()
                // 没有定位回调时（模拟器、隧道、定位被拒），时长只能靠 ticker
                // 结算。这里按限频顺手落盘，进程被强杀也能恢复到最后一次写盘。
                self.persistSnapshot()
            }
        }
    }

    /// 把当前骑行段按墙钟时间并入总时长。暂停时结算并关闭当前段，
    /// 恢复时开启新段；ticker 每次唤醒只刷新展示值，不依赖唤醒次数。
    private func settleDuration() {
        guard let segmentStartedAt else { return }
        let now = Date()
        settledDurationS += max(0, now.timeIntervalSince(segmentStartedAt))
        self.segmentStartedAt = phase == .riding ? now : nil
        durationS = Int(settledDurationS.rounded(.down))
    }

    /// 探测云端是否已执行 0019 迁移(ride_points.bearing 是否存在)。
    /// 未执行时所有新增字段静默跳过，旧逻辑不受影响。
    private func probeSchemaSupport() async {
        guard supportsExtras == nil else { return }
        do {
            _ = try await client
                .from("ride_points")
                .select("bearing")
                .limit(1)
                .execute()
            supportsExtras = true
        } catch {
            supportsExtras = false
        }
    }

    /// 骑行中每 10 秒上报一次位置，供同路骑士实时列表使用
    private func startPresenceReporting() {
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.phase == .riding, let lat = self.lastLat, let lng = self.lastLng {
                    let row = RidePresenceInsert(
                        userId: self.userId,
                        routeId: self.route.id,
                        lat: lat,
                        lng: lng,
                        vehicleName: nil,
                        nickname: nil,
                        bearing: self.supportsExtras == true ? self.lastBearing : nil,
                        tripId: self.supportsExtras == true ? TripSession.shared.tripId : nil
                    )
                    try? await self.client
                        .from("ride_presence")
                        .upsert(row, onConflict: "user_id")
                        .execute()

                    // 匿名统计：后方同向 / 对向驶来(只返回数量，不含任何骑手信息)
                    if self.supportsExtras == true {
                        let counts = await TripService.ridersNearby(
                            self.client,
                            lat: lat,
                            lon: lng,
                            bearing: self.lastBearing
                        )
                        if let counts { self.nearbyRiders = counts }
                    }

                    // 同路提醒：只比较匿名汇总人数是否增加，不读取其他骑手身份或坐标
                    if NotificationHelper.isEnabled("notifySameway"),
                       let count = await TripService.ridersOnRoute(self.client, routeId: self.route.id) {
                        if self.companionsPrimed {
                            if count > self.lastCompanionCount {
                                NotificationHelper.companionAlert()
                            }
                        } else {
                            self.companionsPrimed = true
                        }
                        self.lastCompanionCount = count
                    }
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func removePresence() async {
        try? await client
            .from("ride_presence")
            .delete()
            .eq("user_id", value: userId)
            .execute()
    }
}

/// 冷启动时收尾没有快照可恢复的骑行。
/// 新版客户端会在骑行中持续写 `ActiveRideSession` 快照，冷启动优先走恢复流程；
/// 这里只兜底旧版本留下的、或快照丢失的 `riding` 记录，避免记录页出现幽灵「进行中」。
enum InterruptedRideRecovery {
    /// 返回被收尾的记录数，调用方据此决定是否解释去向。
    @discardableResult
    static func abandonInterruptedRides(client: SupabaseClient, userId: UUID) async -> Int {
        let stale: [RideRecordStatusRow] = (try? await client
            .from("ride_records")
            .select("id, status")
            .eq("user_id", value: userId)
            .eq("status", value: "riding")
            .execute()
            .value) ?? []
        guard !stale.isEmpty else { return 0 }
        let endedAt = ISO8601DateFormatter().string(from: Date())
        try? await client
            .from("ride_records")
            .update(["status": "abandoned", "ended_at": endedAt])
            .eq("user_id", value: userId)
            .eq("status", value: "riding")
            .execute()
        return stale.count
    }
}
