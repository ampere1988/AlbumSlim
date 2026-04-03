import SwiftUI
import Photos

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var authStatus: PHAuthorizationStatus = PermissionManager.photoLibraryStatus
    @State private var isRequesting = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "photo.stack")
                .font(.system(size: 72))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text("相册瘦身")
                    .font(.largeTitle.bold())
                Text("智能分析相册，释放存储空间")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "lock.shield", text: "所有分析在本地完成，隐私安全")
                featureRow(icon: "video.fill", text: "智能压缩视频，画质几乎无损")
                featureRow(icon: "photo.on.rectangle.angled", text: "自动发现相似照片和废片")
                featureRow(icon: "scissors", text: "批量管理截图，一键清理")
            }
            .padding(.horizontal, 32)

            Spacer()

            switch authStatus {
            case .denied, .restricted:
                VStack(spacing: 12) {
                    Text("需要相册访问权限才能使用")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("前往系统设置") {
                        PermissionManager.openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            default:
                Button {
                    Task {
                        isRequesting = true
                        let status = await PermissionManager.requestPhotoLibrary()
                        authStatus = status
                        isRequesting = false
                        if status == .authorized || status == .limited {
                            hasCompletedOnboarding = true
                        }
                    }
                } label: {
                    if isRequesting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("授权访问相册")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)
            }
        }
        .padding(24)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            authStatus = PermissionManager.photoLibraryStatus
            if PermissionManager.isAuthorized {
                hasCompletedOnboarding = true
            }
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
            Text(text)
                .font(.body)
        }
    }
}
