import SwiftUI

struct SavedNotesView: View {
    @Environment(AppServiceContainer.self) private var services
    @State private var showDeleteAllConfirmation = false
    @State private var copiedToast: String?

    var body: some View {
        NavigationStack {
            Group {
                if services.notesExport.notes.isEmpty {
                    ContentUnavailableView(
                        "暂无识别记录",
                        systemImage: "doc.text",
                        description: Text("截图识别后保存的文字会显示在这里")
                    )
                } else {
                    notesList
                }
            }
            .navigationTitle("识别记录")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !services.notesExport.notes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("清空", role: .destructive) {
                            showDeleteAllConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog("确定清空所有识别记录？", isPresented: $showDeleteAllConfirmation, titleVisibility: .visible) {
                Button("清空", role: .destructive) {
                    services.notesExport.deleteAll()
                }
            }
            .overlay(alignment: .bottom) {
                if let toast = copiedToast {
                    Text(toast)
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onAppear {
                            Task {
                                try? await Task.sleep(for: .seconds(1.5))
                                withAnimation { copiedToast = nil }
                            }
                        }
                }
            }
            .animation(.default, value: copiedToast)
        }
    }

    private var notesList: some View {
        List {
            ForEach(services.notesExport.notes) { note in
                NavigationLink {
                    SavedNoteDetailView(note: note, copiedToast: $copiedToast)
                } label: {
                    noteRow(note)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        services.notesExport.deleteNote(note.id)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        UIPasteboard.general.string = note.text
                        withAnimation { copiedToast = "已复制到剪贴板" }
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .tint(.blue)
                }
            }
        }
    }

    private func noteRow(_ note: SavedNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                let cat = ScreenshotCategory(rawValue: note.category) ?? .other
                Text(note.category)
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cat.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(cat.color)

                Spacer()

                if let date = note.screenshotDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(note.text)
                .font(.subheadline)
                .lineLimit(2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct SavedNoteDetailView: View {
    @Environment(AppServiceContainer.self) private var services
    @Environment(\.dismiss) private var dismiss
    let note: SavedNote
    @Binding var copiedToast: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                let cat = ScreenshotCategory(rawValue: note.category) ?? .other
                HStack {
                    Text(note.category)
                        .font(.subheadline.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(cat.color.opacity(0.15), in: Capsule())
                        .foregroundStyle(cat.color)

                    if let date = note.screenshotDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(note.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider()

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = note.text
                        withAnimation { copiedToast = "已复制到剪贴板" }
                    } label: {
                        Label("复制文字", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    ShareLink(
                        item: services.notesExport.shareText(for: note),
                        subject: Text(note.category)
                    ) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        }
        .navigationTitle("识别内容")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("删除记录", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("确定删除这条记录？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                services.notesExport.deleteNote(note.id)
                dismiss()
            }
        }
    }
}
