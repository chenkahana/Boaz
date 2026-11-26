// `make automation-control-test`: the development-only control socket's gates and command parsing
// (Apps/macOS/Engine/AutomationControl.swift), compiled without the app.
import Foundation

var failures = 0
@MainActor func check(_ condition: Bool, _ name: String, line: Int = #line) {
    if !condition { failures += 1; print("FAIL line \(line): \(name)") }
}
func parse(_ text: String) -> Result<AutomationControlProtocol.Command, AutomationControlProtocol.Failure> {
    Result { () throws(AutomationControlProtocol.Failure) in try AutomationControlProtocol.parse(Data(text.utf8)) }
}
func rejects(_ text: String) -> Bool { if case .failure = parse(text) { true } else { false } }

// Gates: every one is required.
let flag = ["/Applications/Boaz.app/Contents/MacOS/Boaz", "-BoazAutomationControl", "YES"]
check(AutomationControlProtocol.isEnabled(channel: "development", arguments: flag, automationReady: true), "all gates")
for channel in ["production", "beta", "", nil] as [String?] {
    check(!AutomationControlProtocol.isEnabled(channel: channel, arguments: flag, automationReady: true),
          "inert on channel \(channel ?? "nil")")
}
check(!AutomationControlProtocol.isEnabled(channel: "development", arguments: flag, automationReady: false),
      "needs Local Automation")
for arguments in [[], ["-BoazAutomationControl"], ["-BoazAutomationControl", "NO"], ["-BoazAutomationControl", "yes"],
                  ["BoazAutomationControl", "YES"], ["--BoazAutomationControl", "YES"], ["-BoazUITest", "YES"]] {
    check(!AutomationControlProtocol.isEnabled(channel: "development", arguments: arguments, automationReady: true),
          "needs the launch argument: \(arguments)")
}

// Commands.
check(try! parse(#"{"command":"list"}"#).get() == .list, "list")
check(try! parse(#"{"command":"quit"}"#).get() == .quit, "quit")
check(try! parse(#"{"command":"select","tab":"T1"}"#).get() == .select(tab: "T1"), "select")
check(try! parse(#"{"command":"close","tab":"T1"}"#).get() == .close(tab: "T1"), "close")
check(try! parse(#"{"command":"open","url":"https://example.com/a","space":"S1"}"#).get()
      == .open(URL(string: "https://example.com/a")!, space: "S1"), "open in a space")
check(try! parse(#"{"command":"open","url":"about:blank"}"#).get() == .open(URL(string: "about:blank")!, space: nil),
      "open in the current space")
// Incognito: open in a private window (never with a space), close private windows.
check(try! parse(#"{"command":"open","url":"https://example.com/a","private":true}"#).get()
      == .openPrivate(URL(string: "https://example.com/a")!), "open in Incognito")
check(try! parse(#"{"command":"open","url":"https://example.com/a","private":false}"#).get()
      == .open(URL(string: "https://example.com/a")!, space: nil), "private false is a normal open")
check(try! parse(#"{"command":"closePrivate"}"#).get() == .closePrivate, "close Incognito windows")
for text in [#"{"command":"open","url":"https://a.b","private":true,"space":"S1"}"#,
             #"{"command":"open","url":"https://a.b","private":1}"#,
             #"{"command":"open","url":"https://a.b","private":"yes"}"#,
             #"{"command":"open","url":"javascript:alert(1)","private":true}"#] {
    check(rejects(text), "refuses \(text)")
}
for url in ["http://127.0.0.1:8080/", "file:///tmp/a.html", "chrome://extensions", "chrome://extensions/?id=abc"] {
    check(!rejects(#"{"command":"open","url":"\#(url)"}"#), "allows \(url)")
}
for url in ["javascript:alert(1)", "data:text/html,x", "about:settings", "boaz://open", "https:///nohost", "ftp://a/b",
            "notaurl", "chrome://quit", "chrome://restart", "chrome://crash", "chrome://settings",
            "file://server/share/a.html", "file://localhost/tmp/a.html"] {
    check(rejects(#"{"command":"open","url":"\#(url)"}"#), "refuses \(url)")
}
for text in ["", "list", "[]", #"{"cmd":"list"}"#, #"{"command":"reload"}"#, #"{"command":"select"}"#,
             #"{"command":"select","tab":""}"#, #"{"command":"close","tab":7}"#, #"{"command":"open"}"#,
             #"{"command":"open","url":"https://a.b","space":7}"#] {
    check(rejects(text), "refuses \(text)")
}
check(rejects(#"{"command":"list","pad":"\#(String(repeating: "x", count: AutomationControlProtocol.maxLine))"}"#),
      "refuses a line over 64 KiB")

// A connection gets one absolute deadline: a client that trickles bytes can't hold the queue past it.
var pair: [Int32] = [0, 0]
check(socketpair(AF_UNIX, SOCK_STREAM, 0, &pair) == 0, "socketpair")
let (server, client) = (pair[0], pair[1])
_ = Darwin.write(client, "{\"command\":\"list\"}\n", 19)
check(AutomationControlProtocol.readLine(server, until: .now() + 2) == Data(#"{"command":"list"}"#.utf8), "reads one line")
let dripper = Thread { for _ in 0..<12 { _ = Darwin.write(client, "x", 1); Thread.sleep(forTimeInterval: 0.25) } }
dripper.start()
let started = Date()
check(AutomationControlProtocol.readLine(server, until: .now() + 1) == nil, "a trickling client times out")
check(Date().timeIntervalSince(started) < 1.5, "within the deadline, not per read")
Thread.sleep(forTimeInterval: 2.5)
close(server); close(client)

// Replies are one line.
let reply = AutomationControlProtocol.reply(["ok": true, "spaces": [["name": "a\nb"]]])
check(reply.last == 0x0A && reply.dropLast().firstIndex(of: 0x0A) == nil, "reply is one line")

print(failures == 0 ? "AutomationControl: all checks passed" : "AutomationControl: \(failures) failed")
exit(failures == 0 ? 0 : 1)
