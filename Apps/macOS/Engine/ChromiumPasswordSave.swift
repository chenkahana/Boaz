#if BOAZ_CHROMIUM
import AppKit
import BoazKit

@MainActor
final class ChromiumPasswordSave {
    static let shared = ChromiumPasswordSave()
    private var generation: UInt64 = 0
    private var task: Task<Void, Never>?
    private var page: ChromiumEnginePageAdapter?
    private var navigation: UInt64?
    private var profile: EngineProfileIdentity?
    private var alert: NSAlert?
    private weak var window: NSWindow?

    func offer(on page: ChromiumEnginePageAdapter, target: ChromiumCapturedDocument,
               sourceOrigin: URL, username: String, password: String, window: NSWindow) {
        dismiss()
        guard !page.profile.isPrivate, target.page == page.handle, target.profile == page.profile,
              target.navigationID == page.state.navigationID, page.state.lifecycle == .active,
              username.utf8.count <= 65_536, password.utf8.count <= 65_536 - username.utf8.count,
              let entry = SavedPassword(url: sourceOrigin, username: username),
              sourceOrigin.user == nil, sourceOrigin.password == nil,
              window.isVisible, window.attachedSheet == nil else {
            target.release()
            return
        }
        self.page = page
        navigation = target.navigationID
        profile = target.profile
        self.window = window
        let current = generation
        let prompt = NSAlert()
        prompt.messageText = "Save Password?"
        prompt.informativeText = "Save this sign-in for \(entry.site) in your passwords?"
        prompt.addButton(withTitle: "Save Password")
        prompt.addButton(withTitle: "Not Now")
        alert = prompt
        task = Task { @MainActor [weak self] in
            defer {
                target.release()
                if let self, self.generation == current {
                    self.alert = nil
                    self.page = nil
                    self.navigation = nil
                    self.profile = nil
                    self.window = nil
                    self.task = nil
                }
            }
            guard let self, self.isCurrent(current, page: page) else { return }
            let response = await prompt.beginSheetModal(for: window)
            guard response == .alertFirstButtonReturn, !Task.isCancelled,
                  self.isCurrent(current, page: page) else { return }
            guard await PasswordAutofill.authenticate("save your password for \(entry.site)"),
                  !Task.isCancelled, self.isCurrent(current, page: page) else { return }
            do {
                let valid = try await page.executeTrusted(on: target, function: "() => true", arguments: [:])
                guard valid == .bool(true), !Task.isCancelled,
                      self.isCurrent(current, page: page) else { return }
                // Keep the authoritative document check adjacent to the synchronous write.
                try SavedPasswords.save(entry, password: password)
            } catch is CancellationError {
            } catch {
                guard self.generation == current else { return }
                MacModel.shared.showToast("The password could not be saved. Please try again.")
            }
        }
    }

    func invalidate(page handle: BoazHostPage) {
        guard let page, page.handle == handle else { return }
        if page.state.lifecycle != .active || page.state.navigationID != navigation || page.profile != profile {
            dismiss(page: handle)
        }
    }

    func dismiss(page handle: BoazHostPage? = nil) {
        if let handle, page?.handle != handle { return }
        generation &+= 1
        task?.cancel()
        task = nil
        if let sheet = alert?.window, let parent = sheet.sheetParent {
            parent.endSheet(sheet, returnCode: .cancel)
        }
        alert = nil
        page = nil
        navigation = nil
        profile = nil
        window = nil
    }

    private func isCurrent(_ current: UInt64, page: ChromiumEnginePageAdapter) -> Bool {
        generation == current && self.page === page && !page.profile.isPrivate &&
            page.profile == profile && page.state.lifecycle == .active &&
            page.state.navigationID == navigation && window?.isVisible == true
    }
}
#endif
