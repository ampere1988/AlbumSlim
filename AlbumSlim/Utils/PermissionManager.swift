import Foundation
import Photos

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
}
