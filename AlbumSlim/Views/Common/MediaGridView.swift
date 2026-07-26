import SwiftUI

struct MediaGridView: View {
    let items: [MediaItem]
    let bestItemID: String?
    let services: AppServiceContainer
    var isSelectable: Bool = false
    var selection: Binding<Set<String>>?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Spacing.s)]

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
