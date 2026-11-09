import QuickLook
import SwiftUI

/// Downloaded files list, opened from the BrowserBar menu. Preview with QuickLook, share, or delete.
struct DownloadsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var files: [DownloadedFile] = []
    @State private var previewing: DownloadedFile?

    var body: some View {
        NavigationStack {
            List {
                ForEach(files) { file in
                    // Share sits beside the row button, not inside its label, so it stays its own target.
                    HStack(spacing: 4) {
                        Button { previewing = file } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.fill").font(.title2).foregroundStyle(Theme.brand)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.url.lastPathComponent).lineLimit(1).foregroundStyle(.primary)
                                    Text("\(sizeLabel(file.size)) · \(file.savedAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        ShareLink(item: file.url) { Label("Share", systemImage: "square.and.arrow.up") }
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                            .buttonStyle(.plain)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            Downloads.delete(file)
                            reload()
                        }
                    }
                }
            }
            .overlay {
                if files.isEmpty {
                    ContentUnavailableView("No downloads", systemImage: "arrow.down.circle",
                                           description: Text("Files you download appear here."))
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
            .sheet(item: $previewing) { file in QuickLookView(url: file.url) }
        }
        .onAppear(perform: reload)
    }

    private func reload() { files = Downloads.list() }

    private func sizeLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// Minimal `QLPreviewController` host; SwiftUI has no native QuickLook view on iOS.
private struct QuickLookView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as QLPreviewItem
        }
    }
}
