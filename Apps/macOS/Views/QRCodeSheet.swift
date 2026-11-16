import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UniformTypeIdentifiers

/// A QR code for a page or image address, from the page's context menu.
struct QRCodeSheet: View {
    let url: URL
    let title: String
    let done: () -> Void
    private let image: NSImage?

    init(url: URL, title: String, done: @escaping () -> Void) {
        self.url = url
        self.title = title
        self.done = done
        image = Self.image(for: url.absoluteString)
    }

    var body: some View {
        VStack(spacing: 14) {
            if let image {
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 240, height: 240)
            } else {
                ContentUnavailableView("Too Long for a QR Code", systemImage: "qrcode",
                    description: Text("This address has too many characters to fit in a QR code."))
                    .frame(width: 240, height: 240)
            }
            VStack(spacing: 2) {
                if !title.isEmpty { Text(title).font(.headline).lineLimit(1) }
                Text(url.absoluteString).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
            }
            HStack {
                Button("Copy Image", systemImage: "doc.on.doc") {
                    guard let image else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
                .disabled(image == nil)
                Button("Save PNG…", systemImage: "square.and.arrow.down", action: save).disabled(image == nil)
                Spacer()
                Button("Done", action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.qrCode")
        .onExitCommand(perform: done)
    }

    private func save() {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(url.host() ?? "QR Code").png"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do { try data.write(to: destination) }
            catch { NSAlert(error: error).runModal() }
        }
    }

    /// Black modules on white with a four-module quiet zone; nil when the text doesn't fit.
    private static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let framed = code.composited(over: CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -4, dy: -4)))
        let scaled = framed.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// Shows the sheet on the window whose page asked for it.
    @MainActor static func present(_ url: URL, title: String, on window: NSWindow) {
        let sheet = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        sheet.contentViewController = NSHostingController(rootView: QRCodeSheet(url: url, title: title) {
            [weak window, weak sheet] in
            guard let sheet else { return }
            window?.endSheet(sheet)
        })
        window.beginSheet(sheet)
    }
}
