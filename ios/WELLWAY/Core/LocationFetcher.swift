import CoreLocation
import Foundation

/// 反向地理编码：当前位置 → 地名(系统 CLGeocoder,无需 key、无需联网配置)
enum PlaceNameService {
    /// "上海市·徐汇区" / "陆家嘴" 之类的地名；失败返回 nil
    static func name(for location: CLLocation) async -> String? {
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else {
            return nil
        }
        // 城市层级优先：限行查询按城市命中，不能先返回「陆家嘴」这类街区名。
        if let locality = placemark.locality, !locality.isEmpty,
           let sub = placemark.subLocality, !sub.isEmpty {
            return "\(locality)·\(sub)"
        }
        if let locality = placemark.locality, !locality.isEmpty { return locality }
        if let name = placemark.name, !name.isEmpty { return name }
        return placemark.administrativeArea
    }
}

/// 一次性当前位置获取(路线详情页「同路骑友」用)。
/// 与骑行中的 RideService 持续定位互不干扰：
/// 未授权时唤起一次系统授权弹窗；已授权则 requestLocation() 拿单次定位。
@MainActor
final class OneShotLocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var waitingForAuth = false
    private var retries = 0
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// 返回当前位置；未授权/被拒绝/定位失败返回 nil(不抛错)。
    func fetchLocation() async -> CLLocation? {
        await withCheckedContinuation { cont in
            continuation = cont
            retries = 0
            // 用户可能忽略系统授权弹窗，或定位服务持续不回调：
            // 8 秒后统一返回 nil，调用方必须能退出加载态。
            timeoutTask?.cancel()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(8))
                guard let self, !Task.isCancelled else { return }
                self.finish(with: nil)
            }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .notDetermined:
                waitingForAuth = true
                manager.requestWhenInUseAuthorization()
            default:
                finish(with: nil)
            }
        }
    }

    private func finish(with location: CLLocation?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        waitingForAuth = false
        continuation?.resume(returning: location)
        continuation = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            // 系统会在设置 delegate / 请求授权时立刻回调一次，此时仍是 notDetermined:
            // 继续等待用户选择，不能直接当作「被拒绝」
            guard status != .notDetermined else { return }
            guard waitingForAuth else {
                // 已经授权过(不是本次请求触发的),直接把状态交给 requestLocation 的结果
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    self.manager.requestLocation()
                }
                return
            }
            waitingForAuth = false
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.requestLocation()
            } else {
                finish(with: nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            finish(with: locations.first)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard continuation != nil else { return }
            // 刚启动 / 模拟器常见 locationUnknown:系统还没算出定位，重试几次再判失败
            if let clError = error as? CLError, clError.code == .locationUnknown, retries < 8 {
                retries += 1
                try? await Task.sleep(for: .milliseconds(500))
                guard continuation != nil else { return }
                manager.requestLocation()
                return
            }
            finish(with: nil)
        }
    }
}
