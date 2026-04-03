import SwiftUI

struct SpaceSavedBanner: View {
    let count: Int
    let size: Int64

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.title)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("发现 \(count) 项可清理")
                    .font(.headline)
                Text("可释放 \(size.formattedFileSize)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}
