import SwiftUI
import CoreLocation

/// 事故现场记录。
///
/// 只做现场留存：保存时间、路线、真实坐标与用户填写的经过，便于本人、家人、
/// 保险或维修方核对。不会自动报警、不会通知任何人，也不提供救援调度。
/// 无定位时仍允许提交，但必须明确显示「位置不可用」，不能填假坐标。
struct IncidentReportView: View {
    let routeName: String
    let latitude: Double?
    let longitude: Double?

    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var kind: IncidentKind? = IncidentReportView.debugKind
    @State private var note: String = IncidentReportView.debugNote
    @State private var occurredAt = Date()
    @State private var submitting = IncidentReportView.isDebugSubmitting
    @State private var errorText: String? = IncidentReportView.debugError
    @State private var receipt: IncidentReportReceipt? = IncidentReportView.debugReceipt
    @State private var showShare = false
    @FocusState private var noteFocused: Bool
    private var screenAppearance: ScreenAppearance { .shared }

    private enum IncidentKind: String, CaseIterable, Identifiable {
        case fall
        case collision
        case breakdown
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .fall: return "摔车"
            case .collision: return "碰撞"
            case .breakdown: return "车辆故障"
            case .other: return "其他"
            }
        }
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static var arguments: [String] { ProcessInfo.processInfo.arguments }
    private static var isDebugFailure: Bool { arguments.contains("-sosaccidentfailed") }
    private static var isDebugReceipt: Bool { arguments.contains("-sosaccidentreceipt") }
    private static var isDebugSubmitting: Bool { arguments.contains("-sosaccidentsubmitting") }
    private static var debugKind: IncidentKind? {
        isDebugFailure || isDebugReceipt || isDebugSubmitting ? .collision : nil
    }
    private static var debugNote: String {
        isDebugFailure || isDebugReceipt || isDebugSubmitting
            ? "在路口被后车追尾，人无大碍，右侧后视镜损坏，对方已停车。"
            : ""
    }
    private static var debugError: String? {
        isDebugFailure ? "提交失败，记录仍保留在页面上。请检查网络后重试。" : nil
    }
    private static var debugReceipt: IncidentReportReceipt? {
        guard isDebugReceipt else { return nil }
        return IncidentReportReceipt(id: 1042, occurredAt: isoFormatter.string(from: Date()))
    }

    private var coordinate: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        guard CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) else {
            return nil
        }
        return (latitude, longitude)
    }

    private var locationText: String {
        guard let coordinate else { return "位置不可用（仍可提交）" }
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var trimmedNote: String {
        note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        kind != nil && !submitting
    }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: "记录事故现场", onBack: { dismiss() })

            if let receipt {
                receiptContent(receipt)
            } else {
                formContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .preferredColorScheme(.light)
        .onAppear { screenAppearance.push(.light) }
        .onDisappear { screenAppearance.pop(.light) }
        .sheet(isPresented: $showShare) {
            ShareSheet(items: [shareText])
        }
    }

    // MARK: - 填写

    private var formContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("先拨打 110 / 120 / 122")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("这里只留存现场记录，不会自动报警、不会通知任何人，也不提供救援调度。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }

                sectionTitle("事故类型", top: 24)
                kindList

                sectionTitle("事故经过", top: 24)
                noteEditor

                sectionTitle("现场信息", top: 24)
                infoList

                Text("时间、路线、位置与 App 版本会自动附在记录中。位置不可用时不会填写虚假坐标。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func sectionTitle(_ title: String, top: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, top)
            .padding(.bottom, 4)
    }

    private var kindList: some View {
        VStack(spacing: 0) {
            ForEach(Array(IncidentKind.allCases.enumerated()), id: \.element.id) { index, item in
                Button {
                    kind = item
                    errorText = nil
                    Haptics.selection()
                } label: {
                    HStack(spacing: 12) {
                        Text(item.title)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Image(systemName: kind == item ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(kind == item ? Theme.textPrimary : Theme.chevron)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .accessibilityAddTraits(kind == item ? .isSelected : [])

                if index < IncidentKind.allCases.count - 1 {
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
    }

    private var noteEditor: some View {
        ZStack(alignment: .topLeading) {
            if note.isEmpty {
                Text("补充事故经过、伤情、对方车辆或现场情况（选填）")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.listGray)
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $note)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .focused($noteFocused)
                .accessibilityLabel("事故经过，选填")
                .padding(.horizontal, 7)
                .padding(.top, 6)
        }
        .frame(height: 132)
        .background(Theme.lightField)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text("\(note.count)/500")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .padding(9)
        }
        .onChange(of: note) { _, value in
            errorText = nil
            if value.count > 500 {
                note = String(value.prefix(500))
            }
        }
    }

    private var infoList: some View {
        VStack(spacing: 0) {
            infoRow(label: "时间", value: Self.displayFormatter.string(from: occurredAt))
            hairline
            infoRow(label: "路线", value: routeName.isEmpty ? "未记录路线" : routeName)
            hairline
            infoRow(label: "位置", value: locationText)
            hairline
            infoRow(label: "版本", value: appVersion)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.separator).frame(height: 1)
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 40, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 48)
    }

    // MARK: - 回执

    private func receiptContent(_ receipt: IncidentReportReceipt) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("记录已保存")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("已保存到你的账号。紧急情况请立即拨打 110 / 120 / 122；本记录不会自动报警，也不会通知任何人。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }

                sectionTitle("回执", top: 24)
                VStack(spacing: 0) {
                    infoRow(label: "编号", value: "#\(receipt.id)")
                    hairline
                    infoRow(label: "时间", value: receiptTime(receipt))
                    hairline
                    infoRow(label: "类型", value: kind?.title ?? "未记录")
                    hairline
                    infoRow(label: "路线", value: routeName.isEmpty ? "未记录路线" : routeName)
                    hairline
                    infoRow(label: "位置", value: locationText)
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }

                if !trimmedNote.isEmpty {
                    sectionTitle("经过", top: 24)
                    Text(trimmedNote)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }

                sectionTitle("留存", top: 24)
                Button {
                    showShare = true
                } label: {
                    HStack {
                        Text("分享文字记录")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.chevron)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }

                Color.clear.frame(height: 24)
            }
            .padding(.horizontal, 20)
        }
    }

    private func receiptTime(_ receipt: IncidentReportReceipt) -> String {
        let date = ISO8601DateFormatter.wellwayDate(from: receipt.occurredAt) ?? occurredAt
        return Self.displayFormatter.string(from: date)
    }

    private var shareText: String {
        guard let receipt else { return "" }
        var lines = [
            "WELLWAY 事故记录回执 #\(receipt.id)",
            "时间：\(receiptTime(receipt))",
            "类型：\(kind?.title ?? "未记录")",
            "路线：\(routeName.isEmpty ? "未记录" : routeName)",
            "位置：\(locationText)"
        ]
        if let coordinate {
            lines.append(String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=%.6f,%.6f",
                                coordinate.latitude, coordinate.longitude,
                                coordinate.latitude, coordinate.longitude))
        }
        if !trimmedNote.isEmpty {
            lines.append("")
            lines.append("经过：\(trimmedNote)")
        }
        lines.append("")
        lines.append("紧急情况请拨打 110 / 120 / 122。本记录仅作现场留存，不会自动报警。")
        return lines.joined(separator: "\n")
    }

    // MARK: - 底部主行动

    private var bottomBar: some View {
        Group {
            if receipt != nil {
                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SolidPressStyle())
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if let errorText {
                        Text(errorText)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.danger)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        submit()
                    } label: {
                        Group {
                            if submitting {
                                HStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text("正在提交…")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(Color.white)
                                }
                            } else {
                                Text(errorText == nil ? "提交记录" : "重新提交")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(canSubmit ? Color.white : Theme.listGray)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(canSubmit || submitting ? Color.black : Theme.lightField)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(SolidPressStyle())
                    .allowsHitTesting(canSubmit)
                    .accessibilityHint(kind == nil ? "请先选择事故类型" : "保存本次事故现场记录")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .wellwayBottomBar()
    }

    // MARK: - 提交

    private func submit() {
        guard let kind, !submitting else { return }
        guard let userId = auth.session?.user.id else {
            errorText = "登录状态已失效，请重新登录后再提交"
            return
        }

        submitting = true
        errorText = nil
        noteFocused = false

        let payload = IncidentReportInsert(
            userId: userId,
            routeName: routeName.isEmpty ? nil : routeName,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            incidentType: kind.rawValue,
            note: trimmedNote,
            occurredAt: Self.isoFormatter.string(from: occurredAt),
            appVersion: appVersion
        )

        Task { @MainActor in
            do {
                let saved: IncidentReportReceipt = try await auth.client
                    .from("incident_reports")
                    .insert(payload)
                    .select("id, occurred_at")
                    .single()
                    .execute()
                    .value
                submitting = false
                receipt = saved
                Haptics.tap()
            } catch {
                submitting = false
                errorText = "提交失败，记录仍保留在页面上。请检查网络后重试。"
                #if DEBUG
                print("Incident report submit failed: \(error)")
                #endif
            }
        }
    }
}
