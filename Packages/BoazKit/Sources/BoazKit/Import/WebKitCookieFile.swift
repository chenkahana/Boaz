import Foundation

/// WebKit's `Cookies.binarycookies`, read just far enough to say whether a store still holds cookies.
public enum WebKitCookieFile {
    /// Cookies in `data` that haven't expired at `now`; nil when `data` isn't a well-formed cookie file.
    public static func unexpiredCount(in data: Data, now: Date = Date()) -> Int? {
        let bytes = [UInt8](data)
        func word(_ at: Int, bigEndian: Bool) -> Int? {
            guard at >= 0, at + 4 <= bytes.count else { return nil }
            let value = bytes[at..<at + 4].reduce(0) { $0 << 8 | Int($1) }
            return bigEndian ? value : Int(UInt32(value).byteSwapped)
        }
        guard bytes.starts(with: Array("cook".utf8)), let pages = word(4, bigEndian: true),
              8 + pages * 4 <= bytes.count else { return nil }
        var page = 8 + pages * 4, count = 0
        for index in 0..<pages {
            guard let size = word(8 + index * 4, bigEndian: true), page + size <= bytes.count,
                  let cookies = word(page + 4, bigEndian: false), 8 + cookies * 4 <= size else { return nil }
            for cookie in 0..<cookies {
                guard let start = word(page + 8 + cookie * 4, bigEndian: false), start + 48 <= size else { return nil }
                let expiry = bytes[page + start + 40..<page + start + 48].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                if Date(timeIntervalSinceReferenceDate: Double(bitPattern: expiry)) > now { count += 1 }
            }
            page += size
        }
        return count
    }
}
