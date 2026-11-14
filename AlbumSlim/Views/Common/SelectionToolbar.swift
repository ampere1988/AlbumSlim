import SwiftUI

/// 标准编辑模式 toolbar：右上"选择/完成" + 编辑模式下左上"全选/取消全选"
/// 在 View 上挂载：`.modifier(SelectionToolbar(isEditing:..., selectedCount:..., totalCount:..., onSelectAll:..., onDeselectAll:...))`
struct SelectionToolbar: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isEditing: Bool
    let selectedCount: Int
    let totalCount: Int
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? AppStrings.done : AppStrings.select) {
                        Haptics.tap()
                        withAnimation(reduceMotion ? nil : Motion.standard) {
                            isEditing.toggle()
                        }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(selectedCount == totalCount && totalCount > 0
                               ? AppStrings.deselectAll
                               : AppStrings.selectAll) {
                            Haptics.tap()
                            if selectedCount == totalCount { onDeselectAll() } else { onSelectAll() }
                        }
                        .disabled(totalCount == 0)
                    }
                    ToolbarItem(placement: .principal) {
                        Text(AppStrings.selected(selectedCount))
                            .font(.headline)
                            .contentTransition(.numericText())
                            .motion(Motion.standard, value: selectedCount)
                    }
                }
            }
            .navigationBarTitleDisplayMode(isEditing ? .inline : .automatic)
    }
}

extension View {
    func selectionToolbar(
        isEditing: Binding<Bool>,
        selectedCount: Int,
        totalCount: Int,
        onSelectAll: @escaping () -> Void,
        onDeselectAll: @escaping () -> Void
    ) -> some View {
        modifier(SelectionToolbar(
            isEditing: isEditing,
            selectedCount: selectedCount,
            totalCount: totalCount,
            onSelectAll: onSelectAll,
            onDeselectAll: onDeselectAll
        ))
    }
}
