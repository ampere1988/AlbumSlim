import SwiftUI
import StoreKit

struct SettingsView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var showPermissionDenied = false
    @State private var showClearCacheConfirm = false
    @State private var showPaywall = false

    private let privacyPolicyURL = URL(string: "https://chunbingtang.com/privacy.html")!
    private let termsURL = URL(string: "https://chunbingtang.com/terms.html")!
    private let supportEmail = "wakeupmozart@gmail.com"

    var body: some View {
        @Bindable var reminder = services.reminder
        NavigationStack {
            Form {
                subscriptionSection

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
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - 订阅

    private var subscriptionSection: some View {
        Section("Pro 订阅") {
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
                    Label("升级到 Pro", systemImage: "crown")
                }
            }

            Button("恢复购买") {
                Task { await services.subscription.restorePurchases() }
            }

            Button("管理订阅") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }
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
                        Text(interval.rawValue).tag(interval)
                    }
                }
            }
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        Section("通用") {
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

    private func sendFeedbackEmail() {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let systemVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        let subject = "闪图 v\(appVersion) 意见反馈"
        let body = "\n\n---\n设备: \(deviceModel)\n系统: iOS \(systemVersion)\n版本: \(appVersion)"

        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        if let url = URL(string: "mailto:\(supportEmail)?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }
}
