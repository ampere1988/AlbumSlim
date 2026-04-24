import Foundation
import CoreLocation

/// 反向地理解析：CLLocation → 城市/地点名，带内存缓存 + 串行化（CLGeocoder 有节流）
@MainActor
@Observable
final class LocationNameService {
    private var cache: [String: String] = [:]
    private let geocoder = CLGeocoder()
    private let semaphore = AsyncSemaphore(limit: 1)

    /// 返回合适显示的地点名（优先 locality，其次 subAdministrativeArea，最后 country）
    func placeName(for location: CLLocation?) async -> String? {
        guard let location else { return nil }
        let key = cacheKey(for: location.coordinate)
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }

        await semaphore.wait()
        defer { semaphore.signal() }

        // 等锁期间可能已有其它请求写入缓存
        if let cached = cache[key] { return cached.isEmpty ? nil : cached }

        let placemark: CLPlacemark?
        do {
            placemark = try await geocoder.reverseGeocodeLocation(location).first
        } catch {
            placemark = nil
        }

        let name = placemark?.locality
            ?? placemark?.subAdministrativeArea
            ?? placemark?.administrativeArea
            ?? placemark?.country
        cache[key] = name ?? ""
        return name
    }

    /// 把经纬度截到 3 位小数（约 110m 精度），同一片区不重复请求
    private func cacheKey(for coord: CLLocationCoordinate2D) -> String {
        let lat = (coord.latitude * 1000).rounded() / 1000
        let lng = (coord.longitude * 1000).rounded() / 1000
        return "\(lat),\(lng)"
    }
}
