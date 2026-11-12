import Foundation
import AudioToolbox
import UserNotifications
import UIKit

/// 本地通知助手：对向提醒 / 打卡完成 / 骑行完成
enum NotificationHelper {
    /// 通知开关(与设置页 UserDefaults 一致)
    static func isEnabled(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// 需要时申请通知权限(骑行开始时调用)
    static func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// 是否在前台(前台不弹横幅，避免打扰)
    static var isForeground: Bool {
        UIApplication.shared.applicationState == .active
    }

    static func post(title: String, body: String, identifier: String = UUID().uuidString) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 对向提醒(安全优先):
    /// - 前台(骑行中):只播放短促提示音，不弹横幅、不打断视线，避免影响驾驶；
    /// - 后台/锁屏：走系统通知横幅 + 声音。
    static func companionAlert() {
        if isForeground {
            AudioServicesPlaySystemSound(1057) // 短促「叮」提示音
        } else {
            post(title: "对向提醒", body: "附近有骑手正在同路线骑行", identifier: "companion-\(UUID().uuidString)")
        }
    }
}
