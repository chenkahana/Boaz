#if BOAZ_CHROMIUM
import AppKit
import UniformTypeIdentifiers

@MainActor
enum ChromiumPageCapture {
    static func exportVisible(from adapter: ChromiumEnginePageAdapter, window: NSWindow?,
                              onError: @escaping @MainActor (String) -> Void) {
        Task { @MainActor in
            do {
                let data = try await adapter.captureVisible(maxWidth: 2048, maxHeight: 1024)
                guard let window, window.isVisible else { return }
                guard let bitmap = NSBitmapImageRep(data: data) else {
                    throw ChromiumCaptureError.malformedResult
                }
                let panel = NSSavePanel()
                panel.title = "Save Visible Area"
                panel.allowedContentTypes = [.png]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = "Boaz Screenshot.png"
                panel.message = "Visible area captured at \(bitmap.pixelsWide) × \(bitmap.pixelsHigh) pixels."
                guard await panel.beginSheetModal(for: window) == .OK,
                      let destination = panel.url else { return }
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destination, options: .atomic)
                }.value
            } catch is CancellationError {
            } catch {
                onError("Could not save screenshot: \(error.localizedDescription)")
            }
        }
    }
}
#endif
