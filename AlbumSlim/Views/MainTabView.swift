import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("概览", systemImage: "chart.pie.fill")
                }
            VideoListView()
                .tabItem {
                    Label("视频", systemImage: "video.fill")
                }
            PhotoCleanerTabView()
                .tabItem {
                    Label("照片", systemImage: "photo.on.rectangle.angled")
                }
            ScreenshotListView()
                .tabItem {
                    Label("截图", systemImage: "scissors")
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
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case 0: SimilarPhotosView()
                case 1: WastePhotosView()
                case 2: BurstPhotosView()
                default: EmptyView()
                }
            }
            .navigationTitle("照片清理")
        }
    }
}
