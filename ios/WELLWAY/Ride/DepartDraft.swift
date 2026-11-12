import Foundation
import Observation

/// 「P房选择目的地」暂存：把选中的路线带到出发 Tab(第三个 tab)
/// 在路线详情页点「添加到出发页」时写入，出发页据此选中并滚动到该路线。
@MainActor
@Observable
final class DepartDraft {
    static let shared = DepartDraft()

    var route: Route?
    var checkpoints: [Checkpoint] = []

    private init() {}
}
