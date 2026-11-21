import Foundation
import Observation
import Supabase
import UIKit

/// 车库数据：车辆列表 + 车型库目录 + 车辆照片
@MainActor
@Observable
final class GarageService {
    private(set) var vehicles: [Vehicle] = []
    /// 最近一次成功加进车库的车辆 id。首页轮播靠它跳到「刚加的那辆」——
    /// 列表是按 `is_default desc, created_at desc` 排的，刚加的排在非默认里的第一个，
    /// 用「最后一个下标」去猜会跳到最老那辆。
    private(set) var lastAddedVehicleId: UUID?
    /// 首页轮播已经跳过去了，清掉标记(否则之后任何一次列表刷新又会把她拉回去)
    func clearLastAddedFlag() { lastAddedVehicleId = nil }

    /// 添加流程收尾时再记一次：列表刷新会触发首页跳到新车，
    /// 但此时列表还在全屏覆盖层下方，跳转可能被 TabView 的重新布局覆盖。
    /// 关闭覆盖层后再用这个标记补跳一次。
    func markJustAdded(_ id: UUID) { lastAddedVehicleId = id }
    private(set) var brands: [Brand] = []
    private(set) var modelsByBrand: [Int: [VehicleModel]] = [:]
    private(set) var isLoading = false
    /// 品牌/车型目录加载中(选择器据此显示加载态，避免误显示「没有品牌」)
    private(set) var isCatalogLoading = false
    private(set) var photos: [UUID: UIImage] = [:]
    var errorMessage: String?
    /// 车辆列表刷新失败、但手上还有上一次的数据：页面继续显示旧列表，
    /// 由调用方给一次轻提示，避免「下拉刷新后什么都没变也没说为什么」。
    private(set) var vehicleRefreshFailed = false

    private let client: SupabaseClient

    /// 车型库目录单页条数。PostgREST 单次最多返回 1000 行，目录已经上千条，必须翻页取全
    private static let catalogPageSize = 500

    init(client: SupabaseClient) {
        self.client = client
    }

    /// 加载目录(品牌 + 全部车型),整个车库流程共用。
    /// 目录变化很少：先读本地缓存秒开，超过 24 小时再静默刷新；
    /// 下拉刷新传 force: true 跳过缓存，后台改了车型图也能立刻看到。
    func loadCatalog(force: Bool = false) async {
        isCatalogLoading = true
        defer { isCatalogLoading = false }

        let cached = Self.readCatalogCache()
        if let cached {
            if brands.isEmpty {
                applyCatalog(brands: cached.brands, models: cached.models)
            }
            if !force, Date().timeIntervalSince(cached.savedAt) < 24 * 60 * 60 {
                return
            }
        }

        do {
            let loadedBrands: [Brand] = try await client
                .from("brands")
                .select("id, name, name_en, is_hot, sort")
                .order("sort")
                .execute()
                .value

            var loadedModels: [VehicleModel] = []
            var offset = 0
            while true {
                // id 作为最后的排序键，保证翻页顺序稳定(否则相邻页可能重复或漏数据)
                let page: [VehicleModel] = try await client
                    .from("models")
                    .select("id, brand_id, name, series, model_type, displacement_cc, price_min, price_max, rating, is_new, sort, image_url")
                    .order("brand_id")
                    .order("sort")
                    .order("id")
                    .range(from: offset, to: offset + Self.catalogPageSize - 1)
                    .execute()
                    .value
                loadedModels.append(contentsOf: page)
                if page.count < Self.catalogPageSize { break }
                offset += Self.catalogPageSize
            }

            applyCatalog(brands: loadedBrands, models: loadedModels)
            Self.writeCatalogCache(brands: loadedBrands, models: loadedModels)
            errorMessage = nil
        } catch {
            // 有缓存时静默降级，不把目录刷新失败误报成「车辆加载失败」
            if brands.isEmpty {
                errorMessage = error.wellwayUserMessage
            }
        }
    }

    private func applyCatalog(brands loadedBrands: [Brand], models loadedModels: [VehicleModel]) {
        brands = loadedBrands
        var grouped: [Int: [VehicleModel]] = [:]
        for model in loadedModels {
            grouped[model.brandId, default: []].append(model)
        }
        modelsByBrand = grouped
    }

    // MARK: - 目录缓存

    private struct CatalogCache: Codable {
        let brands: [Brand]
        let models: [VehicleModel]
        let savedAt: Date
    }

    private static var catalogCacheURL: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wellway", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("catalog-cache.json")
    }

    private static func readCatalogCache() -> CatalogCache? {
        guard let data = try? Data(contentsOf: catalogCacheURL) else { return nil }
        return try? JSONDecoder().decode(CatalogCache.self, from: data)
    }

    private static func writeCatalogCache(brands: [Brand], models: [VehicleModel]) {
        let cache = CatalogCache(brands: brands, models: models, savedAt: Date())
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: catalogCacheURL, options: .atomic)
    }

    /// 调试入口(-garagesample)：注入一辆有目录、有车照的车，供无账号时复检
    /// 车库正常态。和真实加载共用同一套展示路径，不改生产网络逻辑。
    @discardableResult
    func applyDebugSample() -> (userId: UUID, vehicleId: UUID, secondVehicleId: UUID) {
        let userId = UUID(uuidString: "00000000-0000-0000-0000-000000010700")!
        let primaryId = UUID(uuidString: "00000000-0000-0000-0000-000000010701")!
        let secondaryId = UUID(uuidString: "00000000-0000-0000-0000-000000010702")!

        let cfmoto = Brand(id: 1, name: "春风", nameEn: "CFMOTO", isHot: true, sort: 1)
        let honda = Brand(id: 2, name: "本田", nameEn: "HONDA", isHot: true, sort: 2)
        let nk450 = VehicleModel(
            id: 101, brandId: 1, name: "春风 450NK", series: "NK", modelType: "街车",
            displacementCc: 450, priceMin: 23_980, priceMax: 26_580,
            rating: 4.8, isNew: false, sort: 1, imageUrl: nil
        )
        let cb400f = VehicleModel(
            id: 201, brandId: 2, name: "本田 CB400F", series: "CB", modelType: "街车",
            displacementCc: 399, priceMin: 33_000, priceMax: 37_000,
            rating: 4.6, isNew: false, sort: 1, imageUrl: nil
        )

        brands = [cfmoto, honda]
        modelsByBrand = [1: [nk450], 2: [cb400f]]
        vehicles = [
            Vehicle(id: primaryId, userId: userId, brandId: 1, modelId: 101,
                    nickname: nil, color: "星光白", photoUrl: nil, isDefault: true),
            Vehicle(id: secondaryId, userId: userId, brandId: 2, modelId: 201,
                    nickname: nil, color: "曜石黑", photoUrl: nil, isDefault: false)
        ]
        photos = [:]
        // 内置产品照没有网络依赖，截图和真机离线复检都能稳定出图。
        if let image = UIImage(named: "ConceptBike") {
            photos[primaryId] = image
        }
        errorMessage = nil
        isLoading = false
        return (userId, primaryId, secondaryId)
    }

    func loadVehicles(userId: UUID) async {
        // 调试入口：-garageempty 时不请求车辆，用于复检「还没有车辆」首屏
        if ProcessInfo.processInfo.arguments.contains("-garageempty") {
            vehicles = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded: [Vehicle] = try await client
                .from("vehicles")
                .select("id, user_id, brand_id, model_id, nickname, color, photo_url, is_default")
                .eq("user_id", value: userId)
                .order("is_default", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
            vehicles = loaded
            errorMessage = nil
            vehicleRefreshFailed = false
            await loadPhotos(for: loaded)
            await ensureDefaultVehicle(userId: userId, loaded: loaded)
        } catch {
            errorMessage = error.wellwayUserMessage
            vehicleRefreshFailed = !vehicles.isEmpty
        }
    }

    /// 兜底默认车辆：添加流程从来不写 `is_default`（只有「设为默认」会写），
    /// 所以老账号加到第二辆时会出现「一辆默认车都没有」——
    /// 「车辆」页的默认徽标直接消失，出发页只能按创建时间猜一辆。
    /// 只在完全没有默认车时补一次，选排序最前的一辆（列表按创建时间倒序，
    /// 也就是刚添加的那辆），和首页轮播跳新车的表现保持一致。
    private func ensureDefaultVehicle(userId: UUID, loaded: [Vehicle]) async {
        guard !loaded.contains(where: \.isDefault), let target = loaded.first else { return }
        do {
            try await client.from("vehicles")
                .update(["is_default": true])
                .eq("id", value: target.id)
                .eq("user_id", value: userId)
                .execute()
            vehicles = loaded.map {
                Vehicle(id: $0.id, userId: $0.userId, brandId: $0.brandId, modelId: $0.modelId,
                        nickname: $0.nickname, color: $0.color, photoUrl: $0.photoUrl,
                        isDefault: $0.id == target.id)
            }
        } catch {
            // 补默认失败不影响车辆列表展示，下次加载会再试
        }
    }

    @discardableResult
    func addVehicle(_ vehicle: VehicleInsert) async -> Vehicle? {
        do {
            let created: Vehicle = try await client.from("vehicles")
                .insert(vehicle)
                .select("id, user_id, brand_id, model_id, nickname, color, photo_url, is_default")
                .single()
                .execute()
                .value
            errorMessage = nil
            lastAddedVehicleId = created.id
            return created
        } catch let error as PostgrestError {
            // 把服务端 code/detail 一并带出，便于定位(如 RLS、外键、类型等)
            let detail = error.detail.map { ": \($0)" } ?? ""
            errorMessage = "\(error.message)\(detail)(\(error.code ?? "unknown"))"
            return nil
        } catch {
            errorMessage = error.wellwayUserMessage
            return nil
        }
    }

    func updateVehicle(id: UUID, nickname: String?, color: String?, photoUrl: String?, isDefault: Bool) async {
        let previousPhotoUrl = vehicles.first { $0.id == id }?.photoUrl
        var photoUpdateApplied = false
        do {
            try await client.from("vehicles")
                .update([
                    "nickname": nickname ?? "",
                    "color": color ?? "",
                    "photo_url": photoUrl ?? "",
                ])
                .eq("id", value: id)
                .execute()
            photoUpdateApplied = true
            try await client.from("vehicles")
                .update(["is_default": isDefault])
                .eq("id", value: id)
                .execute()
            errorMessage = nil
            if previousPhotoUrl != photoUrl {
                await removeStoredPhoto(previousPhotoUrl)
            }
        } catch {
            // 资料写入成功后旧照片已失去引用；写入前失败则新上传对象仍未被引用。
            // 两种情况都清掉不再使用的那个，避免反复换图把 Storage 撑大。
            if photoUpdateApplied {
                if previousPhotoUrl != photoUrl { await removeStoredPhoto(previousPhotoUrl) }
            } else if previousPhotoUrl != photoUrl {
                await removeStoredPhoto(photoUrl)
            }
            errorMessage = error.wellwayUserMessage
        }
    }

    @discardableResult
    func deleteVehicle(id: UUID) async -> Bool {
        let photoUrl = vehicles.first { $0.id == id }?.photoUrl
        do {
            try await client.from("vehicles").delete().eq("id", value: id).execute()
            vehicles.removeAll { $0.id == id }
            photos.removeValue(forKey: id)
            await removeStoredPhoto(photoUrl)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.wellwayUserMessage
            return false
        }
    }

    /// 车辆资料或车辆本身删除后，清掉 Storage 中不再被引用的照片。
    private func removeStoredPhoto(_ path: String?) async {
        guard let path, !path.isEmpty else { return }
        try? await client.storage.from("vehicle-photos").remove(paths: [path])
    }

    /// 提交「添加品牌」请求(写入 feedback 表，管理后台可见；车型库由官方维护)
    @discardableResult
    func submitBrandRequest(name: String) async -> Bool {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        do {
            try await client
                .from("feedback")
                .insert(FeedbackInsert(content: "品牌添加请求：\(name)", contact: nil, appVersion: version))
                .execute()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.wellwayUserMessage
            return false
        }
    }

    @discardableResult
    func setDefault(id: UUID, userId: UUID) async -> Bool {
        do {
            // 先点亮目标车，再清理其它车：即使中途失败，也不会出现“一辆默认车都没有”。
            try await client.from("vehicles")
                .update(["is_default": true])
                .eq("id", value: id)
                .eq("user_id", value: userId)
                .execute()
            try await client.from("vehicles")
                .update(["is_default": false])
                .neq("id", value: id)
                .eq("user_id", value: userId)
                .execute()
            await loadVehicles(userId: userId)
            guard errorMessage == nil else { return false }
            let defaults = vehicles.filter(\.isDefault)
            guard defaults.count == 1, defaults.first?.id == id else {
                errorMessage = "默认车辆设置未生效，请重试"
                return false
            }
            return true
        } catch {
            errorMessage = error.wellwayUserMessage
            return false
        }
    }

    // MARK: - 照片

    /// 上传车辆照片到 vehicle-photos/<uid>/<filename>,返回存储路径
    func uploadPhoto(_ imageData: Data, userId: UUID) async -> String? {
        // Storage RLS 用 auth.uid()::text(小写) 比对目录名，UUID.uuidString 是大写，必须转小写
        let path = "\(userId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        do {
            try await client.storage.from("vehicle-photos").upload(path, data: imageData, options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            #if DEBUG
            print("[vehicle-photo] upload failed: \(error)")
            #endif
            errorMessage = "照片上传失败，请检查网络后重试"
            return nil
        }
    }

    /// 更换照片后清掉本地缓存，否则 loadVehicles 会复用旧图
    func clearPhotoCache(for id: UUID) {
        photos.removeValue(forKey: id)
    }

    private func loadPhotos(for list: [Vehicle]) async {
        for vehicle in list where vehicle.photoUrl != nil && photos[vehicle.id] == nil {
            do {
                let data = try await client.storage.from("vehicle-photos").download(path: vehicle.photoUrl!)
                if let image = UIImage(data: data) {
                    photos[vehicle.id] = image
                }
            } catch {
                // 私有照片偶尔下载失败，忽略
            }
        }
    }

    func brandName(for id: Int) -> String {
        brands.first { $0.id == id }?.name ?? "未知品牌"
    }

    /// 品牌展示名：优先中文（与车型库同名），无中文时回退英文
    func displayBrandName(for id: Int) -> String {
        guard let brand = brands.first(where: { $0.id == id }) else { return "未知品牌" }
        if brand.name.range(of: "\\p{Han}", options: .regularExpression) != nil {
            return brand.name
        }
        return brand.nameEn ?? brand.name
    }

    /// 每辆车的骑行统计(该车已完成记录聚合：总里程 / 次数 / 时长)
    /// 车库首页与「出发 → 更换车辆」共用同一口径。
    /// 返回 nil 表示本次请求失败；空字典表示成功且确实没有已完成骑行。
    func loadRideStats(userId: UUID) async -> [UUID: RideStats]? {
        struct Row: Decodable {
            let vehicleId: UUID?
            let distanceM: Int
            let durationS: Int

            enum CodingKeys: String, CodingKey {
                case vehicleId = "vehicle_id"
                case distanceM = "distance_m"
                case durationS = "duration_s"
            }
        }
        do {
            let rows: [Row] = try await client
                .from("ride_records")
                .select("vehicle_id, distance_m, duration_s")
                .eq("user_id", value: userId)
                .eq("status", value: "completed")
                .execute()
                .value
            var grouped: [UUID: (km: Double, count: Int, seconds: Int)] = [:]
            for row in rows {
                guard let vid = row.vehicleId else { continue }
                var acc = grouped[vid] ?? (0, 0, 0)
                acc.km += Double(row.distanceM) / 1000
                acc.count += 1
                acc.seconds += max(0, row.durationS)
                grouped[vid] = acc
            }
            return grouped.mapValues {
                RideStats(totalKm: $0.km, rideCount: $0.count, totalSeconds: $0.seconds)
            }
        } catch {
            return nil
        }
    }

    func modelName(for id: Int) -> String {
        modelsByBrand.values
            .flatMap { $0 }
            .first { $0.id == id }?
            .cleanedName ?? "未知车型"
    }

    /// 车辆对应的车型库条目(取车图/排量/分类插画都走这里)
    func model(for id: Int) -> VehicleModel? {
        modelsByBrand.values
            .flatMap { $0 }
            .first { $0.id == id }
    }

    func modelDisplay(for id: Int) -> String {
        guard let model = modelsByBrand.values.flatMap({ $0 }).first(where: { $0.id == id }) else {
            return "未知车型"
        }
        var text = model.cleanedName
        if let cc = model.displacementCc {
            text += " · \(cc)cc"
        }
        if let priceMin = model.priceMin {
            text += " · ¥\(priceMin.formatted())"
        }
        return text
    }
}
