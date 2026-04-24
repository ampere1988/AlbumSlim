import SwiftUI
import Photos

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var photoAuthStatus: PHAuthorizationStatus = PermissionManager.photoLibraryStatus

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
        .safeAreaInset(edge: .top) {
            if photoAuthStatus != .authorized && photoAuthStatus != .limited {
                permissionBanner
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .switchTab)) { notification in
            if let index = notification.userInfo?["index"] as? Int {
                selectedTab = index
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            photoAuthStatus = PermissionManager.photoLibraryStatus
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            // 离开截图 tab(tag 3)时通知 ScreenshotListView 重置导航栈,
            // 避免切回来时 detail 页 UIScrollView 残留放大状态
            if oldValue == 3, newValue != 3 {
                NotificationCenter.default.post(name: .screenshotTabLeft, object: nil)
            }
        }
    }

    private var permissionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("未授权相册访问")
                    .font(.footnote.bold())
                Text("开启权限后才能扫描和清理")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("去设置") {
                PermissionManager.openSettings()
            }
            .font(.footnote.bold())
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}

enum PhotoCleanerCategory: Int, CaseIterable, Identifiable {
    case similar, waste, burst, large

    var id: Int { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .similar: "相似照片"
        case .waste: "废片"
        case .burst: "连拍"
        case .large: "超大照片"
        }
    }

    var icon: String {
        switch self {
        case .similar: "rectangle.stack.fill"
        case .waste: "trash"
        case .burst: "square.stack.3d.up.fill"
        case .large: "photo.badge.plus"
        }
    }
}

struct PhotoCleanerTabView: View {
    @State private var selectedCategory: PhotoCleanerCategory = .similar

    var body: some View {
        NavigationStack {
            Group {
                switch selectedCategory {
                case .similar: SimilarPhotosView()
                case .waste: WastePhotosView()
                case .burst: BurstPhotosView()
                case .large: LargePhotosView()
                }
            }
            .navigationTitle(selectedCategory.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("清理类型", selection: $selectedCategory) {
                            ForEach(PhotoCleanerCategory.allCases) { category in
                                Label(category.title, systemImage: category.icon)
                                    .tag(category)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title3)
                    }
                }
            }
        }
    }
}
