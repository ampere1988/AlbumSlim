import SwiftUI

struct SettingsView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var showPermissionDenied = false

    var body: some View {
        @Bindable var reminder = services.reminder
        NavigationStack {
            Form {
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

                Section("关于") {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
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
        }
    }
}
