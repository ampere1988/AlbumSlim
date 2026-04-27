import SwiftUI
import SwiftData
import AVFoundation

@main
struct AlbumSlimApp: App {
    let services = AppServiceContainer()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        Self.configureAudioSession()
        services.backgroundTask.registerBackgroundTasks(services: services)
    }

    /// 配置音频会话为 .ambient + .mixWithOthers：
    /// - 浏览视频带声播放，但不抢占用户正在播放的音乐/播客
    /// - 来电、AirPods 切换等中断后系统自动恢复，不会让 AVPlayer 卡死
    private static func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .ambient,
                mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[AlbumSlim] AVAudioSession 配置失败: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding {
                MainTabView()
                    .environment(services)
                    .task { await services.prepareAsync() }
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .modelContainer(for: CachedAnalysis.self)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                services.backgroundTask.handleEnterBackground(services: services)
            case .active:
                services.backgroundTask.handleEnterForeground()
            default:
                break
            }
        }
    }
}
