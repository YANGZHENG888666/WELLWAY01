import SwiftUI
import CoreLocation
import MapKit

/// 骑行中的安全救援页。
///
/// 提供紧急电话、真实定位分享，以及基于 MapKit 的附近医院 / 派出所查询。
/// 不提供救援调度，不自动通知任何人；查询失败时也不伪造附近救援点。
struct SafetyRescueView: View {
    let routeName: String
    let latitude: Double?
    let longitude: Double?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showShare = false
    @State private var showIncidentReport = false
    @State private var nearbyState: NearbyState = .idle
    @State private var isScrolled = false
    private var screenAppearance: ScreenAppearance { .shared }

    private static let nearbySearchRadius: CLLocationDistance = 8_000
    private static let nearbyResultLimit = 5

    private struct EmergencyLine: Identifiable {
        let id = UUID()
        let number: String
        let title: String
        let detail: String
    }

    private enum RescueKind: String {
        case hospital
        case police

        var title: String {
            switch self {
            case .hospital: return "医院"
            case .police: return "派出所"
            }
        }

        var symbol: String {
            switch self {
            case .hospital: return "cross.case.fill"
            case .police: return "shield.fill"
            }
        }

        var query: String {
            switch self {
            case .hospital: return "医院"
            case .police: return "派出所"
            }
        }

        var poiCategory: MKPointOfInterestCategory {
            switch self {
            case .hospital: return .hospital
            case .police: return .police
            }
        }
    }

    private struct RescuePlace: Identifiable {
        let id: String
        let name: String
        let kind: RescueKind
        let latitude: Double
        let longitude: Double
        let distance: CLLocationDistance

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    private enum NearbyState {
        case idle
        case loading
        case loaded([RescuePlace])
        case empty
        case failed
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

    private var searchKey: String {
        guard let coordinate else { return "none" }
        return String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
    }

    private var debugNearbyState: NearbyState? {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-sossearchloading") { return .loading }
        if arguments.contains("-sossearchempty") { return .empty }
        if arguments.contains("-sossearchfailed") { return .failed }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "安全救援", onBack: { dismiss() })
                // 页头实底到 86pt，正文滚到这里会被硬切，半行标题紧贴「安全救援」下沿。
                // 补一段 24pt 白→透明渐隐，让内容读成滑进页头下方。
                .overlay(alignment: .bottom) {
                    if isScrolled {
                        LinearGradient(
                            stops: [
                                .init(color: Color.white, location: 0),
                                .init(color: Color.white.opacity(0.96), location: 0.45),
                                .init(color: Color.white.opacity(0), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 24)
                        .offset(y: 24)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .zIndex(1)

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

                    sectionTitle("附近救援点", top: 28)
                    nearbyRescueContent

                    sectionTitle("事故记录", top: 28)
                    incidentEntry

                    sectionTitle("重要说明", top: 28)
                    Text("附近救援点来自系统地图搜索，仅作导航参考；是否接诊或受理请以现场为准。本页不会自动报警，也不会自动通知任何人，不提供救援调度。紧急情况请先确保自身安全，再拨打上方电话。分享位置只会打开系统分享面板，发送对象由你决定。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)

                    Color.clear.frame(height: 28)
                }
                .padding(.horizontal, 20)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SafetyScrollOffsetKey.self,
                            value: proxy.frame(in: .named("safetyScroll")).minY
                        )
                    }
                )
            }
            .coordinateSpace(name: "safetyScroll")
            .onPreferenceChange(SafetyScrollOffsetKey.self) { offset in
                let scrolled = offset < -2
                guard scrolled != isScrolled else { return }
                withAnimation(.easeInOut(duration: 0.15)) { isScrolled = scrolled }
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
        .fullScreenCover(isPresented: $showIncidentReport) {
            IncidentReportView(
                routeName: routeName,
                latitude: latitude,
                longitude: longitude
            )
        }
        .task(id: searchKey) {
            await loadNearbyRescuePlaces()
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

    /// 事故记录是“留存”而不是“报警”，因此做成扁平文字行，不与底部「分享我的位置」抢主行动。
    private var incidentEntry: some View {
        Button {
            showIncidentReport = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("记录事故现场")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("保存时间、路线、位置与经过，供本人留存")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .accessibilityHint("打开事故现场记录页，不会自动报警")
    }

    @ViewBuilder
    private var nearbyRescueContent: some View {
        switch nearbyState {
        case .idle:
            nearbyStatus(
                icon: "location.slash",
                title: "获取位置后可查找",
                message: "有定位后显示 8 公里内的医院与派出所。",
                showsRetry: false
            )
        case .loading:
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.textSecondary)
                    .frame(width: 22)
                Text("正在查找附近医院与派出所…")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
            .accessibilityLabel("正在查找附近医院与派出所")
        case .loaded(let places):
            VStack(spacing: 0) {
                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    rescueRow(place)
                    if index < places.count - 1 {
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
        case .empty:
            nearbyStatus(
                icon: "mappin.slash",
                title: "附近 8 公里内未找到",
                message: "这不代表附近没有救援资源，请直接拨打 120 或 110。",
                showsRetry: true
            )
        case .failed:
            nearbyStatus(
                icon: "exclamationmark.circle",
                title: "暂时无法查询附近救援点",
                message: "查询服务不可用，不代表附近没有救援资源。请直接拨打 120 或 110。",
                showsRetry: true
            )
        }
    }

    private func nearbyStatus(
        icon: String,
        title: String,
        message: String,
        showsRetry: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 22)
                .padding(.top, 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if showsRetry {
                Button {
                    Task { await loadNearbyRescuePlaces() }
                } label: {
                    Text("重试")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(IconPressStyle(pressedOpacity: 0.5))
                .accessibilityHint("重新查询附近医院与派出所")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private func rescueRow(_ place: RescuePlace) -> some View {
        Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
            item.name = place.name
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: place.kind.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text("\(place.kind.title) · \(distanceText(place.distance))")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.chevron)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel("\(place.name)，\(place.kind.title)，距当前位置\(distanceText(place.distance))")
        .accessibilityHint("在 Apple 地图中打开驾车导航")
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        if meters < 1_000 {
            return "\(max(1, Int(meters.rounded()))) m"
        }
        return String(format: "%.1f km", meters / 1_000)
    }

    @MainActor
    private func loadNearbyRescuePlaces() async {
        if let debugNearbyState {
            nearbyState = debugNearbyState
            return
        }

        guard let coordinate else {
            nearbyState = .idle
            return
        }

        nearbyState = .loading
        do {
            let places = try await Self.searchNearbyRescue(around: coordinate)
            guard !Task.isCancelled else { return }
            nearbyState = places.isEmpty ? .empty : .loaded(places)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            #if DEBUG
            print("SafetyRescue nearby search failed: \(error)")
            #endif
            nearbyState = .failed
        }
    }

    private enum NearbySearchError: Error {
        case unavailable
    }

    private static func searchNearbyRescue(
        around coordinate: CLLocationCoordinate2D
    ) async throws -> [RescuePlace] {
        async let hospitalTask = searchNearbyRescue(of: .hospital, around: coordinate)
        async let policeTask = searchNearbyRescue(of: .police, around: coordinate)

        var hospitalPlaces: [RescuePlace]?
        var policePlaces: [RescuePlace]?
        do { hospitalPlaces = try await hospitalTask } catch { hospitalPlaces = nil }
        do { policePlaces = try await policeTask } catch { policePlaces = nil }

        guard hospitalPlaces != nil || policePlaces != nil else {
            throw NearbySearchError.unavailable
        }

        var seen = Set<String>()
        var merged: [RescuePlace] = []
        for place in (hospitalPlaces ?? []) + (policePlaces ?? []) {
            let dedupeKey = "\(String(format: "%.5f", place.latitude)),\(String(format: "%.5f", place.longitude))"
            if seen.insert(dedupeKey).inserted {
                merged.append(place)
            }
        }

        return Array(
            merged
                .sorted { $0.distance < $1.distance }
                .prefix(nearbyResultLimit)
        )
    }

    private static func searchNearbyRescue(
        of kind: RescueKind,
        around coordinate: CLLocationCoordinate2D
    ) async throws -> [RescuePlace] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = kind.query
        request.region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: nearbySearchRadius * 2,
            longitudinalMeters: nearbySearchRadius * 2
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [kind.poiCategory])

        let response = try await MKLocalSearch(request: request).start()
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        return response.mapItems.compactMap { item in
            let itemCoordinate = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(itemCoordinate) else { return nil }

            let name = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }

            let target = CLLocation(
                latitude: itemCoordinate.latitude,
                longitude: itemCoordinate.longitude
            )
            let distance = origin.distance(from: target)
            guard distance <= nearbySearchRadius else { return nil }

            let id = "\(kind.rawValue)-\(String(format: "%.5f", itemCoordinate.latitude))-\(String(format: "%.5f", itemCoordinate.longitude))-\(name)"
            return RescuePlace(
                id: id,
                name: name,
                kind: kind,
                latitude: itemCoordinate.latitude,
                longitude: itemCoordinate.longitude,
                distance: distance
            )
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

/// 只在正文真正滚动后才显示页头下缘渐隐，避免静止态把第一条内容压灰。
private struct SafetyScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
