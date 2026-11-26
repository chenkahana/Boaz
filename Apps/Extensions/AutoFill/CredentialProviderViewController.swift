import AuthenticationServices
import BoazKit
import LocalAuthentication
import SwiftUI

/// Boaz's passwords in AutoFill: the list behind the key above the keyboard, a password picked from the suggestions
/// above it, and the sheet iOS shows when the user turns Boaz on. Read-only, reading the Keychain items the app saves,
/// and a password leaves only after Face ID, Touch ID or the device passcode, for the sign-in the user picked.
final class CredentialProviderViewController: ASCredentialProviderViewController {
    private let model = AutoFillModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.fill = { [weak self] entry, password in
            self?.extensionContext.completeRequest(
                withSelectedCredential: ASPasswordCredential(user: entry.username, password: password))
        }
        model.cancel = { [weak self] in self?.cancel(.userCanceled) }
        model.finishConfiguration = { [weak self] in self?.extensionContext.completeExtensionConfigurationRequest() }
        let hosting = UIHostingController(rootView: AutoFillRootView(model: model))
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    /// The key above the keyboard, then Boaz: the list, for the app or site asking.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        model.showList(for: serviceIdentifiers.compactMap {
            SavedPassword.pageURL(serviceIdentifier: $0.identifier, isDomain: $0.type == .domain)
        })
    }

    /// A suggestion above the keyboard: never filled without the check.
    override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
        cancel(.userInteractionRequired)
    }

    override func prepareInterfaceToProvideCredential(for credentialRequest: any ASCredentialRequest) {
        guard let identity = credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity,
              let recordIdentifier = identity.recordIdentifier else {
            cancel(.credentialIdentityNotFound)
            return
        }
        Task {
            guard let entry = try? SavedPasswords.all().first(where: { $0.id == recordIdentifier }) else {
                // Deleted since iOS last heard: tell it now, so it stops suggesting it.
                await AutoFillIdentities.refresh()
                cancel(.credentialIdentityNotFound)
                return
            }
            guard await DeviceOwner.authenticate("fill your password for \(entry.site)") else {
                cancel(.userCanceled)
                return
            }
            guard let password = try? SavedPasswords.password(for: entry) else {
                cancel(.credentialIdentityNotFound)
                return
            }
            model.fill(entry, password)
        }
    }

    /// The user turned Boaz on in Settings (or from Boaz): say so, and give iOS the suggestions straight away.
    override func prepareInterfaceForExtensionConfiguration() {
        model.screen = .configuration
        Task { await AutoFillIdentities.refresh() }
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: ASExtensionError(code))
    }
}

/// Touch ID, Face ID or the device's passcode, as in the app (`PasswordAutofill.authenticate`). A device with no
/// passcode has nothing to ask for.
enum DeviceOwner {
    static func authenticate(_ reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return (error as? LAError)?.code == .passcodeNotSet
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) == true
    }
}
