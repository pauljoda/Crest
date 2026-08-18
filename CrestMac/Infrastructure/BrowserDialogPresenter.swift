import AppKit
import Foundation
import WebKit

@MainActor
final class BrowserDialogPresenter {
    func presentAlert(
        message: String,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completion() }
    }

    func presentConfirm(
        message: String,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { completion($0 == .alertFirstButtonReturn) }
    }

    func presentPrompt(
        message: String,
        defaultText: String?,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = makeAlert(message: message, request: request)
        let input = NSTextField(string: defaultText ?? "")
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            completion(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func presentFileInput(
        parameters: WKOpenPanelParameters,
        request: URLRequest,
        completion: @escaping @MainActor @Sendable ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.title = "Choose Files for \(Self.sourceLabel(for: request))"
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        present(panel) { response in
            completion(response == .OK ? panel.urls : nil)
        }
    }

    func presentHTTPAuthentication(
        prompt: BrowserHTTPAuthenticationPrompt,
        spaceName: String
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
            present(alert) { response in
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

    func presentMediaCapturePermission(
        permission: BrowserMediaPermission,
        origin: BrowserSiteOrigin,
        topLevelURL: URL?,
        spaceName: String,
        completion:
            @escaping @MainActor @Sendable (BrowserSitePermissionPromptResponse) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Allow \(origin.host) to use your \(permission.displayName)?"
        var message =
            "This request belongs only to the \(spaceName) Space. "
            + "Saved choices can be changed in Settings > Site Permissions."
        if let topLevelURL,
            let topLevelHost = topLevelURL.host(),
            topLevelHost.caseInsensitiveCompare(origin.host) != .orderedSame
        {
            message += "\n\nThe request comes from \(origin.displayName) inside \(topLevelHost)."
        }
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Allow Once")
        alert.addButton(withTitle: "Always Allow in \(spaceName)")
        alert.addButton(withTitle: "Block in \(spaceName)")

        present(alert) { response in
            switch response {
            case .alertFirstButtonReturn:
                completion(.allowOnce)
            case .alertSecondButtonReturn:
                completion(.grantPersistently)
            default:
                completion(.denyPersistently)
            }
        }
    }

    func presentGeolocationPermission(
        origin: BrowserSiteOrigin,
        topLevelURL: URL?,
        spaceName: String
    ) async -> BrowserSitePermissionPromptResponse {
        var message =
            "This site will be able to use your current location for this request. "
            + "The choice belongs only to the \(spaceName) Space."
        if let topLevelURL,
            let topLevelHost = topLevelURL.host(),
            topLevelHost.caseInsensitiveCompare(origin.host) != .orderedSame
        {
            message += "\n\nThe request comes from \(origin.displayName) inside \(topLevelHost)."
        }
        return await presentSitePermission(
            title: "Allow \(origin.host) to use your location?",
            message: message,
            allowOnceTitle: "Allow Once",
            alwaysAllowTitle: "Always Allow in \(spaceName)",
            blockTitle: "Block in \(spaceName)"
        )
    }

    func presentHostedNotificationPermission(
        origin: BrowserSiteOrigin,
        spaceName: String
    ) async -> BrowserSitePermissionPromptResponse {
        await presentSitePermission(
            title: "Allow notifications from \(origin.host)?",
            message:
                "Notifications can appear outside Crest while this page is open. "
                + "Background Web Push is not supported. "
                + "The choice belongs only to the \(spaceName) Space.",
            allowOnceTitle: "Allow for Session",
            alwaysAllowTitle: "Always Allow in \(spaceName)",
            blockTitle: "Block in \(spaceName)"
        )
    }

    /// Explains the second, app-level permission boundary before leaving Crest.
    /// The caller keeps the page's original request pending, then rechecks the
    /// system authorization after Crest becomes active again.
    func recoverGeolocationSystemAuthorization() async {
        guard
            let settingsURL = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
            )
        else { return }
        await presentSystemPermissionRecovery(
            title: "Location Access Is Off for Crest",
            message:
                "macOS is blocking Crest from receiving a location, even when this site is allowed. "
                + "Turn on Crest in Privacy & Security > Location Services. "
                + "This request will continue when you return.",
            openButtonTitle: "Open Location Settings",
            settingsURL: settingsURL
        )
    }

    func recoverNotificationSystemAuthorization() async {
        var components = URLComponents(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: Bundle.main.bundleIdentifier)
        ]
        guard let settingsURL = components?.url else { return }
        await presentSystemPermissionRecovery(
            title: "Notifications Are Off for Crest",
            message:
                "macOS is blocking Crest notifications, even when this site is allowed. "
                + "Turn on Allow notifications for Crest. "
                + "This request will continue when you return.",
            openButtonTitle: "Open Notification Settings",
            settingsURL: settingsURL
        )
    }

    /// Asks before Crest leaves the browser for another application. Cancelling
    /// is not offered as a saved block, so Escape declines this one hand-off
    /// rather than silently muting the site for good.
    func presentExternalApplicationPermission(
        origin: BrowserSiteOrigin,
        destinationURL: URL,
        spaceName: String
    ) async -> BrowserExternalSchemePromptResponse {
        let scheme = destinationURL.scheme?.lowercased() ?? "link"
        return await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Open this “\(scheme)” link in another app?"
            alert.informativeText =
                "\(origin.host) wants to leave Crest and open "
                + "\(Self.externalDestinationLabel(for: destinationURL)). "
                + "The choice belongs only to the \(spaceName) Space and can be "
                + "changed in Settings > Site Permissions."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open")
            alert.addButton(withTitle: "Always Allow in \(spaceName)")
            alert.addButton(withTitle: "Cancel")
            present(alert) { response in
                switch response {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: .open)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: .openAndRemember)
                default:
                    continuation.resume(returning: .cancel)
                }
            }
        }
    }

    /// Shows enough of an external URL to judge it without pasting a whole
    /// tracker-laden query string into an alert.
    static func externalDestinationLabel(for url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        if let host = url.host(), !host.isEmpty {
            return "\(scheme)://\(host)"
        }
        let path = url.absoluteString.dropFirst(scheme.count + 1)
        let trimmed = path.prefix(while: { $0 != "?" })
        return trimmed.isEmpty ? url.absoluteString : "\(scheme):\(trimmed)"
    }

    func presentAutomaticDownloadPermission(
        filename: String,
        origin: BrowserSiteOrigin,
        spaceName: String
    ) async -> BrowserSitePermissionPromptResponse {
        await presentSitePermission(
            title: "Allow automatic downloads from \(origin.host)?",
            message:
                "The site started “\(filename)” without a direct download action. "
                + "The choice belongs only to the \(spaceName) Space.",
            allowOnceTitle: "Download Once",
            alwaysAllowTitle: "Always Allow in \(spaceName)",
            blockTitle: "Block in \(spaceName)"
        )
    }

    func approveRiskyDownload(
        assessment: BrowserDownloadRiskAssessment,
        sourceURL: URL?,
        spaceName: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Download “\(assessment.sanitizedFilename)”?"
            var paragraphs = assessment.reasons.map(\.message)
            if let host = sourceURL?.host() {
                paragraphs.append("Source: \(host) · Space: \(spaceName)")
            } else {
                paragraphs.append("Space: \(spaceName)")
            }
            paragraphs.append("macOS will quarantine the completed file. Open it only if you trust its source.")
            alert.informativeText = paragraphs.joined(separator: "\n\n")
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Download")
            alert.addButton(withTitle: "Cancel")
            present(alert) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }

    static func sourceLabel(for request: URLRequest) -> String {
        guard let url = request.url, let host = url.host(), !host.isEmpty else {
            return ProductIdentity.name
        }
        guard let port = url.port, !isDefault(port: port, for: url.scheme) else { return host }
        return "\(host):\(port)"
    }

    private static func isDefault(port: Int, for scheme: String?) -> Bool {
        switch scheme?.lowercased() {
        case "http":
            return port == 80
        case "https":
            return port == 443
        default:
            return false
        }
    }

    private func makeAlert(message: String, request: URLRequest) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "\(Self.sourceLabel(for: request)) says"
        alert.informativeText = message
        alert.alertStyle = .informational
        return alert
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

    private func presentSitePermission(
        title: String,
        message: String,
        allowOnceTitle: String,
        alwaysAllowTitle: String,
        blockTitle: String
    ) async -> BrowserSitePermissionPromptResponse {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: allowOnceTitle)
            alert.addButton(withTitle: alwaysAllowTitle)
            alert.addButton(withTitle: blockTitle)
            present(alert) { response in
                switch response {
                case .alertFirstButtonReturn:
                    continuation.resume(returning: .allowOnce)
                case .alertSecondButtonReturn:
                    continuation.resume(returning: .grantPersistently)
                default:
                    continuation.resume(returning: .denyPersistently)
                }
            }
        }
    }

    private func presentSystemPermissionRecovery(
        title: String,
        message: String,
        openButtonTitle: String,
        settingsURL: URL
    ) async {
        let shouldOpen = await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: openButtonTitle)
            alert.addButton(withTitle: "Not Now")
            present(alert) { response in
                continuation.resume(
                    returning: response == .alertFirstButtonReturn
                )
            }
        }
        guard shouldOpen, NSWorkspace.shared.open(settingsURL) else { return }
        await waitForApplicationReturn()
    }

    private func waitForApplicationReturn() async {
        var observedInactiveApplication = !NSApp.isActive
        while !observedInactiveApplication {
            try? await Task.sleep(for: .milliseconds(100))
            observedInactiveApplication = !NSApp.isActive
        }
        while !NSApp.isActive {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func present(
        _ alert: NSAlert,
        completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        guard let window = hostWindow else {
            completion(alert.runModal())
            return
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    private func present(
        _ panel: NSOpenPanel,
        completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        guard let window = hostWindow else {
            completion(panel.runModal())
            return
        }
        panel.beginSheetModal(for: window, completionHandler: completion)
    }

    private var hostWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }
}
