import SwiftUI

/// 小胶囊标签: 张数、体积、废片原因等元信息统一用它。
///
/// 只承载已经在别处出现过的信息, 所以默认合并进父级朗读, 由调用方给容器
/// 一个完整的 accessibilityLabel。
struct MetaChip: View {
    private let label: Text
    private let systemImage: String?
    private let tint: Color

    /// 运行时拼出来的动态文本(体积、张数等)
    init(text: String, systemImage: String? = nil, tint: Color = Theme.textSecondary) {
        self.label = Text(text)
        self.systemImage = systemImage
        self.tint = tint
    }

    /// 需要本地化的固定文案
    init(_ key: LocalizedStringKey, systemImage: String? = nil, tint: Color = Theme.textSecondary) {
        self.label = Text(key)
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            label
                .font(AppFont.label)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background {
            Capsule().fill(tint.opacity(0.14))
        }
    }
}

#Preview {
    HStack(spacing: Spacing.s) {
        MetaChip(text: "128 张", systemImage: "photo")
        MetaChip(text: "2.4 GB", systemImage: "internaldrive", tint: Theme.video)
        MetaChip("模糊", systemImage: "camera.filters", tint: Theme.warning)
    }
    .padding()
    .background(Theme.background)
}
