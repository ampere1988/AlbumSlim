import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var showPermissionDenied = false
    @State private var showClearCacheConfirm = false
    @State private var showPaywall = false
    @State private var showRestartAlert = false
    @AppStorage("appLanguage") private var appLanguage = "system"

    private let privacyPolicyURL = URL(string: "https://chunbingtang.com/privacy.html")!
    private let termsURL = URL(string: "https://chunbingtang.com/terms.html")!
    private let supportEmail = "wakeupmozart@gmail.com"

    var body: some View {
        @Bindable var reminder = services.reminder
        NavigationStack {
            Form {
                subscriptionSection

                usageStatsSection

                reminderSection(reminder: reminder)

                generalSection

                aboutSection

                legalSection
            }
            .navigationTitle("设置")
            .alert("通知权限未开启", isPresented: $showPermissionDenied) {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请在系统设置中允许闪图发送通知，以便接收清理提醒")
            }
            .alert("确认清除缓存", isPresented: $showClearCacheConfirm) {
                Button("清除", role: .destructive) {
                    services.analysisCache.clearAllCache()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除所有分析缓存数据，下次扫描需要重新分析。此操作不会影响您的照片和视频。")
            }
            .alert("语言已更改", isPresented: $showRestartAlert) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("请从后台完全关闭闪图后重新打开，新的语言设置即可生效")
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - 订阅

    private var subscriptionSection: some View {
        Section("Pro") {
            if services.subscription.isPro {
                HStack {
                    Label("Pro 已激活", systemImage: "crown.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("解锁 Pro", systemImage: "crown")
                }
            }

            Button("恢复购买") {
                Task { await services.subscription.restorePurchases() }
            }
        }
    }

    // MARK: - 使用统计

    private var usageStatsSection: some View {
        Section("使用统计") {
            let achievement = services.achievement
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(icon: "trash.circle.fill", color: .red, value: "\(achievement.totalDeletedCount)", label: String(localized: "已删除项目"))
                StatCard(icon: "arrow.triangle.2.circlepath.circle.fill", color: .blue, value: "\(achievement.totalCleanupCount)", label: String(localized: "清理次数"))
                StatCard(icon: "internaldrive.fill", color: .green, value: achievement.totalFreedSpace.formattedFileSize, label: String(localized: "节省空间"))
                StatCard(icon: "magnifyingglass.circle.fill", color: .orange, value: "\(achievement.totalScanCount)", label: String(localized: "扫描分析"))
                StatCard(icon: "video.circle.fill", color: .purple, value: "\(achievement.totalCompressedCount)", label: String(localized: "视频压缩"))
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    // MARK: - 提醒

    private func reminderSection(reminder: ReminderService) -> some View {
        Section("清理提醒") {
            Toggle("定期提醒清理", isOn: Binding(
                get: { reminder.isReminderEnabled },
                set: { newValue in
                    if newValue {
                        Task {
                            let granted = await reminder.requestNotificationPermission()
                            if granted {
                                reminder.isReminderEnabled = true
                            } else {
                                showPermissionDenied = true
                            }
                        }
                    } else {
                        reminder.isReminderEnabled = false
                    }
                }
            ))

            if reminder.isReminderEnabled {
                Picker("提醒频率", selection: Binding(
                    get: { reminder.reminderInterval },
                    set: { reminder.reminderInterval = $0 }
                )) {
                    ForEach(ReminderService.ReminderInterval.allCases, id: \.self) { interval in
                        Text(interval.localizedName).tag(interval)
                    }
                }
            }
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        Section("通用") {
            Picker("语言", selection: $appLanguage) {
                Text("跟随系统").tag("system")
                Text("简体中文").tag("zh-Hans")
                Text("English").tag("en")
            }
            .onChange(of: appLanguage) { _, newValue in
                if newValue == "system" {
                    UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                } else {
                    UserDefaults.standard.set([newValue], forKey: "AppleLanguages")
                }
                showRestartAlert = true
            }

            Button(role: .destructive) {
                showClearCacheConfirm = true
            } label: {
                Label("清除分析缓存", systemImage: "trash")
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            HStack {
                Text("版本")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundStyle(.secondary)
            }

            Button {
                requestAppReview()
            } label: {
                Label("给闪图评分", systemImage: "star")
            }

            Button {
                sendFeedbackEmail()
            } label: {
                Label("意见反馈", systemImage: "envelope")
            }
        }
    }

    // MARK: - 法律信息

    private var legalSection: some View {
        Section("法律信息") {
            Link(destination: privacyPolicyURL) {
                Label("隐私政策", systemImage: "hand.raised")
            }

            Link(destination: termsURL) {
                Label("使用条款", systemImage: "doc.text")
            }
        }
    }

    // MARK: - Actions

    private func requestAppReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
    }

    // MARK: - StatCard

    private struct StatCard: View {
        let icon: String
        let color: Color
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(value)
                    .font(.title3.bold())
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }

    private func sendFeedbackEmail() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        let subject = String(localized: "闪图 v\(appVersion) 意见反馈")
        let body = "\n\n---\n\(String(localized: "设备")): \(deviceModel)\n\(String(localized: "系统")): iOS \(systemVersion)\n\(String(localized: "版本")): \(appVersion)"

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:\(supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}
