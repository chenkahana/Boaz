import BoazKit
import LocalAuthentication
import OSLog
import WebKit

/// Boaz's saved passwords on web pages: offers the site's sign-ins when a login field is focused, fills the one the
/// user picks once they authenticate, and offers to save what they sign in with. A script in its own content world
/// finds the fields and reports focus and sign-ins; pages can't see it, call it or post to it, and no password goes
/// into the page before the user picks one. Main frames only, so an embedded frame from elsewhere gets nothing.
/// One for the app; lives in `Apps/Browser` so both apps compile it.
@Observable final class PasswordAutofill {
    static let shared = PasswordAutofill()

    /// The login field focused in a tab, and what to offer there.
    struct Field: Equatable {
        var tabID: String
        /// The page's origin, as WebKit reports it: the only page a pick is filled into.
        var origin: String
        /// In the page's CSS pixels, from the visible viewport's top left.
        var rect: CGRect
        /// The visible viewport's width in CSS pixels: the view's width over this is points per pixel.
        var viewportWidth: Double
        var suggestions: [SavedPassword]
    }

    /// A sign-in the user just made with a password Boaz doesn't have.
    struct SaveOffer: Identifiable, Equatable {
        let id = UUID()
        var tabID: String
        var entry: SavedPassword
        var password: String
        var isUpdate: Bool
    }

    private(set) var field: Field?
    var offer: SaveOffer?
    /// Every saved sign-in, without passwords; read again after each change.
    private(set) var saved: [SavedPassword] = []

    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var hiding: Task<Void, Never>?
    /// The username a two-step sign-in took on its first page, by site, for its password page.
    @ObservationIgnored private var usernames: [String: (name: String, at: Date)] = [:]
    @ObservationIgnored private var lastSubmit: (key: String, at: Date)?

    nonisolated private static let log = Logger(subsystem: "com.chenkahana.boaz", category: "passwords")
    private static let world = WKContentWorld.world(name: "boaz-passwords")
    private static let messageName = "boazPasswords"

    func reload() {
        do {
            saved = try SavedPasswords.all()
        } catch {
            Self.log.error("Reading saved passwords failed: \(String(describing: error))")
        }
        loaded = true
    }

    /// `offersToSave` is false in private browsing: sign-ins there are filled, never kept.
    func install(in configuration: inout WebPage.Configuration, tabID: String, offersToSave: Bool) {
        configuration.userContentController.addUserScript(
            WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world))
        configuration.userContentController.add(Messages { [weak self] body, origin in
            self?.receive(body, from: origin, tabID: tabID, offersToSave: offersToSave)
        }, contentWorld: Self.world, name: Self.messageName)
    }

    /// Fills `entry` into the focused form, once the user proves it's them.
    func fill(_ entry: SavedPassword, on page: WebPage) async {
        guard let field else { return }
        hide()
        guard await Self.authenticate("fill your password for \(entry.site)"),
              let password = try? SavedPasswords.password(for: entry) else { return }
        _ = try? await page.callJavaScript("return window.__boazPasswords?.fill(origin, username, password) ?? false;",
                                           arguments: ["origin": field.origin, "username": entry.username,
                                                       "password": password],
                                           contentWorld: Self.world)
    }

    func hide() {
        hiding?.cancel()
        field = nil
    }

    func save(_ offer: SaveOffer) {
        self.offer = nil
        do {
            try SavedPasswords.save(offer.entry, password: offer.password)
        } catch {
            Self.log.error("Saving a password failed: \(String(describing: error))")
        }
        reload()
    }

    func delete(_ entry: SavedPassword) throws {
        try SavedPasswords.delete(entry)
        reload()
    }

    /// Touch ID, Face ID or the device's password. A device with no passcode has nothing to ask for.
    static func authenticate(_ reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return (error as? LAError)?.code == .passcodeNotSet
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
    }

    // MARK: Messages

    private func receive(_ body: [String: Any], from origin: WKSecurityOrigin, tabID: String, offersToSave: Bool) {
        let port = origin.port == 0 ? "" : ":\(origin.port)"
        guard let url = URL(string: "\(origin.protocol)://\(origin.host)\(port)") else { return }
        switch body["type"] as? String {
        case "focus":
            guard let rect = body["rect"] as? [Double], rect.count == 4,
                  let width = body["width"] as? Double, width > 0 else { return }
            if !loaded { reload() }
            let typed = (body["typed"] as? String)?.lowercased() ?? ""
            let suggestions = saved.offered(at: url).filter { typed.isEmpty || $0.username.lowercased().hasPrefix(typed) }
            hiding?.cancel()
            field = suggestions.isEmpty ? nil : Field(
                tabID: tabID, origin: url.absoluteString, rect: CGRect(x: rect[0], y: rect[1], width: rect[2], height: rect[3]),
                viewportWidth: width, suggestions: suggestions)
        case "blur":
            // Not at once: a click on a suggestion blurs the field on its way to the suggestion.
            hiding?.cancel()
            hiding = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, self?.field?.tabID == tabID else { return }
                self?.field = nil
            }
        case "submit":
            guard offersToSave else { return }
            submitted(username: body["username"] as? String ?? "", password: body["password"] as? String, at: url,
                      tabID: tabID)
        default:
            break
        }
    }

    private func submitted(username: String, password: String?, at url: URL, tabID: String) {
        let site = url.absoluteString
        guard let password, !password.isEmpty else {
            if !username.isEmpty { usernames[site] = (username, .now) }
            return
        }
        var username = username
        if username.isEmpty, let earlier = usernames[site], earlier.at > .now - 300 { username = earlier.name }
        guard let entry = SavedPassword(url: url, username: username) else { return }
        // One sign-in, however many of its events the script saw.
        let key = "\(entry.id)|\(password.hashValue)"
        if let lastSubmit, lastSubmit.key == key, lastSubmit.at > .now - 5 { return }
        lastSubmit = (key, .now)
        if !loaded { reload() }
        let existing = saved.first { $0.id == entry.id }
        if let existing, (try? SavedPasswords.password(for: existing)) == password { return }
        offer = SaveOffer(tabID: tabID, entry: entry, password: password, isUpdate: existing != nil)
    }

    private final class Messages: NSObject, WKScriptMessageHandler {
        private let onMessage: ([String: Any], WKSecurityOrigin) -> Void

        init(onMessage: @escaping ([String: Any], WKSecurityOrigin) -> Void) { self.onMessage = onMessage }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else { return }
            onMessage(body, message.frameInfo.securityOrigin)
        }
    }

    // MARK: Script

    /// A login field is a password field, or the text field before a form's first password field (or one marked as
    /// a username, or named like one on a page that asks for the username alone). Sign-ins are seen as forms submit,
    /// Return in a field and clicks on a form's button; only the user's own (trusted) events count, so a page can't
    /// make Boaz offer to save what it likes.
    private static let script = """
        (() => {
            if (window.__boazPasswords) return;
            const post = message => window.webkit.messageHandlers.\(messageName).postMessage(message);
            const textTypes = new Set(['text', 'email', 'tel']);
            const isPassword = e => e instanceof HTMLInputElement && e.type === 'password';
            const isText = e => e instanceof HTMLInputElement && textTypes.has(e.type);
            const autocomplete = e => (e.getAttribute('autocomplete') || '').toLowerCase();
            const shown = e => {
                const r = e.getBoundingClientRect();
                return r.width > 0 && r.height > 0 && getComputedStyle(e).visibility !== 'hidden';
            };
            const scopeOf = e => e.form || e.closest('form') || document;
            const inputs = scope => [...scope.querySelectorAll('input')].filter(e => !e.disabled && !e.readOnly && shown(e));
            const namedLikeUsername = e => /user|email|login|account|identifier/i
                .test([e.name, e.id, autocomplete(e), e.getAttribute('aria-label'), e.placeholder].join(' '));
            const fields = e => {
                const all = inputs(scopeOf(e));
                const password = all.find(x => isPassword(x) && autocomplete(x) !== 'new-password') || null;
                let username = all.find(x => isText(x) && /\\b(username|email)\\b/.test(autocomplete(x))) || null;
                if (!username && password) {
                    for (const x of all) { if (x === password) break; if (isText(x)) username = x; }
                }
                if (!username && !password && isText(e) && namedLikeUsername(e)) username = e;
                return { username, password };
            };

            let current = null, last = null, frame = 0;
            const report = () => {
                frame = 0;
                if (!current || !current.isConnected || document.activeElement !== current) return;
                const r = current.getBoundingClientRect(), view = visualViewport;
                post({ type: 'focus', typed: isPassword(current) ? '' : current.value,
                       rect: [r.left - view.offsetLeft, r.top - view.offsetTop, r.width, r.height], width: view.width });
            };
            const follow = () => { if (current && !frame) frame = requestAnimationFrame(report); };
            document.addEventListener('focusin', event => {
                const e = event.target;
                const f = e instanceof HTMLInputElement ? fields(e) : {};
                if (e !== f.username && e !== f.password) return;
                current = last = e;
                report();
            }, true);
            document.addEventListener('focusout', event => {
                if (event.target !== current) return;
                current = null;
                post({ type: 'blur' });
            }, true);
            document.addEventListener('input', event => { if (event.target === current) follow(); }, true);
            document.addEventListener('pointerdown', event => { if (event.target === current) follow(); }, true);
            addEventListener('scroll', follow, { capture: true, passive: true });
            visualViewport.addEventListener('resize', follow);
            visualViewport.addEventListener('scroll', follow);

            // A form changing its password has the new one last.
            const signIn = scope => {
                const all = [...scope.querySelectorAll('input')];
                const filled = all.filter(x => isPassword(x) && x.value);
                const password = filled.filter(x => autocomplete(x) === 'new-password').pop() || filled[0] || null;
                let username = null;
                for (const x of all) {
                    if (x === password || x === filled[0]) break;
                    if (isText(x) && x.value && shown(x)) username = x;
                }
                if (password) { post({ type: 'submit', username: username?.value || '', password: password.value }); return; }
                const named = all.find(x => isText(x) && x.value && shown(x) && namedLikeUsername(x));
                if (named) post({ type: 'submit', username: named.value, password: null });
            };
            document.addEventListener('submit', event => {
                if (event.isTrusted && event.target instanceof HTMLFormElement) signIn(event.target);
            }, true);
            document.addEventListener('keydown', event => {
                if (event.isTrusted && event.key === 'Enter' && event.target instanceof HTMLInputElement) {
                    signIn(scopeOf(event.target));
                }
            }, true);
            document.addEventListener('click', event => {
                if (!event.isTrusted || !(event.target instanceof Element)) return;
                const button = event.target.closest('button, input[type=submit], [role=button]');
                if (!button) return;
                const form = button.form || button.closest('form');
                if (form && button.type !== 'submit') return;
                signIn(form || document);
            }, true);

            const set = (e, value) => {
                e.value = value;
                e.dispatchEvent(new Event('input', { bubbles: true }));
                e.dispatchEvent(new Event('change', { bubbles: true }));
            };
            const fill = (origin, username, password) => {
                const target = current?.isConnected ? current : last?.isConnected ? last : null;
                if (location.origin !== origin || !target) return false;
                const f = fields(target);
                if (f.username && username) set(f.username, username);
                if (f.password) set(f.password, password);
                return true;
            };
            window.__boazPasswords = { fill };
        })();
        """
}
