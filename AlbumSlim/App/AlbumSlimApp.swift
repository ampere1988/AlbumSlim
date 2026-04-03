import SwiftUI
import SwiftData

@main
struct AlbumSlimApp: App {
    let services = AppServiceContainer()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(services)
        }
        .modelContainer(for: CachedAnalysis.self)
    }
}
