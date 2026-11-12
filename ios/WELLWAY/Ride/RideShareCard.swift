import SwiftUI
import UIKit

/// 骑行分享卡：1080×1350（4:5），深色底。
/// 只放真实数据：没有轨迹时不画轨迹、不出里程和均速。
struct RideShareCard: View {
    static let size = CGSize(width: 1080, height: 1350)

    let routeName: String
    let dateText: String
    let endpoints: String
    let metrics: [(label: String, value: String)]
    let unitPoints: [CGPoint]
    let hasTrack: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.darkBackground

            VStack(alignment: .leading, spacing: 0) {
                // 与开屏、关于页共用真实字标；系统字重排的 "WellWay" 笔画和品牌字形对不上。
                Image("Wordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .frame(width: 150, height: 46)
                    .accessibilityLabel("WellWay")

                Spacer(minLength: 0)

                Text(routeName)
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !dateText.isEmpty {
                    Text(dateText)
                        .font(.system(size: 28))
                        // 分享卡会被平台压到几百像素宽，0.55 的次级文字在缩略图里基本糊掉
                        .foregroundStyle(Color.white.opacity(0.62))
                        .padding(.top, 18)
                }

                // 起终点属于「这条是哪次」的一部分，和时间放在一起；
                // 放在四栏指标下面会被读成第一栏「里程」的注解。
                if !endpoints.isEmpty {
                    Text(endpoints)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.top, 10)
                }

                trackPanel
                    .padding(.top, 44)

                Spacer(minLength: 0)

                HStack(spacing: 0) {
                    ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                        if index > 0 {
                            // 卡片会被平台压到几百像素宽：1pt / 20% 的分隔线在缩略图里直接消失，
                            // 四栏数值看起来像挤在一起。加粗到 2pt 并提亮一档。
                            Rectangle()
                                .fill(Color.white.opacity(0.28))
                                .frame(width: 2, height: dividerHeight)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(metric.value)
                                .font(.system(size: metricValueSize, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(metric.label)
                                .font(.system(size: metricLabelSize))
                                .foregroundStyle(Color.white.opacity(0.62))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, index == 0 ? 0 : metricLead)
                    }
                }

            }
            .padding(72)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// 四项指标(里程/时长/均速/爬升)在 1080 宽的卡片里各占 234pt，
    /// 48pt 的「19.7 km/h」会溢出到下一列、把分隔线压没；四项时整体降一档。
    private var metricValueSize: CGFloat { metrics.count >= 4 ? 40 : 48 }
    private var metricLabelSize: CGFloat { metrics.count >= 4 ? 22 : 24 }
    private var metricLead: CGFloat { metrics.count >= 4 ? 24 : 32 }
    private var dividerHeight: CGFloat { metrics.count >= 4 ? 64 : 78 }

    private var trackPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.darkCard)

            if hasTrack, unitPoints.count >= 2 {
                TrackPreview(
                    unitPoints: unitPoints,
                    trackRect: CGRect(x: 56, y: 56, width: 864, height: 288),
                    startDot: .zero,
                    endDot: .zero,
                    dotSize: 20
                )
            } else {
                Text("本次骑行未记录轨迹")
                    .font(.system(size: 26))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        // 无轨迹时不要留一块 400pt 的空框：卡面上最显眼的会是「未记录」这句否定，
        // 分享出去像卡坏了。收窄成一条说明条，把版面还给标题和指标。
        .frame(width: 936, height: hasTrack ? 400 : 220)
    }
}

@MainActor
enum RideShareCardRenderer {
    static func image(
        routeName: String,
        dateText: String,
        endpoints: String,
        metrics: [(label: String, value: String)],
        unitPoints: [CGPoint],
        hasTrack: Bool
    ) -> UIImage? {
        let card = RideShareCard(
            routeName: routeName,
            dateText: dateText,
            endpoints: endpoints,
            metrics: metrics,
            unitPoints: unitPoints,
            hasTrack: hasTrack
        )
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
