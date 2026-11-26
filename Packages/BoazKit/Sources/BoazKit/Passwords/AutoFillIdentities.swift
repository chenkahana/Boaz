import AuthenticationServices
import OSLog

/// What iOS suggests above the keyboard once Boaz is on for AutoFill: the site and username of each saved password,
/// never the password, kept by iOS on the device. iOS learns nothing on its own, so the app and the AutoFill
/// extension hand it the whole list again whenever they've read it.
public enum AutoFillIdentities {
    private static let log = Logger(subsystem: "com.chenkahana.boaz", category: "passwords")

    /// Replaces the suggestions with `entries`. Does nothing while Boaz is off for AutoFill.
    public static func replace(with entries: [SavedPassword]) async {
        let store = ASCredentialIdentityStore.shared
        guard await store.state().isEnabled else { return }
        let identities: [any ASCredentialIdentity] = entries.map { entry in
            ASPasswordCredentialIdentity(serviceIdentifier: ASCredentialServiceIdentifier(identifier: entry.serviceURL, type: .URL),
                                         user: entry.username, recordIdentifier: entry.id)
        }
        do {
            try await store.replaceCredentialIdentities(identities)
        } catch {
            log.error("Updating the AutoFill suggestions failed: \(String(describing: error))")
        }
    }

    /// Reads the saved passwords and replaces the suggestions with them.
    public static func refresh() async {
        guard await ASCredentialIdentityStore.shared.state().isEnabled else { return }
        do {
            await replace(with: try SavedPasswords.all())
        } catch {
            log.error("Reading saved passwords for AutoFill failed: \(String(describing: error))")
        }
    }
}
