import SwiftUI

struct MediaGridView: View {
    let items: [MediaItem]
    let bestItemID: String?
    let services: AppServiceContainer
    var isSelectable: Bool = false
    var selection: Binding<Set<String>>?

    /// 两列让相似照片保留足够的脸部和文字细节，用户无需打开详情就能判断。
    private let columns = [
        GridItem(.flexible(), spacing: Spacing.s),
        GridItem(.flexible(), spacing: Spacing.s)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Spacing.s) {
            ForEach(items) { item in
                ThumbnailCell(
                    item: item,
                    isBest: item.id == bestItemID,
                    isSelectable: isSelectable,
                    isSelected: selection?.wrappedValue.contains(item.id) ?? false,
                    services: services
                ) {
                    toggle(item)
                }
            }
        }
    }

    private func toggle(_ item: MediaItem) {
        guard let selection else { return }
        if selection.wrappedValue.contains(item.id) {
            selection.wrappedValue.remove(item.id)
        } else {
            selection.wrappedValue.insert(item.id)
        }
    }
}
