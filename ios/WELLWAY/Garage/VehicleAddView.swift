import SwiftUI
import PhotosUI

/// 添加/编辑车辆(Figma「添加车辆」「车辆确认-编辑」):品牌 → 车型 → 照片/昵称/颜色/默认
struct VehicleAddView: View {
    @Environment(AuthManager.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let garage: GarageService
    var existing: Vehicle?
    var onDelete: (() -> Void)?

    @State private var brandId: Int?
    @State private var modelId: Int?
    @State private var nickname = ""
    @State private var color = ""
    @State private var isDefault = false
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var confirmDelete = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoUrl: String?

    private var isEditing: Bool { existing != nil }

    var body: some View {
        VStack(spacing: 0) {
            DesignPageHeader(title: isEditing ? "车辆确认" : "添加车辆")
                .background(Color.white)
            Form {
                if !isEditing {
                    Section("选择品牌及车辆") {
                        VehicleSelectField(garage: garage, modelId: $modelId)
                            .motionAppear(delay: 0.05)
                    }
                } else if let existing {
                    Section("车辆") {
                        LabeledContent("车型", value: garage.modelDisplay(for: existing.modelId))
                    }
                }

                Section("车辆照片") {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        HStack(spacing: 12) {
                            if let photoData, let image = UIImage(data: photoData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            } else {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 64, height: 64)
                                    .background(Theme.primary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            Text("上传车辆照片")
                                .foregroundStyle(Theme.primary)
                            Spacer()
                        }
                    }
                }

                Section("车辆信息") {
                    TextField("昵称（如：小红）", text: $nickname)
                    TextField("颜色（选填）", text: $color)
                    Toggle("设为默认车辆", isOn: $isDefault)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Theme.danger)
                    }
                }

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(isEditing ? "保存修改" : "添加到车库").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isSaving || (modelId == nil && !isEditing))
                }

                if isEditing, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("删除车辆").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .ignoresSafeArea()
            .onChange(of: brandId) { _, _ in
                modelId = nil
            }
            .onChange(of: selectedPhoto) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
            .task {
                if let existing {
                    brandId = existing.brandId
                    modelId = existing.modelId
                    nickname = existing.nickname ?? ""
                    color = existing.color ?? ""
                    isDefault = existing.isDefault
                    photoUrl = existing.photoUrl
                }
            }
            .wellwayDialog(
                isPresented: $confirmDelete,
                title: "删除这辆车？",
                message: "将从车库移除这辆车，骑行记录会保留。",
                buttons: [
                    WellwayDialogButton(title: "删除车辆", role: .destructive) {
                        onDelete?()
                        dismiss()
                    }
                ]
            )
            .pageMark(isEditing ? 56 : 24)
        }
    }

    private func save() async {
        guard let userId = auth.user?.id else { return }
        isSaving = true
        errorText = nil

        // 新照片先上传
        var finalPhotoUrl = photoUrl
        if let photoData {
            let path = await garage.uploadPhoto(photoData, userId: userId)
            if path != nil {
                finalPhotoUrl = path
            } else if garage.errorMessage != nil {
                errorText = garage.errorMessage
                isSaving = false
                return
            }
        }

        if let existing {
            await garage.updateVehicle(
                id: existing.id,
                nickname: nickname.trimmingCharacters(in: .whitespaces).isEmpty ? nil : nickname,
                color: color.trimmingCharacters(in: .whitespaces).isEmpty ? nil : color,
                photoUrl: finalPhotoUrl,
                isDefault: isDefault
            )
        } else {
            guard let modelId,
                  let model = garage.modelsByBrand.values.flatMap({ $0 }).first(where: { $0.id == modelId }) else {
                errorText = "请先选择品牌及车辆"
                isSaving = false
                return
            }
            let vehicle = VehicleInsert(
                userId: userId,
                brandId: model.brandId,
                modelId: modelId,
                nickname: nickname.trimmingCharacters(in: .whitespaces).isEmpty ? nil : nickname,
                color: color.trimmingCharacters(in: .whitespaces).isEmpty ? nil : color,
                photoUrl: finalPhotoUrl
            )
            if let created = await garage.addVehicle(vehicle) {
                if isDefault {
                    await garage.setDefault(id: created.id, userId: userId)
                }
            }
        }
        isSaving = false

        if garage.errorMessage != nil {
            errorText = garage.errorMessage
        } else {
            if let uid = auth.user?.id {
                await garage.loadVehicles(userId: uid)
            }
            dismiss()
        }
    }
}
