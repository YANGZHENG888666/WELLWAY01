import SwiftUI

/// 迷你柱状图(黑色圆角柱，入场自底部生长，用于数据统计可视化)
struct MiniBars: View {
    let heights: [CGFloat]
    var width: CGFloat = 3
    var spacing: CGFloat = 3
    var color: Color = .black
    var delay: Double = 0
    var stagger: Double = 0.05

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, h in
                MiniBar(height: h, width: width, color: color, delay: delay + Double(index) * stagger)
            }
        }
    }
}

private struct MiniBar: View {
    let height: CGFloat
    let width: CGFloat
    let color: Color
    let delay: Double
    @State private var grown = false

    var body: some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: grown ? height : 0)
            .onAppear {
                withAnimation(Motion.appear.delay(delay)) { grown = true }
            }
    }
}
