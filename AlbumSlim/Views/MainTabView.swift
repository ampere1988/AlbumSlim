import SwiftUI
import Photos

struct MainTabView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var selectedTab = 0
    @State private var photoAuthStatus: PHAuthorizationStatus = PermissionManager.photoLibraryStatus

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                ShuffleFeedView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(0)
                VideoListView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(1)
                PhotoCleanerTabView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(2)
                ScreenshotListView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(3)
                SettingsView()
                    .toolbar(.hidden, for: .tabBar)
                    .tag(4)
            }

            ShuffleNavMenu(selectedTab: $selectedTab)
                .padding(.trailing, 16)
                .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top) {
            // 浏览 Tab 走沉浸式全屏，不显示权限横幅（由 ShuffleFeedView 自己做 overlay 引导）
            if selectedTab != 0,
               photoAuthStatus != .authorized && photoAuthStatus != .limited {
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
            // 离开浏览 tab(tag 0)时暂停视频/Live Photo 播放,并重置 backdrop 为 light
            if oldValue == 0, newValue != 0 {
                NotificationCenter.default.post(name: .shuffleTabLeft, object: nil)
                services.backdrop.reset()
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

extension Notification.Name {
    static let switchTab = Notification.Name("switchTab")
    /// 用户切离截图 tab 时发送,携带被离开的 tab index 没有意义 —— 仅做信号
    static let screenshotTabLeft = Notification.Name("screenshotTabLeft")
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
