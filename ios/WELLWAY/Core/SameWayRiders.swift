import CoreLocation
import Foundation

/// 同路骑友走廊匹配(客户端计算；详情页与卡片模式共用同一份逻辑):
/// 统计「我的位置 → 路线起点」走廊内、方向一致(比我更接近起点)的活跃骑友数。
enum SameWayRiders {
    /// 走廊单侧宽度(米)
    static let corridorHalfWidth: CLLocationDistance = 200
    /// 方向判定容差(米)
    static let aheadSlack: CLLocationDistance = 200

    static func count(me: CLLocation,
                      startLat: Double,
                      startLng: Double,
                      riders: [RidePresence],
                      excludeUserId: UUID?) -> Int {
        let start = CLLocation(latitude: startLat, longitude: startLng)
        let myDistanceToStart = me.distance(from: start)
        var count = 0
        for row in riders {
            if let excludeUserId, row.userId == excludeUserId { continue }
            let rider = CLLocation(latitude: row.lat, longitude: row.lng)
            guard rider.distance(from: start) <= myDistanceToStart + aheadSlack else { continue }
            guard distanceToSegment(rider, from: me, to: start) <= corridorHalfWidth else { continue }
            count += 1
        }
        return count
    }

    /// 点到线段的最短距离(米)。短距离内用经纬度平面投影取垂足，再算真实球面距离。
    static func distanceToSegment(_ p: CLLocation, from a: CLLocation, to b: CLLocation) -> CLLocationDistance {
        let ax = a.coordinate.latitude, ay = a.coordinate.longitude
        let bx = b.coordinate.latitude, by = b.coordinate.longitude
        let px = p.coordinate.latitude, py = p.coordinate.longitude
        let dx = bx - ax, dy = by - ay
        let lenSq = dx * dx + dy * dy
        var t: Double = 0
        if lenSq > 0 {
            t = min(max(((px - ax) * dx + (py - ay) * dy) / lenSq, 0), 1)
        }
        let closest = CLLocation(latitude: ax + t * dx, longitude: ay + t * dy)
        return closest.distance(from: p)
    }
}
