#if BOAZ_CHROMIUM || AUTOMATION_CONTROL_TESTS
import Foundation

/// The development-only tab control socket's gates and wire format (one JSON object per line each way). Test drivers
/// use it to open, select and close tabs and to quit, without synthetic input; `Tools/chromium/automation_client.py`
/// (`Control`) is its client. Pure, so `make automation-control-test` checks it without the app.
nonisolated enum AutomationControlProtocol {
    static let argument = "-BoazAutomationControl"
    static let maxLine = 64 * 1024

    /// All three, or no socket: a development-channel app (the sealed Info.plist key), `-BoazAutomationControl YES`
    /// on this launch's command line (never read from stored defaults), and Local Automation running.
    static func isEnabled(channel: String?, arguments: [String], automationReady: Bool) -> Bool {
        guard channel == "development", automationReady,
              let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return false }
        return arguments[index + 1] == "YES"
    }

    enum Command: Equatable {
        case list
        case open(URL, space: String?)
        case select(tab: String)
        case close(tab: String)
        case quit
    }

    struct Failure: Error, Equatable { let message: String }

    static func parse(_ line: Data) throws(Failure) -> Command {
        guard line.count <= maxLine else { throw Failure(message: "Command is longer than 64 KiB") }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let name = object["command"] as? String else { throw Failure(message: "Expected {\"command\": ...}") }
        func string(_ key: String) throws(Failure) -> String {
            guard let value = object[key] as? String, !value.isEmpty else { throw Failure(message: "\(name) needs \(key)") }
            return value
        }
        switch name {
        case "list": return .list
        case "open":
            let text = try string("url")
            guard let url = allowedURL(text) else { throw Failure(message: "URL not allowed: \(text)") }
            if object["space"] != nil, !(object["space"] is String) { throw Failure(message: "space must be a string") }
            return .open(url, space: object["space"] as? String)
        case "select": return .select(tab: try string("tab"))
        case "close": return .close(tab: try string("tab"))
        case "quit": return .quit
        default: throw Failure(message: "Unknown command: \(name)")
        }
    }

    /// http(s) with a host, file, about:blank, and chrome:// pages (chrome://extensions).
    static func allowedURL(_ text: String) -> URL? {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "http", "https": return url.host()?.isEmpty == false ? url : nil
        case "file", "chrome": return url
        case "about": return text == "about:blank" ? url : nil
        default: return nil
        }
    }

    static func reply(_ object: [String: Any]) -> Data {
        var data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            ?? Data(#"{"ok":false,"error":"Reply could not be encoded"}"#.utf8)
        data.append(0x0A)
        return data
    }
}
#endif

#if BOAZ_CHROMIUM
import AppKit
import BoazKit

/// Listens on `$TMPDIR/boaz-control-<pid>.sock` (the per-user 0700 temporary directory) only while
/// `AutomationControlProtocol.isEnabled`; production and default launches return before any socket exists. Every
/// connection's peer must be this user (`getpeereid`), the same trust boundary as the 0600 DevTools record. Commands run
/// on the main actor through the sidebar's own entry points, so routing, spaces and profiles behave as they do by hand.
@MainActor
final class AutomationControl {
    static let shared = AutomationControl()
    private var source: DispatchSourceRead?
    private var path: String?
    private var waiting: Task<Void, Never>?
    private var browsers: () -> [BrowserState] = { [] }
    private var quit: () -> Void = {}

    private var channel: String? { Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String }
    private var automationReady: Bool { ChromiumAutomation.shared.status?.state == .ready }
    private func enabled(ready: Bool) -> Bool {
        AutomationControlProtocol.isEnabled(channel: channel, arguments: ProcessInfo.processInfo.arguments,
                                            automationReady: ready)
    }

    func start(browsers: @escaping () -> [BrowserState], quit: @escaping () -> Void) {
        stop()
        guard enabled(ready: true) else { return }
        self.browsers = browsers
        self.quit = quit
        waiting = Task { @MainActor [weak self] in
            // Local Automation reports READY shortly after startup; give up if it's off or never comes up.
            for _ in 0..<120 {
                guard let self, !Task.isCancelled else { return }
                switch ChromiumAutomation.shared.status?.state {
                case .ready:
                    guard enabled(ready: true) else { return }
                    do { try listen() } catch { NSLog("Boaz automation control: %@", "\(error)") }
                    return
                case .disabled, .failed: return
                case .starting, nil: break
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stop() {
        waiting?.cancel()
        waiting = nil
        source?.cancel()
        source = nil
        if let path { unlink(path) }
        path = nil
    }

    private func listen() throws {
        let directory = try Self.privateTemporaryDirectory()
        Self.removeStaleSockets(in: directory)
        let path = directory + "/boaz-control-\(getpid()).sock"
        let fd = try Self.bind(path)
        self.path = path
        let queue = DispatchQueue(label: "com.chenkahana.boaz.automation-control")
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler(handler: Self.acceptHandler(fd, queue: queue))
        source.setCancelHandler(handler: Self.closer(fd))
        source.resume()
        self.source = source
    }

    private nonisolated struct SocketError: Error, CustomStringConvertible {
        let description: String
        init(_ what: String) { description = "\(what): \(String(cString: strerror(errno)))" }
    }

    /// `$TMPDIR` straight from the system, whatever the environment says, and only if it is this user's and private.
    private nonisolated static func privateTemporaryDirectory() throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count) > 0 else { throw SocketError("confstr") }
        var directory = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        while directory.count > 1, directory.hasSuffix("/") { directory.removeLast() }
        var info = stat()
        guard lstat(directory, &info) == 0 else { throw SocketError("lstat \(directory)") }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
            throw SocketError("\(directory) is not a private directory owned by this user")
        }
        return directory
    }

    /// Sockets left by Boaz processes that are gone (a crash skips `stop`), including one at this pid's own path.
    private nonisolated static func removeStaleSockets(in directory: String) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] {
            guard let match = name.wholeMatch(of: #/boaz-control-([0-9]+)\.sock/#), let pid = pid_t(match.1) else { continue }
            let path = directory + "/" + name
            var info = stat()
            guard pid == getpid() || (kill(pid, 0) != 0 && errno == ESRCH),
                  lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK, info.st_uid == getuid() else { continue }
            unlink(path)
        }
    }

    private nonisolated static func bind(_ path: String) throws -> Int32 {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { throw SocketError("Socket path is too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError("socket") }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        let mask = umask(0o077)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(mask)
        guard bound == 0, chmod(path, 0o600) == 0, Darwin.listen(fd, 4) == 0 else {
            let error = SocketError("bind \(path)")
            close(fd)
            unlink(path)
            throw error
        }
        return fd
    }

    /// Built outside the main actor: it runs on `queue`.
    private nonisolated static func acceptHandler(_ listener: Int32, queue: DispatchQueue) -> @Sendable () -> Void {
        { @Sendable in
            let client = accept(listener, nil, nil)
            guard client >= 0 else { return }
            var uid = uid_t.max, gid = gid_t.max
            guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { close(client); return }
            _ = fcntl(client, F_SETFD, FD_CLOEXEC)
            var on: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            guard let line = readLine(client) else {
                write(client, AutomationControlProtocol.reply(["ok": false, "error": "Expected one line of at most 64 KiB"]))
                close(client)
                return
            }
            Task { @MainActor in
                let (reply, after) = await AutomationControl.shared.handle(line)
                respond(client, reply, after: after, on: queue)
            }
        }
    }

    private nonisolated static func closer(_ fd: Int32) -> @Sendable () -> Void { { close(fd) } }

    private nonisolated static func respond(_ client: Int32, _ reply: Data, after: (@MainActor @Sendable () -> Void)?,
                                            on queue: DispatchQueue) {
        queue.async {
            write(client, reply)
            close(client)
            if let after { Task { @MainActor in after() } }
        }
    }

    private nonisolated static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while data.count <= AutomationControlProtocol.maxLine {
            let count = read(fd, &buffer, buffer.count)
            guard count > 0 else { return nil }
            data.append(contentsOf: buffer[0..<count])
            if let end = data.firstIndex(of: 0x0A) {
                return end <= AutomationControlProtocol.maxLine ? data[..<end] : nil
            }
        }
        return nil
    }

    private nonisolated static func write(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress! + offset, bytes.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }

    private func handle(_ line: Data) async -> (Data, (@MainActor @Sendable () -> Void)?) {
        func failure(_ message: String) -> (Data, (@MainActor @Sendable () -> Void)?) {
            (AutomationControlProtocol.reply(["ok": false, "error": message]), nil)
        }
        guard source != nil, automationReady else { return failure("Local Automation is not running") }
        let command: AutomationControlProtocol.Command
        do { command = try AutomationControlProtocol.parse(line) } catch { return failure(error.message) }
        if command == .quit {
            // The ⌘Q path, so the saved windows restore on the next launch as they do for a user.
            return (AutomationControlProtocol.reply(["ok": true]), { AutomationControl.shared.quit() })
        }
        // The first normal window: Incognito tabs are never listed or driven.
        guard let browser = browsers().first(where: { !$0.isIncognito }) else { return failure("No browser window is open") }
        let model = browser.model
        switch command {
        case .list:
            let (activeTab, activeSpace) = (browser.activeTabID, browser.spaceID)
            let spaces = model.sidebar.spaces.map { space -> [String: Any] in
                func row(_ tab: SidebarItem, pinned: Bool) -> [String: Any] {
                    ["id": tab.id, "url": tab.url?.absoluteString ?? "", "title": tab.title ?? "",
                     "selected": tab.id == activeTab, "pinned": pinned, "today": !pinned]
                }
                let tabs = model.allPinnedTabs(in: space).map { row($0, pinned: true) }
                    + model.todayTabs(in: space).map { row($0, pinned: false) }
                return ["id": space.id, "profileID": space.profileID, "name": space.title,
                        "selected": space.id == activeSpace, "tabs": tabs]
            }
            return (AutomationControlProtocol.reply(["ok": true, "spaces": spaces]), nil)
        case let .open(url, space):
            if let space {
                guard model.space(space) != nil else { return failure("No space \(space)") }
                browser.switchSpace(to: space)
                // The switch waits for the space's profile to start the first time.
                for _ in 0..<100 where browser.spaceID != space { try? await Task.sleep(for: .milliseconds(100)) }
                guard browser.spaceID == space else { return failure("Space \(space) did not open") }
            }
            guard let current = browser.currentSpace else { return failure("No space is open") }
            let before = Set(model.todayTabs(in: current).map(\.id))
            browser.openTab(url)
            let opened = model.todayTabs(in: current).first { !before.contains($0.id) }?.id
            return (AutomationControlProtocol.reply(["ok": true, "tab": opened ?? NSNull(), "space": current.id]), nil)
        case let .select(id), let .close(id):
            guard let tab = browser.tab(id), tab.kind == .tab else { return failure("No tab \(id)") }
            if case .select = command { browser.activate(tab) } else { browser.close(tab) }
            return (AutomationControlProtocol.reply(["ok": true]), nil)
        case .quit:
            return failure("Unreachable")
        }
    }
}
#endif
