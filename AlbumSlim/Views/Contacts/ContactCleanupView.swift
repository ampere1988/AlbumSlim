import SwiftUI
import Contacts

struct ContactCleanupView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @State private var pendingMerge: ContactDuplicateGroup?
    @State private var showPaywall = false

    private var service: ContactCleanupService { services.contactCleanup }

    var body: some View {
        Group {
            switch service.authorizationStatus {
            case .authorized:
                contentView
            case .denied, .restricted:
                deniedView
            default:
                requestView
            }
        }
        .navigationTitle(String(localized: "重复联系人"))
        .navigationBarTitleDisplayMode(.inline)
        // 仅做纯读取的状态刷新，绝不在这里触发系统权限弹窗（那只能来自用户主动点击）
        .onAppear { service.refreshAuthorizationStatus() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                service.refreshAuthorizationStatus()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert(
            String(localized: "合并这些联系人？"),
            isPresented: Binding(
                get: { pendingMerge != nil },
                set: { if !$0 { pendingMerge = nil } }
            ),
            presenting: pendingMerge
        ) { group in
            Button(String(localized: "合并"), role: .destructive) {
                performMerge(group)
            }
            Button(AppStrings.cancel, role: .cancel) { pendingMerge = nil }
        } message: { group in
            Text(String(localized: "联系方式会合并到信息最全的那条，其余 \(group.removableCount) 条将被删除。此操作不可撤销。"))
        }
    }

    // MARK: - 未授权

    private var requestView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(String(localized: "查找重复联系人"))
                .font(.title3.bold())
            Text(String(localized: "闪图会在本地比对号码与姓名，找出重复条目。通讯录内容不会离开你的设备。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(String(localized: "允许访问通讯录")) {
                Task {
                    if await service.requestAccess() {
                        await service.scan()
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var deniedView: some View {
        ContentUnavailableView {
            Label(String(localized: "未授权通讯录"), systemImage: "lock")
        } description: {
            Text(String(localized: "请到系统设置里允许闪图访问通讯录"))
        } actions: {
            Button(String(localized: "去设置")) { PermissionManager.openSettings() }
        }
    }

    // MARK: - 已授权

    @ViewBuilder
    private var contentView: some View {
        if service.isScanning {
            ProgressView(AppStrings.scanning)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if service.groups.isEmpty {
            ContentUnavailableView {
                Label(String(localized: "没有重复联系人"), systemImage: "checkmark.seal")
            } description: {
                Text(String(localized: "已检查 \(service.totalContactCount) 位联系人"))
            }
            .task { if service.totalContactCount == 0 { await service.scan() } }
        } else {
            List {
                ForEach(service.groups) { group in
                    Section {
                        ForEach(group.contacts) { contact in
                            contactRow(contact, isPrimary: contact.id == group.primaryID)
                        }
                        let isMerging = service.mergingGroupIDs.contains(group.id)
                        Button {
                            requestMerge(group)
                        } label: {
                            if isMerging {
                                HStack {
                                    ProgressView()
                                    Text(String(localized: "合并中…"))
                                }
                            } else {
                                Label(
                                    String(localized: "合并为 1 条（删除 \(group.removableCount) 条）"),
                                    systemImage: "arrow.triangle.merge"
                                )
                            }
                        }
                        .disabled(isMerging)
                    } header: {
                        Text(group.reason.label)
                    }
                }
            }
        }
    }

    private func contactRow(_ contact: ContactSummary, isPrimary: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.fullName.isEmpty ? String(localized: "(无姓名)") : contact.fullName)
                    .font(.body)
                if !contact.subtitle.isEmpty {
                    Text(contact.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isPrimary {
                Text(String(localized: "保留"))
                    .font(.caption2.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: - 动作

    private func requestMerge(_ group: ContactDuplicateGroup) {
        // 已在合并中的分组不再重复弹出确认（防止双击/重复确认触发并发合并）
        guard !service.mergingGroupIDs.contains(group.id) else { return }
        // 合并是清理操作，门控口径与其它模块一致
        guard ProFeatureGate.canClean(isPro: services.subscription.isPro) else {
            showPaywall = true
            return
        }
        pendingMerge = group
    }

    private func performMerge(_ group: ContactDuplicateGroup) {
        pendingMerge = nil
        Task {
            do {
                try await service.merge(group: group)
                services.toast.show(
                    icon: AppIcons.checkmarkCircleFill,
                    text: String(localized: "已合并 \(group.contacts.count) 条联系人"),
                    tint: .green
                )
            } catch {
                services.toast.failure(error.localizedDescription)
            }
        }
    }
}
