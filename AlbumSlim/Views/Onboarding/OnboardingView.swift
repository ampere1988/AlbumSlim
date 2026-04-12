import SwiftUI
import Photos

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var authStatus: PHAuthorizationStatus = PermissionManager.photoLibraryStatus
    @State private var isRequesting = false
    @AppStorage("hasShownPrivacyNotice") private var hasShownPrivacyNotice = false
    @State private var showPrivacySheet = false

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
        .onAppear {
            if !hasShownPrivacyNotice {
                showPrivacySheet = true
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            PrivacyNoticeView {
                hasShownPrivacyNotice = true
                showPrivacySheet = false
            }
            .interactiveDismissDisabled()
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

struct PrivacyNoticeView: View {
    var onAccept: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundStyle(.green.gradient)

            VStack(spacing: 8) {
                Text("隐私保护承诺")
                    .font(.title.bold())
                Text("您的相册安全是我们的首要原则")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                privacyItem(
                    icon: "cpu",
                    title: "100% 本地处理",
                    detail: "所有 AI 分析均在您的设备上完成，照片和视频绝不会上传到任何服务器"
                )
                privacyItem(
                    icon: "icloud.slash",
                    title: "零网络传输",
                    detail: "App 不会将您的任何照片、视频或分析数据发送到外部"
                )
                privacyItem(
                    icon: "eye.slash",
                    title: "无隐私追踪",
                    detail: "我们不收集、不存储、不分享您的个人数据和使用习惯"
                )
                privacyItem(
                    icon: "lock.shield",
                    title: "数据留在手机",
                    detail: "分析缓存仅存储在本地，删除 App 即彻底清除所有数据"
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                onAccept()
            } label: {
                Text("我知道了")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)
        }
        .padding(24)
        .presentationDetents([.large])
    }

    private func privacyItem(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
