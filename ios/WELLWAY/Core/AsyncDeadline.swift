import Foundation

/// 限时执行：到点立即返回 nil，不等底层网络请求自然超时。
/// 超时后底层任务会被取消，但调用方必须自行保留未确认的数据。
enum AsyncDeadline {
    static func run<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let lock = NSLock()
            var finished = false

            let work = Task {
                let value = await operation()
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
}
