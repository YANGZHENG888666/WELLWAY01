import SwiftUI
import UIKit

/// 键盘避让方案：页面与根容器都忽略键盘安全区，系统不再自动上推整页。
/// 键盘态的位移完全由页面自身(kbShift)动画控制 → 品牌区全程不动、无闪动。
struct KeyboardPageFix: ViewModifier {
    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(.keyboard)
    }
}
