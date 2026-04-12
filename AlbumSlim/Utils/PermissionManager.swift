import Foundation
import Photos
import UIKit

enum PermissionManager {
    static var photoLibraryStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    static var isAuthorized: Bool {
        let status = photoLibraryStatus
        return status == .authorized || status == .limited
    }

    static func requestPhotoLibrary() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static var statusDescription: String {
        switch photoLibraryStatus {
        case .notDetermined: return "未请求权限"
        case .restricted: return "访问受限"
        case .denied: return "已拒绝访问"
        case .authorized: return "已授权完整访问"
        case .limited: return "已授权部分访问"
        @unknown default: return "未知状态"
        }
    }
}
