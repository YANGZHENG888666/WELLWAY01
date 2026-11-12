import CoreLocation
import Foundation

/// 系统权限请求：骑行开始时直接唤起 iOS 系统弹窗
/// (定位「使用期间+后台」 + 通知)。
enum PermissionHelper {
    /// 保留强引用，等待用户在系统授权弹窗中做出选择
    private static let locationRequester = LocationRequester()

    /// 定位请求代理：CLLocationManager 带 delegate 才能稳定触发授权回调，
    /// 避免连续弹出多个系统权限时定位请求被静默丢弃。
    private final class LocationRequester: NSObject, CLLocationManagerDelegate {
        let manager = CLLocationManager()
        private var pendingCompletion: (() -> Void)?
        private var waitingForAlways = false
        private var fallback: DispatchWorkItem?

        override init() {
            super.init()
            manager.delegate = self
        }

        /// 等系统定位弹窗有结论再回调。用户一直不点就 8 秒兜底，
        /// 免得因为一个没关的弹窗把后面的通知授权永远挂起。
        func request(completion: @escaping () -> Void) {
            let status = manager.authorizationStatus
            switch status {
            case .notDetermined:
                waitingForAlways = false
                pendingCompletion = completion
                manager.requestWhenInUseAuthorization()
                scheduleFallback()
            case .authorizedWhenInUse:
                // 已授权「使用期间」再升级「始终」,骑行后台持续记录轨迹需要
                waitingForAlways = true
                pendingCompletion = completion
                manager.requestAlwaysAuthorization()
                scheduleFallback()
            default:
                // 已拒绝或已「始终」：没有可等的弹窗，直接往下走
                completion()
            }
        }

        private func scheduleFallback() {
            fallback?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.finish() }
            fallback = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
        }

        private func finish() {
            fallback?.cancel()
            fallback = nil
            let completion = pendingCompletion
            pendingCompletion = nil
            completion?()
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            guard pendingCompletion != nil else { return }
            let status = manager.authorizationStatus
            if waitingForAlways {
                // 升级「始终」：只有真的升到 always 或用户明确拒绝才算有结论；
                // 保持「使用期间」时系统不一定再回一次回调，交给 8 秒兜底。
                if status == .authorizedAlways || status == .denied { finish() }
            } else if status != .notDetermined {
                finish()
            }
        }
    }

    /// 请求骑行真正需要的权限：定位(使用期间→后台)+ 通知。
    /// 本地网络/蓝牙目前没有任何对应功能，不再顺手申请，
    /// 避免同类 App 常见的"要一堆用不上的权限"。
    @MainActor
    static func requestRidePermissions() {
        // 定位先弹，等它对完再弹通知：两个系统弹窗前后脚压在一起，
        // 用户不知道第二个是在要什么，最常见的处理是把第二个也拒掉。
        locationRequester.request {
            Task {
                await NotificationHelper.requestAuthorizationIfNeeded()
            }
        }
    }

}
