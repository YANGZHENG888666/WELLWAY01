import SwiftUI

/// 页面数字调试标注：启动参数 `-pagenumbers` 开启后，每个页面右上角显示设计稿编号，
/// 编号对应 docs/PAGE-INDEX.md,方便按编号快速反馈问题。
enum PageMarker {
    static let enabled = ProcessInfo.processInfo.arguments.contains("-pagenumbers")
}

/// 右上角页号角标(设计稿编号),仅 `-pagenumbers` 启动时可见
private struct PageNumberBadge: ViewModifier {
    let number: Int

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if PageMarker.enabled {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 54)
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// 标注当前页面对应的设计稿编号(Figma 86 帧，见 docs/PAGE-INDEX.md)
    func pageMark(_ number: Int) -> some View {
        modifier(PageNumberBadge(number: number))
    }
}
