import SwiftUI
import CoreLocation

/// 骑行中的安全救援页。
///
/// 只做两件真实可兑现的事：快捷拨打紧急电话、把当前真实定位交给系统分享面板。
/// 不提供救援调度，不自动通知任何人，也不展示没有数据来源的「附近救援点」。
struct SafetyRescueView: View {
    let routeName: String
    let latitude: Double?
    let longitude: Double?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showShare = false
    private var screenAppearance: ScreenAppearance { .shared }

    private struct EmergencyLine: Identifiable {
        let id = UUID()
        let number: String
        let title: String
        let detail: String
    }

    private let emergencyLines = [
        EmergencyLine(number: "110", title: "报警", detail: "人身安全受威胁或需要警方到场"),
        EmergencyLine(number: "120", title: "急救", detail: "受伤或身体不适需要医疗救助"),
        EmergencyLine(number: "122", title: "交通事故", detail: "道路交通事故报警与处理")
    ]

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        let value = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(value) else { return nil }
        return value
    }

    private var hasLocation: Bool { coordinate != nil }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "安全救援", onBack: { dismiss() })

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("需要帮助时，先确保自身安全。")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 4)

                    sectionTitle("紧急电话", top: 26)

                    VStack(spacing: 0) {
                        ForEach(Array(emergencyLines.enumerated()), id: \.element.id) { index, line in
                            emergencyRow(line)
                            if index < emergencyLines.count - 1 {
                                Rectangle()
                                    .fill(Theme.separator)
                                    .frame(height: 1)
                            }
                        }
                    }
                    .overlay(alignment: .top) {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.separator).frame(height: 1)
                    }

                    sectionTitle("我的位置", top: 28)
                    locationBlock

                    sectionTitle("重要说明", top: 28)
                    Text("本页不会自动报警，也不会自动通知任何人，不提供救援调度。紧急情况请先确保自身安全，再拨打上方电话。分享位置只会打开系统分享面板，发送对象由你决定。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)

                    Color.clear.frame(height: 28)
                }
                .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { shareBar }
        .preferredColorScheme(.light)
        .onAppear { screenAppearance.push(.light) }
        .onDisappear { screenAppearance.pop(.light) }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
    }

    private func sectionTitle(_ title: String, top: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, top)
            .padding(.bottom, 4)
    }

    private func emergencyRow(_ line: EmergencyLine) -> some View {
        Button {
            guard let url = URL(string: "tel://\(line.number)") else { return }
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(line.number)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text(line.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(line.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 4) {
                    Text("拨打")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "phone.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(Theme.danger)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("拨打 \(line.number)，\(line.title)")
        .accessibilityHint("将打开系统电话确认")
    }

    private var locationBlock: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hasLocation ? "location.fill" : "location.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(hasLocation ? Theme.successText : Theme.listGray)
                .frame(width: 22)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(hasLocation ? "当前位置已就绪" : "尚未获取到当前位置")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(hasLocation
                     ? "分享时会附带 Apple 地图链接，由你选择发送对象。"
                     : "定位恢复后即可分享；紧急情况请先直接拨打上方电话。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private var shareBar: some View {
        Button {
            showShare = true
        } label: {
            Text(hasLocation ? "分享我的位置" : "暂无法分享位置")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(hasLocation ? Color.white : Theme.listGray)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(hasLocation ? Color.black : Theme.lightField)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SolidPressStyle())
        .disabled(!hasLocation)
        .accessibilityHint(hasLocation
                           ? "打开系统分享面板，把当前位置发给亲友"
                           : "定位恢复后才能分享位置")
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .wellwayBottomBar()
    }

    private var shareText: String {
        guard let coordinate else { return "" }
        let lat = String(format: "%.6f", coordinate.latitude)
        let lng = String(format: "%.6f", coordinate.longitude)
        let link = "https://maps.apple.com/?ll=\(lat),\(lng)&q=\(lat),\(lng)"
        return "我在骑行「\(routeName)」，需要帮助。我的位置：\n\(link)"
    }
}
