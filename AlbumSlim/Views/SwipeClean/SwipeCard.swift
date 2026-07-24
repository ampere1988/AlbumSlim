import SwiftUI

/// 单张滑动卡片。offset 由父视图的拖拽手势驱动，卡片自己负责倾斜与角标。
struct SwipeCard: View {
    let image: UIImage?
    let offset: CGSize
    let isTop: Bool

    /// 超过这个横向位移即判定为一次决策
    static let decisionThreshold: CGFloat = 110

    private var rotation: Double {
        Double(offset.width / 18)
    }

    /// 角标透明度随位移线性增强
    private var badgeOpacity: Double {
        min(Double(abs(offset.width) / Self.decisionThreshold), 1.0)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if isTop, offset.width < 0 {
                badge(text: String(localized: "删除"), color: .red)
                    .padding(20)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isTop, offset.width > 0 {
                badge(text: String(localized: "保留"), color: .green)
                    .padding(20)
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .rotationEffect(.degrees(isTop ? rotation : 0))
        .offset(isTop ? offset : .zero)
    }

    private func badge(text: String, color: Color) -> some View {
        Text(text)
            .font(.title2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(color, lineWidth: 3)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .opacity(badgeOpacity)
    }
}
