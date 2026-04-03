import SwiftUI
import SwiftData

@main
struct AlbumSlimApp: App {
    let services = AppServiceContainer()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasCompletedOnboarding && PermissionManager.isAuthorized {
                MainTabView()
                    .environment(services)
            } else {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
            }
        }
        .modelContainer(for: CachedAnalysis.self)
    }
}
