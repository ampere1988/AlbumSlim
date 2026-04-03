import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProductID = SubscriptionService.yearlyID

    private var subscription: SubscriptionService { services.subscription }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featureComparisonSection
                    productCardsSection
                    purchaseButton
                    footerSection
                }
                .padding()
            }
            .navigationTitle("解锁 Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .task { await subscription.loadProducts() }
            .alert("购买出错", isPresented: .init(
                get: { subscription.purchaseError != nil },
                set: { if !$0 { subscription.purchaseError = nil } }
            )) {
                Button("确定") {}
            } message: {
                Text(subscription.purchaseError ?? "")
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow.gradient)
            Text("解锁 Pro")
                .font(.largeTitle.bold())
            Text("无限制使用所有功能，释放更多空间")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    // MARK: - Feature Comparison

    private var featureComparisonSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("功能")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("免费")
                    .frame(width: 60)
                Text("Pro")
                    .frame(width: 60)
                    .foregroundStyle(.blue)
                    .bold()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ForEach(featureRows, id: \.name) { row in
                HStack {
                    Text(row.name)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.free)
                        .font(.caption)
                        .frame(width: 60)
                        .foregroundStyle(.secondary)
                    featureIcon(row.pro)
                        .frame(width: 60)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                if row.name != featureRows.last?.name {
                    Divider().padding(.horizontal, 12)
                }
            }
        }
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func featureIcon(_ text: String) -> some View {
        if text == "yes" {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if text == "no" {
            Image(systemName: "xmark.circle")
                .foregroundStyle(.red.opacity(0.6))
        } else {
            Text(text)
                .font(.caption)
                .foregroundStyle(.blue)
        }
    }

    private var featureRows: [FeatureRow] {
        [
            FeatureRow(name: "存储仪表盘", free: "yes", pro: "yes"),
            FeatureRow(name: "视频排序", free: "yes", pro: "yes"),
            FeatureRow(name: "废片检测", free: "20张", pro: "无限"),
            FeatureRow(name: "相似照片", free: "3组", pro: "无限"),
            FeatureRow(name: "视频压缩", free: "no", pro: "yes"),
            FeatureRow(name: "OCR 识别", free: "no", pro: "yes"),
            FeatureRow(name: "一键清理", free: "no", pro: "yes"),
        ]
    }

    // MARK: - Product Cards

    private var productCardsSection: some View {
        VStack(spacing: 10) {
            if subscription.isLoading && subscription.products.isEmpty {
                ProgressView("加载中...")
                    .padding()
            } else {
                ForEach(subscription.products, id: \.id) { product in
                    productCard(product)
                }
            }
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly = product.id == SubscriptionService.yearlyID

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(productDisplayName(product))
                        .font(.headline)
                    if isYearly {
                        Text("推荐")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                Text(productSubtitle(product))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(product.displayPrice)
                .font(.title3.bold())
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? Color.blue.opacity(0.05) : Color.clear)
                )
        )
        .onTapGesture { selectedProductID = product.id }
    }

    private func productDisplayName(_ product: Product) -> String {
        switch product.id {
        case SubscriptionService.monthlyID: return "月订阅"
        case SubscriptionService.yearlyID: return "年订阅"
        case SubscriptionService.lifetimeID: return "终身买断"
        default: return product.displayName
        }
    }

    private func productSubtitle(_ product: Product) -> String {
        switch product.id {
        case SubscriptionService.monthlyID: return "按月付费，随时取消"
        case SubscriptionService.yearlyID: return "省47%，最划算"
        case SubscriptionService.lifetimeID: return "一次购买，永久使用"
        default: return ""
        }
    }

    // MARK: - Purchase Button

    private var purchaseButton: some View {
        Button {
            guard let product = subscription.products.first(where: { $0.id == selectedProductID }) else { return }
            Task {
                try? await subscription.purchase(product)
                if subscription.isPro { dismiss() }
            }
        } label: {
            Group {
                if subscription.isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("订阅")
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(subscription.isLoading || subscription.products.isEmpty)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            Button("恢复购买") {
                Task { await subscription.restorePurchases() }
            }
            .font(.footnote)

            Text("订阅将从 Apple ID 账户扣费。月/年订阅到期前24小时自动续费，可在设置中管理或取消订阅。终身买断为一次性付费，不自动续费。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}

private struct FeatureRow {
    let name: String
    let free: String
    let pro: String
}
