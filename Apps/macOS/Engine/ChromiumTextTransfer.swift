#if BOAZ_CHROMIUM
import Foundation

enum ChromiumTextTransferError: Error, LocalizedError {
    case tooLarge, malformed
    var errorDescription: String? {
        switch self {
        case .tooLarge: "This page exceeds the 4 MiB text extraction limit."
        case .malformed: "The page text could not be transferred."
        }
    }
}

@MainActor
enum ChromiumTextTransfer {
    static func read(from page: ChromiumEnginePageAdapter, body: String) async throws -> String {
        let navigation = page.state.navigationID
        let url = page.state.url
        let profile = page.profile
        let handle = page.handle
        let key = UUID().uuidString
        func sameDocument() -> Bool {
            page.handle == handle && page.profile == profile && page.state.lifecycle == .active &&
                page.state.navigationID == navigation && page.state.url == url
        }
        func validate() throws {
            try Task.checkCancellation()
            guard sameDocument() else { throw ChromiumTrustedScriptError.identityMismatch }
        }
        defer {
            // A separate task can clean up even when the requesting task was cancelled.
            Task { @MainActor in
                guard sameDocument() else { return }
                _ = try? await page.executeTrusted(function: "({key}) => { delete window.__boazTextTransfers?.[key]; return null; }",
                    arguments: ["key": .string(key)])
            }
        }
        try validate()
        let start = try await page.executeTrusted(function: """
            ({key}) => {
                const text = (() => {
            \(body)
                })();
                if (typeof text !== 'string') return -2;
                if (new TextEncoder().encode(text).byteLength > 4194304) return -1;
                window.__boazTextTransfers ??= Object.create(null);
                window.__boazTextTransfers[key] = text;
                return text.length;
            }
            """, arguments: ["key": .string(key)])
        try validate()
        guard case .number(let length) = start else { throw ChromiumTextTransferError.malformed }
        if length == -1 { throw ChromiumTextTransferError.tooLarge }
        guard length >= 0, length <= 4_194_304, length.rounded() == length else {
            throw ChromiumTextTransferError.malformed
        }
        var offset = 0
        var result = ""
        var bytes = 0
        while offset < Int(length) {
            try validate()
            let chunk = try await page.executeTrusted(function: """
                ({key, offset}) => {
                    const text = window.__boazTextTransfers?.[key];
                    if (typeof text !== 'string') return null;
                    let end = Math.min(offset + 8192, text.length);
                    if (end < text.length && text.charCodeAt(end - 1) >= 0xD800 &&
                        text.charCodeAt(end - 1) <= 0xDBFF && text.charCodeAt(end) >= 0xDC00 &&
                        text.charCodeAt(end) <= 0xDFFF) --end;
                    return text.slice(offset, end);
                }
                """, arguments: ["key": .string(key), "offset": .number(Double(offset))])
            try validate()
            guard case .string(let value) = chunk, !value.isEmpty,
                  value.utf16.count <= 8192, offset + value.utf16.count <= Int(length) else {
                throw ChromiumTextTransferError.malformed
            }
            bytes += value.utf8.count
            result += value
            offset += value.utf16.count
            guard bytes <= 4_194_304 else { throw ChromiumTextTransferError.tooLarge }
        }
        return result
    }
}
#endif
