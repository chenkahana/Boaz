#if BOAZ_CHROMIUM
import AppKit
import UniformTypeIdentifiers

@MainActor
enum ChromiumPageCapture {
    static func exportPDF(from adapter: ChromiumEnginePageAdapter, window: NSWindow?,
                          onError: @escaping @MainActor (String) -> Void) {
        Task { @MainActor in
            do {
                let data = try await adapter.capturePDF()
                guard let window, window.isVisible else { return }
                let panel = NSSavePanel()
                panel.title = "Save as PDF"
                panel.allowedContentTypes = [.pdf]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = "Boaz Page.pdf"
                panel.message = "A4 portrait document with backgrounds and 10 mm margins."
                guard await panel.beginSheetModal(for: window) == .OK,
                      let destination = panel.url else { return }
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destination, options: .atomic)
                }.value
            } catch is CancellationError {
            } catch {
                onError("Could not save PDF: \(error.localizedDescription)")
            }
        }
    }

    static func exportFullPage(from adapter: ChromiumEnginePageAdapter, window: NSWindow?,
                              onError: @escaping @MainActor (String) -> Void) {
        Task { @MainActor in
            do {
                let data = try await adapter.captureFullPage()
                guard let window, window.isVisible else { return }
                guard let bitmap = NSBitmapImageRep(data: data) else {
                    throw ChromiumCaptureError.malformedResult
                }
                let panel = NSSavePanel()
                panel.title = "Save Full Page"
                panel.allowedContentTypes = [.png]
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = "Boaz Screenshot.png"
                panel.message = "Current laid-out document captured at \(bitmap.pixelsWide) × \(bitmap.pixelsHigh) pixels. Content requiring scrolling to load is not included."
                guard await panel.beginSheetModal(for: window) == .OK,
                      let destination = panel.url else { return }
                let scoped = destination.startAccessingSecurityScopedResource()
                defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
                try await Task.detached(priority: .userInitiated) {
                    try data.write(to: destination, options: .atomic)
                }.value
            } catch is CancellationError {
            } catch {
                onError("Could not capture the full page. It may exceed the size limit, have changed, or have Developer Tools open. \(error.localizedDescription)")
            }
        }
    }

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
