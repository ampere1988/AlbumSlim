import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss

    private var subscription: SubscriptionService { services.subscription }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    featureList
                    purchaseSection
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
            .task { await subscription.loadProduct() }
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
            Text("解锁全部功能")
                .font(.largeTitle.bold())
            Text("一次购买，永久使用")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            featureRow(icon: "trash.circle.fill", color: .red, text: "无限废片清理")
            featureRow(icon: "square.on.square", color: .green, text: "相似照片去重")
            featureRow(icon: "video.fill", color: .blue, text: "视频压缩与批量管理")
            featureRow(icon: "text.viewfinder", color: .orange, text: "截图 OCR 文字识别")
            featureRow(icon: "square.stack.3d.up.fill", color: .purple, text: "连拍 / 大照片清理")
            featureRow(icon: "wand.and.stars", color: .pink, text: "智能一键扫描清理")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Purchase

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if subscription.isLoading && subscription.product == nil {
                ProgressView("加载中...")
                    .padding()
            } else if let product = subscription.product {
                Button {
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
                            Text("\(product.displayPrice) 永久解锁")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscription.isLoading)
            } else {
                VStack(spacing: 8) {
                    Text("无法加载产品信息")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("重试") {
                        Task { await subscription.loadProduct() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 8) {
            Button("恢复购买") {
                Task { await subscription.restorePurchases() }
            }
            .font(.footnote)

            Text("一次性付费，不自动续费。购买后永久解锁所有 Pro 功能。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
}
