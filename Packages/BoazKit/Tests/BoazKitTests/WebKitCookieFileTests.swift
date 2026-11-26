import Foundation
import Testing
@testable import BoazKit

@Suite("WebKitCookieFile")
struct WebKitCookieFileTests {
    /// A `Cookies.binarycookies` file with one page holding a cookie per expiry date.
    private func file(expiring dates: [Date]) -> Data {
        func le32(_ value: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(value).littleEndian, Array.init) }
        func be32(_ value: Int) -> [UInt8] { withUnsafeBytes(of: UInt32(value).bigEndian, Array.init) }
        let record = 56
        let header = 8 + dates.count * 4 + 4
        var page = [0, 0, 1, 0] + le32(dates.count)
        page += dates.indices.flatMap { le32(header + $0 * record) } + [0, 0, 0, 0]
        for date in dates {
            var cookie = le32(record) + [UInt8](repeating: 0, count: 36)
            cookie += withUnsafeBytes(of: date.timeIntervalSinceReferenceDate.bitPattern.littleEndian, Array.init)
            cookie += [UInt8](repeating: 0, count: 8)
            page += cookie
        }
        return Data(Array("cook".utf8) + be32(1) + be32(page.count) + page + [UInt8](repeating: 0, count: 8))
    }

    @Test func countsOnlyUnexpiredCookies() {
        let now = Date()
        let data = file(expiring: [now.addingTimeInterval(86_400), now.addingTimeInterval(-60), .distantFuture])
        #expect(WebKitCookieFile.unexpiredCount(in: data, now: now) == 2)
        #expect(WebKitCookieFile.unexpiredCount(in: data, now: .distantPast) == 3)
    }

    @Test func emptyStoreHasNone() {
        #expect(WebKitCookieFile.unexpiredCount(in: file(expiring: [])) == 0)
        #expect(WebKitCookieFile.unexpiredCount(in: Data(Array("cook".utf8) + [0, 0, 0, 0])) == 0)
    }

    @Test func rejectsOtherAndTruncatedFiles() {
        #expect(WebKitCookieFile.unexpiredCount(in: Data()) == nil)
        #expect(WebKitCookieFile.unexpiredCount(in: Data("SQLite format 3".utf8)) == nil)
        #expect(WebKitCookieFile.unexpiredCount(in: file(expiring: [.distantFuture]).prefix(40)) == nil)
        #expect(WebKitCookieFile.unexpiredCount(in: Data(Array("cook".utf8) + [0xFF, 0xFF, 0xFF, 0xFF])) == nil)
    }
}
