import Foundation
import Observation
import Supabase
import UIKit

/// 账号管理：支持匿名账号、邮箱验证码登录/注册、账号密码登录、忘记密码。
@MainActor
@Observable
final class AuthManager {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn
    }

    private(set) var state: State = .loading
    private(set) var session: Session?
    private(set) var user: User?
    private(set) var profile: Profile?
    var errorMessage: String?
    /// 刚完成登录(邮箱验证码 / 账号密码),需先展示「登录成功页」过渡
    private(set) var pendingLoginSuccess = false
    private var privacyAgreementUploaded = false
    private var privacyAgreementAttempted = false

    /// 把 Supabase/GoTrue 原始报错转成中文友好文案(App Store 审核要求：面向用户提示不可显示原始英文错误)
    private func friendlyError(_ error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("invalid login credentials") || raw.contains("invalid credentials") {
            return "邮箱或密码不正确"
        }
        if raw.contains("email not confirmed") || raw.contains("email not verified") {
            return "邮箱尚未验证，请先完成验证"
        }
        if raw.contains("already registered") || raw.contains("user already exists") {
            return "该邮箱已注册，请直接登录"
        }
        if raw.contains("signups not allowed") || raw.contains("signup disabled") {
            return "当前暂不支持注册新账号"
        }
        if raw.contains("rate limit") || raw.contains("too many requests") || raw.contains("over_request_rate_limit") {
            return "操作过于频繁，请稍后再试"
        }
        if raw.contains("network") || raw.contains("offline") || raw.contains("internet") {
            return "网络异常，请检查网络连接后重试"
        }
        if raw.contains("timeout") || raw.contains("timed out") {
            return "请求超时，请稍后重试"
        }
        if raw.contains("invalid otp") || raw.contains("otp expired") || raw.contains("invalid token") || raw.contains("token has expired") {
            return "验证码错误或已过期"
        }
        if raw.contains("user not found") {
            return "账号不存在，请检查后重试"
        }
        return "操作失败，请稍后重试"
    }

    let client: SupabaseClient

    init() {
        client = SupabaseClient(supabaseURL: AppConfig.supabaseURL, supabaseKey: AppConfig.supabaseAnonKey)
    }

    /// 启动时恢复本地会话；没有会话则停在登录页(不自动匿名登录)
    /// 网络不可达(例如 Supabase 域名解析失败)时不再无限等待，优先使用本地缓存会话
    func bootstrap() async {
        state = .loading
        let client = self.client
        // 本地已有会话就直接进入，不再等网络(Supabase 不可达时也能进 App)
        if let cached = client.auth.currentSession {
            session = cached
            user = cached.user
            state = .signedIn
            Task { [weak self] in
                await self?.refreshProfile()
            }
            return
        }
        let restored: Session? = await Self.runWithTimeout(seconds: 6) {
            try await client.auth.session
        }

        if let restored = restored ?? client.auth.currentSession {
            session = restored
            user = restored.user
            state = .signedIn
            // 资料与隐私上报不阻塞启动，失败时下一次进前台再补
            Task { [weak self] in
                await self?.refreshProfile()
            }
        } else {
            session = nil
            user = nil
            state = .signedOut
        }
    }

    /// 超时保护：底层请求可能因 DNS/网络问题长时间挂起，超过时限返回 nil
    /// 用 GCD 计时而不是 Task.sleep,避免请求把协作线程池占满时超时不生效
    private static func runWithTimeout<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> T
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let lock = NSLock()
            var finished = false

            let work = Task {
                let value = try? await operation()
                lock.lock()
                let isFirst = !finished
                if isFirst { finished = true }
                lock.unlock()
                if isFirst { continuation.resume(returning: value) }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                lock.lock()
                let isFirst = !finished
                if isFirst { finished = true }
                lock.unlock()
                if isFirst {
                    work.cancel()
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 随便看看：匿名账号进入(showWelcome=true 时直接切 signedIn 显示欢迎页，跳过 loading 避免闪帧)
    func signInAnonymously(showWelcome: Bool = false) async {
        if showWelcome {
            // 先置欢迎标记并切 signedIn,RootView 立即显示欢迎页；失败再回退
            pendingLoginSuccess = true
            state = .signedIn
        } else {
            state = .loading
        }
        do {
            let newSession = try await client.auth.signInAnonymously()
            session = newSession
            user = newSession.user
            errorMessage = nil
            state = .signedIn
            await refreshProfile()
        } catch {
            pendingLoginSuccess = false
            state = .signedOut
            errorMessage = friendlyError(error)
        }
    }

    /// 已有账户立即登录(账号密码)
    func signInWithPassword(email: String, password: String) async {
        state = .loading
        do {
            let newSession = try await client.auth.signIn(email: email, password: password)
            session = newSession
            user = newSession.user
            errorMessage = nil
            pendingLoginSuccess = true
            state = .signedIn
            await refreshProfile()
        } catch {
            state = .signedOut
            errorMessage = friendlyError(error)
        }
    }

    /// 邮箱验证码登录/注册：发送验证码(不存在会自动建档);成功返回 true
    @discardableResult
    func sendEmailCode(_ email: String) async -> Bool {
        do {
            _ = try await client.auth.signInWithOTP(email: email)
            errorMessage = nil
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    /// 校验邮箱验证码并登录(enterApp=false 时仅校验，不切换主界面)
    func verifyEmailCode(email: String, token: String, enterApp: Bool = true) async {
        do {
            // 直接用 verifyOTP 返回的会话，避免依赖 Keychain 持久化(模拟器/沙盒环境
            // 无签名时写入可能失败，导致随后读取 session 抛错而误报「验证码填写错误」)
            let response = try await client.auth.verifyOTP(email: email, token: token, type: .email)
            if let responseSession = response.session {
                session = responseSession
                user = responseSession.user
            } else {
                session = try await client.auth.session
                user = try await client.auth.user()
            }
            errorMessage = nil
            if enterApp {
                pendingLoginSuccess = true
                state = .signedIn
                await refreshProfile()
            }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// 忘记密码第二步：校验通过后设置新密码，并退出回到登录页
    func setNewPassword(_ password: String) async {
        do {
            _ = try await client.auth.update(user: UserAttributes(password: password))
            try? await client.auth.signOut()
            session = nil
            user = nil
            profile = nil
            pendingLoginSuccess = false
            state = .signedOut
            errorMessage = nil
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// 读取自己的资料(匿名建档触发器会在服务端自动创建)
    func refreshProfile() async {
        guard let uid = user?.id else { return }
        do {
            let loaded: Profile = try await client
                .from("profiles")
                .select("id, nickname, avatar_url, email_bound")
                .eq("id", value: uid)
                .single()
                .execute()
                .value
            profile = loaded
        } catch {
            // 资料表尚未创建时静默忽略，下次再读
        }
        await uploadPrivacyAgreementIfNeeded()
    }

    /// 勾选隐私协议后落库(profiles.privacy_agreed_at,迁移 0019 新增列)。
    /// 未登录、未勾选、已上报过或迁移未执行时静默跳过，不影响主流程。
    private func uploadPrivacyAgreementIfNeeded() async {
        guard !privacyAgreementUploaded, !privacyAgreementAttempted else { return }
        guard UserDefaults.standard.bool(forKey: "agreementAccepted") else { return }
        guard let uid = user?.id else { return }
        privacyAgreementAttempted = true
        do {
            try await client
                .from("profiles")
                .update(["privacy_agreed_at": ISO8601DateFormatter().string(from: Date())])
                .eq("id", value: uid)
                .execute()
            privacyAgreementUploaded = true
        } catch {
            // 迁移未执行(列不存在)时静默忽略
        }
    }

    @discardableResult
    func updateNickname(_ nickname: String) async -> Bool {
        guard let uid = user?.id else { return false }
        errorMessage = nil
        do {
            try await client
                .from("profiles")
                .update(["nickname": nickname])
                .eq("id", value: uid)
                .execute()
            await refreshProfile()
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    /// 上传头像(avatars 桶 → 更新 profiles.avatar_url),失败时 errorMessage 带原因
    @discardableResult
    func updateAvatar(imageData: Data) async -> Bool {
        guard let uid = user?.id else { return false }
        errorMessage = nil
        do {
            // Storage RLS 用 auth.uid()::text(小写) 比对目录名，UUID.uuidString 是大写，必须转小写
            let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            let previousPath = profile?.avatarUrl
            try await client.storage.from("avatars").upload(
                path,
                data: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )
            do {
                try await client
                    .from("profiles")
                    .update(["avatar_url": path])
                    .eq("id", value: uid)
                    .execute()
            } catch {
                // 资料写入失败时新对象尚未被引用，立即清掉，避免每次失败都留下孤立文件
                try? await client.storage.from("avatars").remove(paths: [path])
                throw error
            }
            if let current = profile {
                profile = Profile(
                    id: current.id,
                    nickname: current.nickname,
                    avatarUrl: path,
                    emailBound: current.emailBound
                )
            }
            await refreshProfile()
            if let previousPath, !previousPath.isEmpty, previousPath != path {
                // 资料已指向新头像，旧头像不再被任何页面使用
                try? await client.storage.from("avatars").remove(paths: [previousPath])
            }
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    /// 读取当前头像图片(未设置或下载失败返回 nil)
    func loadAvatarImage() async -> UIImage? {
        guard let path = profile?.avatarUrl, !path.isEmpty else { return nil }
        do {
            let data = try await client.storage.from("avatars").download(path: path)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// 第一步：发送绑定邮箱的 OTP;成功返回 true
    @discardableResult
    func sendEmailOTP(_ email: String) async -> Bool {
        do {
            _ = try await client.auth.update(user: UserAttributes(email: email))
            errorMessage = nil
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    /// 第二步：校验 OTP,完成邮箱绑定；成功返回 true
    @discardableResult
    func verifyEmailOTP(email: String, token: String) async -> Bool {
        do {
            _ = try await client.auth.verifyOTP(email: email, token: token, type: .email)
            errorMessage = nil
            await refreshProfile()
            return true
        } catch {
            errorMessage = friendlyError(error)
            return false
        }
    }

    func signOut() async {
        try? await client.auth.signOut()
        session = nil
        user = nil
        profile = nil
        pendingLoginSuccess = false
        state = .signedOut
    }

    /// 注销账号：永久删除账号与全部个人数据(个保法第47条 / App Store 5.1.1(v))
    /// 服务端 delete_my_account() 删除 auth.users 记录， 关联数据级联清除；
    /// 车辆照片存放在 Storage 桶 vehicle-photos/<uid>/, 需先经 Storage API
    /// 删除(直接 SQL 删除 storage.objects 会被 Supabase 拦截 42501)。
    /// 成功后清空本地会话， 回到登录页。
    func deleteAccount() async {
        do {
            // 1. 删除该用户 Storage 中的车辆照片(RLS 允许删除自己目录下的对象)
            if let uid = user?.id.uuidString.lowercased() {
                // 头像与车辆照片都在 <uid>/ 目录下，注销时一并清掉
                for bucket in ["vehicle-photos", "avatars"] {
                    let items = try? await client.storage.from(bucket).list(path: uid)
                    let paths = (items ?? []).map { "\(uid)/\($0.name)" }
                    if !paths.isEmpty {
                        try? await client.storage.from(bucket).remove(paths: paths)
                    }
                }
            }
            // 2. 删除 auth.users(其余用户数据表级联清除)
            try await client.rpc("delete_my_account").execute()
            try? await client.auth.signOut()
            // 清理本地缓存(自定义骑行名等用户内容),避免注销后残留
            UserDefaults.standard.dictionaryRepresentation().keys
                .forEach { UserDefaults.standard.removeObject(forKey: $0) }
            session = nil
            user = nil
            profile = nil
            pendingLoginSuccess = false
            state = .signedOut
            errorMessage = nil
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    /// 登录成功页「进入」:收下过渡页，进入主界面
    func enterMain() {
        pendingLoginSuccess = false
    }
}
