import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var restoreResultMessage: String?

    private var subscription: SubscriptionService { services.subscription }

    private static let features: [(icon: String, tint: Color, text: LocalizedStringKey)] = [
        ("trash.circle.fill", Theme.danger, "无限废片清理"),
        ("square.on.square", Theme.photo, "相似照片去重"),
        ("video.fill", Theme.video, "视频压缩与批量管理"),
        ("text.viewfinder", Theme.screenshot, "截图 OCR 文字识别"),
        ("square.stack.3d.up.fill", Theme.burst, "连拍 / 大照片清理"),
        ("wand.and.stars", Theme.accentSecondary, "智能一键扫描清理"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    headerSection
                    featureList
                    purchaseSection
                    footerSection
                }
                .padding(Spacing.l)
            }
            .background {
                // 顶部一团环境光，把付费页从普通设置页里"抬"出来
                Theme.background
                    .overlay(alignment: .top) {
                        Theme.ambientGlow
                            .frame(height: 420)
                            .allowsHitTesting(false)
                    }
                    .ignoresSafeArea()
            }
            .navigationTitle("解锁 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .accessibilityLabel("关闭")
                }
            }
            .task { await subscription.loadProduct() }
            .alert("购买出错", isPresented: .init(
                get: { subscription.purchaseError != nil },
                set: { if !$0 { subscription.purchaseError = nil } }
            )) {
                Button("确定") {}
            } message: {
                Text(subscription.purchaseError ?? "")
            }
            .alert("恢复购买", isPresented: .init(
                get: { restoreResultMessage != nil },
                set: { if !$0 { restoreResultMessage = nil } }
            )) {
                Button("确定") {}
            } message: {
                Text(restoreResultMessage ?? "")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Spacing.m) {
            GlowIcon(systemImage: "crown.fill", tint: Theme.warning, size: 88)
            Text("解锁全部功能")
                .font(AppFont.display)
                .foregroundStyle(Theme.accentGradient)
            Text("一次购买，终身使用")
                .font(AppFont.meta)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Spacing.s)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            ForEach(Self.features, id: \.icon) { feature in
                HStack(spacing: Spacing.m) {
                    Image(systemName: feature.icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(feature.tint)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(feature.tint.opacity(0.16)))
                    Text(feature.text)
                        .font(AppFont.body)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.success)
                }
            }
        }
        .padding(Spacing.l)
        .glassSurface()
    }

    // MARK: - Purchase

    @ViewBuilder
    private var purchaseSection: some View {
        if subscription.isLoading && subscription.product == nil {
            ProgressView()
                .tint(Theme.accent)
                .padding(Spacing.l)
        } else if let product = subscription.product {
            Button {
                purchase(product)
            } label: {
                if subscription.isLoading {
                    ProgressView().tint(Theme.textOnAccent)
                } else {
                    Text("\(product.displayPrice) 解锁 Pro")
                }
            }
            .primaryActionStyle()
            .disabled(subscription.isLoading)
        } else {
            VStack(spacing: Spacing.m) {
                Text("无法加载产品信息")
                    .font(AppFont.meta)
                    .foregroundStyle(Theme.textSecondary)
                Button("重试", action: reloadProduct)
                    .secondaryActionStyle()
                    .frame(maxWidth: 200)
            }
            .padding(Spacing.l)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: Spacing.m) {
            Button("恢复购买", action: restore)
                .font(AppFont.label.bold())
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)

            Text("一次性付费，不自动续费。购买后在当前 Apple ID 下长期解锁所有 Pro 功能。")
                .font(AppFont.label)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: Spacing.l) {
                Link("隐私政策", destination: URL(string: "https://chunbingtang.com/privacy.html")!)
                Text("·").foregroundStyle(Theme.textTertiary)
                Link("使用条款", destination: URL(string: "https://chunbingtang.com/terms.html")!)
            }
            .font(AppFont.label)
            .foregroundStyle(Theme.textSecondary)
            .frame(minHeight: 44)
        }
    }

    // MARK: - Actions

    private func purchase(_ product: Product) {
        Task {
            try? await subscription.purchase(product)
            if subscription.isPro { dismiss() }
        }
    }

    private func reloadProduct() {
        Task { await subscription.loadProduct() }
    }

    private func restore() {
        Task {
            let restored = await subscription.restorePurchases()
            restoreResultMessage = restored
                ? String(localized: "已恢复 Pro 权益")
                : String(localized: "未找到可恢复的购买")
        }
    }
}
