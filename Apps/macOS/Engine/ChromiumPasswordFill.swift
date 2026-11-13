#if BOAZ_CHROMIUM
import AppKit
import BoazKit

@MainActor
enum ChromiumPasswordFill {
    private static var filling = false

    static func run(on page: ChromiumEnginePageAdapter, window: NSWindow,
                    report: @escaping (String) -> Void) async {
        guard !filling else { return }
        filling = true
        defer { filling = false }
        let navigation = page.state.navigationID
        let url = page.state.url
        let key = UUID().uuidString
        func unchanged() -> Bool {
            page.state.lifecycle == .active && page.state.navigationID == navigation && page.state.url == url
        }
        defer {
            Task { @MainActor in
                guard unchanged() else { return }
                _ = try? await page.executeTrusted(function:
                    "({key}) => { delete window.__boazManualPasswordFills?.[key]; return null; }",
                    arguments: ["key": .string(key)])
            }
        }
        do {
            let prepared = try await page.executeTrusted(function: Self.prepare, arguments: ["key": .string(key)])
            try Task.checkCancellation()
            guard unchanged(), prepared == .bool(true) else {
                report("Select a sign-in field on this page, then choose Fill Saved Password again.")
                return
            }
            let target = try page.captureTrustedDocument()
            defer { target.release() }
            guard unchanged(), let scheme = target.origin.scheme?.lowercased(),
                  scheme == "https" || scheme == "http" else {
                report("Passwords can only be filled on HTTP or HTTPS pages.")
                return
            }
            let entries = try SavedPasswords.all().offered(at: target.origin)
            guard !entries.isEmpty else { report("No saved passwords match this site."); return }
            guard let entry = await choose(entries, site: target.origin.host() ?? "this site", window: window) else { return }
            try Task.checkCancellation()
            guard unchanged() else { report("The page changed. Select the sign-in field and try again."); return }
            guard await PasswordAutofill.authenticate("fill your password for \(entry.site)") else { return }
            try Task.checkCancellation()
            guard unchanged() else { report("The page changed. Select the sign-in field and try again."); return }
            let password = try SavedPasswords.password(for: entry)
            let result = try await page.executeTrusted(on: target, function: """
                ({key, origin, username, password}) => {
                    const fill = window.__boazManualPasswordFills?.[key];
                    delete window.__boazManualPasswordFills?.[key];
                    return fill ? fill(origin, username, password) : false;
                }
                """, arguments: ["key": .string(key), "origin": .string(target.origin.absoluteString),
                    "username": .string(entry.username), "password": .string(password)])
            guard result == .bool(true) else { report("The sign-in field changed. Select it and try again."); return }
        } catch is CancellationError {
            return
        } catch {
            report("The password could not be filled. The page may have changed; please try again.")
        }
    }

    private static func choose(_ entries: [SavedPassword], site: String, window: NSWindow) async -> SavedPassword? {
        let alert = NSAlert()
        alert.messageText = "Fill Saved Password"
        alert.informativeText = "Choose a sign-in for \(site)."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        picker.addItems(withTitles: entries.map { $0.username.isEmpty ? "(No username) — \($0.site)" : "\($0.username) — \($0.site)" })
        picker.setAccessibilityLabel("Saved sign-in")
        alert.accessoryView = picker
        let response = await alert.beginSheetModal(for: window)
        guard response == .alertFirstButtonReturn, entries.indices.contains(picker.indexOfSelectedItem) else { return nil }
        return entries[picker.indexOfSelectedItem]
    }

    // Same field selection and input/change dispatch policy as PasswordAutofill's bundled script.
    private static let prepare = """
        ({key}) => {
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

            const set = (e, value) => {
                e.value = value;
                e.dispatchEvent(new Event('input', { bubbles: true }));
                e.dispatchEvent(new Event('change', { bubbles: true }));
            };
            const target = document.activeElement;
            if (!(target instanceof HTMLInputElement)) return false;
            const found = fields(target);
            if (target !== found.username && target !== found.password) return false;
            window.__boazManualPasswordFills ??= Object.create(null);
            window.__boazManualPasswordFills[key] = (origin, username, password) => {
                if (location.origin !== origin || !target.isConnected) return false;
                const f = fields(target);
                if (f.username && username) set(f.username, username);
                if (f.password) set(f.password, password);
                return true;
            };
            return true;
        }
        """
}
#endif
