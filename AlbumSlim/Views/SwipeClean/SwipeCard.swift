import SwiftUI

/// 单张滑动卡片。offset 由父视图的拖拽手势驱动，卡片自己负责倾斜、色彩反馈与角标。
///
/// 决策反馈做了三层，越靠近阈值越强烈：卡片倾斜 → 方向色蒙层 → 印章式角标。
/// 用户还没松手就已经知道这一下会发生什么。
struct SwipeCard: View {
    let image: UIImage?
    let offset: CGSize
    let isTop: Bool

    /// 超过这个横向位移即判定为一次决策
    static let decisionThreshold: CGFloat = 110

    private var rotation: Double {
        Double(offset.width / 18)
    }

    /// 决策强度 0…1，随位移线性增强
    private var intensity: Double {
        min(Double(abs(offset.width) / Self.decisionThreshold), 1)
    }

    private var isDeleting: Bool { offset.width < 0 }

    private var directionColor: Color {
        isDeleting ? Theme.danger : Theme.success
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Theme.surfaceRaised)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Theme.surfaceSunken)
                    .shimmer()
            }
        }
        .overlay {
            // 方向色蒙层：删除偏红、保留偏绿，最高只到 28% 以免盖住照片本身
            if isTop && intensity > 0 {
                directionColor.opacity(intensity * 0.28)
            }
        }
        .clipShape(.rect(cornerRadius: Radius.hero))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.hero)
                .strokeBorder(isTop ? directionColor.opacity(intensity) : Theme.hairline,
                              lineWidth: isTop && intensity > 0 ? 3 : 1)
        }
        .overlay(alignment: .topLeading) {
            if isTop, offset.width < 0 {
                stamp(text: "删除", color: Theme.danger, angle: -12)
                    .padding(Spacing.xl)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isTop, offset.width > 0 {
                stamp(text: "保留", color: Theme.success, angle: 12)
                    .padding(Spacing.xl)
            }
        }
        .elevation(.floating)
        .rotationEffect(.degrees(isTop ? rotation : 0))
        .offset(isTop ? offset : .zero)
    }

    /// 印章式角标：带倾角、随强度放大，比平躺的圆角矩形更有"盖章"的决断感
    private func stamp(text: LocalizedStringKey, color: Color, angle: Double) -> some View {
        Text(text)
            .font(AppFont.screenTitle)
            .foregroundStyle(color)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .background {
                RoundedRectangle(cornerRadius: Radius.row)
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.row)
                    .strokeBorder(color, lineWidth: 3)
            }
            .rotationEffect(.degrees(angle))
            .scaleEffect(0.85 + 0.15 * intensity)
            .opacity(intensity)
    }
}
