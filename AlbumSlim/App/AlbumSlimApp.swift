import SwiftUI
import SwiftData

@main
struct AlbumSlimApp: App {
    let services = AppServiceContainer()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        services.backgroundTask.registerBackgroundTasks(services: services)
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding && PermissionManager.isAuthorized {
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
