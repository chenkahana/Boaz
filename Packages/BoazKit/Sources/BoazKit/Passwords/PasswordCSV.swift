import Foundation

/// A sign-in read from another browser's or password manager's export.
public struct ImportedPassword: Sendable {
    public var entry: SavedPassword
    public var password: String
}

/// Reads the CSV that browsers export passwords as: Chrome, Edge, Brave and Arc (`name,url,username,password,note`),
/// Firefox (`url,username,password,httpRealm,…`), Safari and Apple Passwords (`Title,URL,Username,Password,Notes,…`),
/// and password managers that name their columns alike (Bitwarden's `login_uri`, `login_username`, `login_password`).
public enum PasswordCSV {
    public enum Failure: LocalizedError {
        case noColumns

        public var errorDescription: String? {
            "This file has no website, username and password columns. Export your passwords as CSV from the browser and choose that file."
        }
    }

    /// The rows with a web address and a password; rows for apps, notes or other schemes are left out.
    public static func read(_ text: String) throws -> [ImportedPassword] {
        var rows = records(text)
        guard !rows.isEmpty else { throw Failure.noColumns }
        let header = rows.removeFirst().map { $0.lowercased().filter(\.isLetter) }
        func column(_ names: [String]) -> Int? { names.lazy.compactMap { header.firstIndex(of: $0) }.first }
        guard let url = column(["url", "loginuri", "website", "uri", "origin", "hostname", "address", "siteurl"]),
              let password = column(["password", "loginpassword", "pass"]) else { throw Failure.noColumns }
        let username = column(["username", "loginusername", "login", "user", "email", "emailaddress", "account"])
        return rows.compactMap { row in
            func value(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index]
            }
            let secret = value(password)
            var address = value(url).trimmingCharacters(in: .whitespaces)
            if !address.contains("://") { address = "https://" + address }
            guard !secret.isEmpty, let site = URL(string: address),
                  let entry = SavedPassword(url: site, username: value(username)) else { return nil }
            return ImportedPassword(entry: entry, password: secret)
        }
    }

    /// RFC 4180 records: quoted fields may hold commas, line breaks and doubled quotes.
    static func records(_ text: String) -> [[String]] {
        var records: [[String]] = [], record: [String] = [], field = ""
        var quoted = false, pendingQuote = false
        for character in text.trimmingPrefix("\u{FEFF}") {
            if quoted {
                if pendingQuote {
                    pendingQuote = false
                    if character == "\"" { field.append("\""); continue }
                    quoted = false
                } else if character == "\"" {
                    pendingQuote = true
                    continue
                } else {
                    field.append(character)
                    continue
                }
            }
            switch character {
            case "\"" where field.isEmpty: quoted = true
            case ",": record.append(field); field = ""
            case "\n", "\r\n", "\r":
                record.append(field); field = ""
                if record.contains(where: { !$0.isEmpty }) { records.append(record) }
                record = []
            default: field.append(character)
            }
        }
        record.append(field)
        if record.contains(where: { !$0.isEmpty }) { records.append(record) }
        return records
    }
}
