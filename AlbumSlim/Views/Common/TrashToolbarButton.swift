import SwiftUI

/// 模块右上 toolbar 的垃圾桶入口按钮（带数字 badge）
/// 用法：`TrashToolbarButton(count: services.trash.trashedItems.count) { showTrash = true }`
struct TrashToolbarButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.tap()
            action()
        }) {
            Image(systemName: AppIcons.trash)
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text("\(min(count, 99))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.red))
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .accessibilityLabel("垃圾桶")
        .accessibilityValue(count > 0 ? "\(count) 项" : "空")
    }
}
