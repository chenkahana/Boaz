import Foundation
import Testing
@testable import BoazKit

@Suite("PasswordCSV")
struct PasswordCSVTests {
    @Test func chromeFormat() throws {
        let csv = """
        name,url,username,password,note
        Example,https://example.com/login,chen,secret1,
        Other,https://other.example,other@example.com,p@ss word,with note
        """
        let rows = try PasswordCSV.read(csv)
        #expect(rows.count == 2)
        #expect(rows[0].entry.host == "example.com")
        #expect(rows[0].entry.username == "chen")
        #expect(rows[0].password == "secret1")
        #expect(rows[1].password == "p@ss word")
    }

    @Test func firefoxFormat() throws {
        let csv = """
        url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged
        https://example.com,chen,secret1,,https://example.com,{abc},0,0,0
        """
        let rows = try PasswordCSV.read(csv)
        #expect(rows.count == 1)
        #expect(rows[0].entry.username == "chen")
    }

    @Test func applePasswordsFormat() throws {
        let csv = """
        Title,URL,Username,Password,Notes,OTPAuth
        Example,https://example.com,chen,secret1,,
        """
        #expect(try PasswordCSV.read(csv).count == 1)
    }

    @Test func bitwardenFormat() throws {
        let csv = """
        folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp
        ,0,login,Example,,,0,https://example.com,chen,secret1,
        """
        #expect(try PasswordCSV.read(csv).count == 1)
    }

    @Test func bareHostsGetHTTPS() throws {
        let csv = """
        name,url,username,password,note
        Example,example.com,chen,secret1,
        """
        #expect(try PasswordCSV.read(csv).first?.entry.isSecure == true)
        #expect(try PasswordCSV.read(csv).first?.entry.host == "example.com")
    }

    @Test func appAndEmptyPasswordRowsAreSkipped() throws {
        let csv = """
        name,url,username,password,note
        App,android://com.example.app,chen,secret1,
        Empty,https://empty.example,chen,,
        Web,https://web.example,chen,secret2,
        """
        let rows = try PasswordCSV.read(csv)
        #expect(rows.count == 1)
        #expect(rows[0].entry.host == "web.example")
    }

    @Test func quotedFieldsKeepCommasNewlinesAndQuotes() throws {
        let csv = "name,url,username,password,note\n" +
            "Example,https://example.com,\"chen, admin\",\"line1\nline2 \"\"quoted\"\"\","
        let rows = try PasswordCSV.read(csv)
        #expect(rows.count == 1)
        #expect(rows[0].entry.username == "chen, admin")
        #expect(rows[0].password == "line1\nline2 \"quoted\"")
    }

    @Test func byteOrderMarkIsTolerated() throws {
        let csv = "\u{FEFF}name,url,username,password,note\nExample,https://example.com,chen,secret1,"
        #expect(try PasswordCSV.read(csv).count == 1)
    }

    @Test func fileWithoutKnownColumnsThrows() {
        #expect(throws: PasswordCSV.Failure.self) {
            _ = try PasswordCSV.read("a,b,c\n1,2,3")
        }
        #expect(throws: PasswordCSV.Failure.self) {
            _ = try PasswordCSV.read("")
        }
    }

    @Test func windowsLineEndings() throws {
        let csv = "name,url,username,password,note\r\nExample,https://example.com,chen,secret1,\r\n"
        #expect(try PasswordCSV.read(csv).count == 1)
    }
}
