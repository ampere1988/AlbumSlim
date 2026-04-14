import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("概览", systemImage: "chart.pie.fill")
                }
                .tag(0)
            VideoListView()
                .tabItem {
                    Label("视频", systemImage: "video.fill")
                }
                .tag(1)
            PhotoCleanerTabView()
                .tabItem {
                    Label("照片", systemImage: "photo.on.rectangle.angled")
                }
                .tag(2)
            ScreenshotListView()
                .tabItem {
                    Label("截图", systemImage: "scissors")
                }
                .tag(3)
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { notification in
            if let index = notification.userInfo?["index"] as? Int {
                selectedTab = index
            }
        }
    }
}

struct PhotoCleanerTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("清理类型", selection: $selectedTab) {
                    Text("相似照片").tag(0)
                    Text("废片").tag(1)
                    Text("连拍").tag(2)
                    Text("超大照片").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                Group {
                    switch selectedTab {
                    case 0: SimilarPhotosView()
                    case 1: WastePhotosView()
                    case 2: BurstPhotosView()
                    case 3: LargePhotosView()
                    default: EmptyView()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("照片清理")
        }
    }
}
