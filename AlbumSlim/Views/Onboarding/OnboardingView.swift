import SwiftUI
import Photos

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @AppStorage("hasAgreedToPrivacy") private var hasAgreedToPrivacy = false
    @State private var authStatus: PHAuthorizationStatus = PermissionManager.photoLibraryStatus
    @State private var isRequesting = false

    var body: some View {
        if !hasAgreedToPrivacy {
            PrivacyAgreementView(hasAgreedToPrivacy: $hasAgreedToPrivacy)
        } else {
            permissionView
        }
    }

    private var permissionView: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            GlowIcon(systemImage: "photo.stack", size: 104)

            VStack(spacing: Spacing.m) {
                Text("闪图")
                    .font(AppFont.display)
                    .foregroundStyle(Theme.accentGradient)
                Text("智能分析相册，释放存储空间")
                    .font(AppFont.meta)
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: Spacing.l) {
                featureRow(icon: "lock.shield", tint: Theme.success, text: "所有分析在本地完成，隐私安全")
                featureRow(icon: "video.fill", tint: Theme.video, text: "智能压缩视频，画质几乎无损")
                featureRow(icon: "photo.on.rectangle.angled", tint: Theme.photo, text: "自动发现相似照片和废片")
                featureRow(icon: "scissors", tint: Theme.screenshot, text: "批量管理截图，一键清理")
            }
            .padding(Spacing.l)
            .glassSurface()

            Spacer()

            switch authStatus {
            case .denied, .restricted:
                VStack(spacing: Spacing.m) {
                    Text("未授权相册访问")
                        .font(AppFont.meta)
                        .foregroundStyle(Theme.textSecondary)
                    Button("前往系统设置", action: PermissionManager.openSettings)
                        .primaryActionStyle()
                    Button("稍后再说") {
                        hasCompletedOnboarding = true
                    }
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minHeight: 44)
                }
            default:
                Button {
                    Task {
                        isRequesting = true
                        let status = await PermissionManager.requestPhotoLibrary()
                        authStatus = status
                        isRequesting = false
                        hasCompletedOnboarding = (status != .notDetermined)
                    }
                } label: {
                    if isRequesting {
                        ProgressView().tint(Theme.textOnAccent)
                    } else {
                        Text("授权访问相册")
                    }
                }
                .primaryActionStyle()
                .disabled(isRequesting)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Theme.background
                .overlay(alignment: .top) {
                    Theme.ambientGlow.frame(height: 460).allowsHitTesting(false)
                }
                .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            authStatus = PermissionManager.photoLibraryStatus
            if PermissionManager.isAuthorized {
                hasCompletedOnboarding = true
            }
        }
    }

    private func featureRow(icon: String, tint: Color, text: LocalizedStringKey) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(Circle().fill(tint.opacity(0.16)))
            Text(text)
                .font(AppFont.body)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

struct PrivacyAgreementView: View {
    @Binding var hasAgreedToPrivacy: Bool
    @Environment(\.openURL) private var openURL

    private let privacyPolicyURL = URL(string: "https://chunbingtang.com/privacy.html")!
    private let termsOfServiceURL = URL(string: "https://chunbingtang.com/terms.html")!

    var body: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            GlowIcon(systemImage: "shield.checkered", tint: Theme.success, size: 96)

            VStack(spacing: Spacing.s) {
                Text("隐私保护承诺")
                    .font(AppFont.screenTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("您的相册安全是我们的首要原则")
                    .font(AppFont.meta)
                    .foregroundStyle(Theme.textSecondary)
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
            .padding(Spacing.l)
            .glassSurface()

            Spacer()

            VStack(spacing: Spacing.m) {
                Button("同意并继续") {
                    hasAgreedToPrivacy = true
                }
                .primaryActionStyle()

                HStack(spacing: Spacing.l) {
                    Button("隐私政策") { openURL(privacyPolicyURL) }
                    Text("·").foregroundStyle(Theme.textTertiary)
                    Button("使用条款") { openURL(termsOfServiceURL) }
                }
                .font(AppFont.meta)
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Theme.background
                .overlay(alignment: .top) {
                    Theme.ambientGlow.frame(height: 460).allowsHitTesting(false)
                }
                .ignoresSafeArea()
        }
    }

    private func privacyItem(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.success)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.success.opacity(0.16)))
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(title)
                    .font(AppFont.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(AppFont.label)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
