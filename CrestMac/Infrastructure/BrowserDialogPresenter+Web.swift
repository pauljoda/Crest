import AppKit
import Foundation

extension BrowserDialogPresenter {
    // MARK: - Actions - Script dialogs

    func presentAlert(
        message: String,
        request: URLRequest,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        alert.addButton(withTitle: "OK")
        present(alert, dismissal: dismissal) { _ in completion() }
    }

    func presentConfirm(
        message: String,
        request: URLRequest,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, dismissal: dismissal) { completion($0 == .alertFirstButtonReturn) }
    }

    /// Pages no longer choose the wording of a beforeunload prompt, so the
    /// message names the site rather than repeating page-supplied text.
    func presentBeforeUnload(
        request: URLRequest,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Leave this page?"
        alert.informativeText = "Changes you made on \(Self.sourceLabel(for: request)) may not be saved."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Leave Page")
        alert.addButton(withTitle: "Stay on Page")
        present(alert, comesForward: true, dismissal: dismissal) { completion($0 == .alertFirstButtonReturn) }
    }

    func presentPrompt(
        message: String,
        defaultText: String?,
        request: URLRequest,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert, dismissal: dismissal) { response in
            completion(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    /// The page's server as a dialog names it, which the core formats: its
    /// host, with the port only when it is not the scheme's default.
    static func sourceLabel(for request: URLRequest) -> String {
        guard let url = request.url, let host = url.host(), !host.isEmpty else {
            return ProductIdentity.name
        }
        guard let port = url.port else { return host }
        return BrowserCorePolicy.authenticationSourceLabel(
            host: host, port: port, scheme: url.scheme, emptyHostLabel: ProductIdentity.name)
    }

    private func makeAlert(message: String, request: URLRequest) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "\(Self.sourceLabel(for: request)) says"
        alert.informativeText = message
        alert.alertStyle = .informational
        return alert
    }

    // MARK: - Actions - Files

    func presentFileInput(
        options: BrowserFileInputOptions,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Choose Files for \(Self.sourceLabel(for: request))"
        panel.canChooseFiles = true
        panel.canChooseDirectories = options.allowsDirectories
        panel.allowsMultipleSelection = options.allowsMultipleSelection
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        present(panel) { response in
            completion(response == .OK ? panel.urls : nil)
        }
    }

    func presentFileAccessFailure(
        _ error: Error,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = makeAlert(message: "Crest couldn’t open the selected files.", request: request)
        alert.informativeText = error.localizedDescription
        let denied =
            (error as NSError).domain == NSCocoaErrorDomain
            && (error as NSError).code == CocoaError.fileReadNoPermission.rawValue
        if denied {
            alert.informativeText +=
                " Allow Crest in Privacy & Security > Files and Folders, then choose the files again."
            alert.addButton(withTitle: "Open Files and Folders Settings")
        }
        alert.addButton(withTitle: "OK")
        present(alert) { response in
            if denied, response == .alertFirstButtonReturn,
                let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")
            {
                NSWorkspace.shared.open(url)
            }
            completion()
        }
    }

    // MARK: - Actions - Authentication

    func presentHTTPAuthentication(
        prompt: BrowserHTTPAuthenticationPrompt,
        spaceName: String,
        dismissal: BrowserPromptDismissal? = nil
    ) async -> BrowserHTTPAuthenticationPromptResponse? {
        let descriptor = prompt.descriptor
        let alert = NSAlert()
        alert.messageText = "Sign in to \(descriptor.source)"
        alert.informativeText = authenticationMessage(
            prompt: prompt,
            spaceName: spaceName
        )
        alert.alertStyle = descriptor.isSecureTransport ? .informational : .warning

        let username = NSTextField(string: prompt.suggestedUsername ?? "")
        username.placeholderString = "Username"
        username.setAccessibilityLabel("Username")
        let password = NSSecureTextField(string: "")
        password.placeholderString = "Password"
        password.setAccessibilityLabel("Password")

        let savePassword = NSButton(
            checkboxWithTitle: "Save in \(spaceName)",
            target: nil,
            action: nil
        )
        savePassword.state = .on
        savePassword.setAccessibilityLabel("Save this sign-in in the \(spaceName) Space")

        let accessoryHeight: CGFloat = prompt.allowsSaving ? 84 : 56
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: accessoryHeight))
        username.frame = NSRect(x: 0, y: accessoryHeight - 24, width: 280, height: 24)
        password.frame = NSRect(x: 0, y: accessoryHeight - 56, width: 280, height: 24)
        fields.addSubview(username)
        fields.addSubview(password)
        if prompt.allowsSaving {
            savePassword.frame = NSRect(x: 0, y: 0, width: 280, height: 20)
            fields.addSubview(savePassword)
        }
        alert.accessoryView = fields
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = username

        return await withCheckedContinuation { continuation in
            present(alert, dismissal: dismissal) { response in
                guard response == .alertFirstButtonReturn else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(
                    returning: BrowserHTTPAuthenticationPromptResponse(
                        username: username.stringValue,
                        password: password.stringValue,
                        shouldSave: prompt.allowsSaving && savePassword.state == .on
                    )
                )
            }
        }
    }

    private func authenticationMessage(
        prompt: BrowserHTTPAuthenticationPrompt,
        spaceName: String
    ) -> String {
        let descriptor = prompt.descriptor
        var components: [String] = []
        if let realm = descriptor.realm, !realm.isEmpty {
            components.append("Realm: \(realm)")
        }
        if prompt.allowsSaving {
            components.append(
                "This sign-in belongs only to the \(spaceName) Space. "
                    + "Crest saves it only after the site accepts it."
            )
        } else {
            components.append(
                "This sign-in belongs only to the \(spaceName) Space and cannot "
                    + "be saved because the connection is not protected by HTTPS."
            )
        }
        if descriptor.previousFailureCount > 0 {
            components.append("The previous credentials were not accepted.")
        }
        if !descriptor.isSecureTransport {
            components.append("Warning: this connection is not protected by HTTPS.")
        }
        return components.joined(separator: "\n\n")
    }

}
