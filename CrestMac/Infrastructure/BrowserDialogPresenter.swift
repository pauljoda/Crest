import AppKit
import Foundation

// MARK: - Types

struct BrowserFileInputOptions {
    let allowsDirectories: Bool
    let allowsMultipleSelection: Bool
}

@MainActor
final class BrowserDialogPresenter {
    // MARK: - Variables

    var hostWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    // MARK: - Actions - System permissions

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

    // MARK: - Actions - External applications

    /// Asks before Crest leaves the browser for another application. Cancelling
    /// is not offered as a saved block, so Escape declines this one hand-off
    /// rather than silently muting the site for good.
    func presentExternalApplicationPermission(
        origin: SiteOrigin,
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

    // MARK: - Actions - Downloads

    func approveRiskyDownload(
        assessment: DownloadRiskAssessment,
        sourceURL: URL?,
        spaceName: String
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText = "Download “\(assessment.sanitizedFilename)”?"
            var paragraphs = assessment.reasons.map { String(localized: $0.message) }
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

    /// Whether to go on with a download the core judged dangerous, before its
    /// file has a place, or to keep one its engine warned about while it
    /// downloads: the core's reasons, the engine's warning, where it came from
    /// and the Space it belongs to.
    func approveDownload(
        _ asked: DownloadApprovalAsked, spaceName: String?, dismissal: BrowserPromptDismissal? = nil
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            let keeps = asked.warning != nil
            alert.messageText = keeps ? "Keep “\(asked.filename)”?" : "Download “\(asked.filename)”?"
            var paragraphs = asked.reasons.map { String(localized: $0.message) }
            if let warning = asked.warning { paragraphs.append(String(localized: warning.approvalMessage)) }
            switch (asked.sourceHost, spaceName) {
            case (let host?, let space?): paragraphs.append("Source: \(host) · Space: \(space)")
            case (let host?, nil): paragraphs.append("Source: \(host)")
            case (nil, let space?): paragraphs.append("Space: \(space)")
            case (nil, nil): break
            }
            if !keeps {
                paragraphs.append("macOS will quarantine the completed file. Open it only if you trust its source.")
            }
            alert.informativeText = paragraphs.joined(separator: "\n\n")
            alert.alertStyle = .warning
            if keeps {
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Keep Download")
            } else {
                alert.addButton(withTitle: "Download")
                alert.addButton(withTitle: "Cancel")
            }
            present(alert, dismissal: dismissal) { response in
                continuation.resume(
                    returning: response == (keeps ? .alertSecondButtonReturn : .alertFirstButtonReturn))
            }
        }
    }

    /// Whether to quit and stop the `count` downloads still in progress.
    func approveQuitWithDownloads(count: Int, dismissal: BrowserPromptDismissal? = nil) async -> Bool {
        await withCheckedContinuation { continuation in
            let alert = NSAlert()
            alert.messageText =
                count == 1
                ? String(localized: "Quit and cancel the download in progress?")
                : String(localized: "Quit and cancel \(count) downloads in progress?")
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Keep Browsing"))
            alert.addButton(withTitle: String(localized: "Quit"))
            present(alert, comesForward: true, dismissal: dismissal) { response in
                continuation.resume(returning: response == .alertSecondButtonReturn)
            }
        }
    }

    // MARK: - Actions - Presentation

    // A `dismissal` closes the sheet once its question no longer waits; the
    // sheet then answers as declined.

    /// Shows `alert` as a sheet on the key window, or on its own while Crest
    /// has none. A question that holds up leaving a page or quitting
    /// `comesForward`: Crest activates first, so a quit asked from outside it
    /// (the updater's relaunch, the Dock, a logout) never waits on a question
    /// the person cannot see.
    func present(
        _ alert: NSAlert,
        comesForward: Bool = false,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        if comesForward, !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        guard let window = hostWindow else {
            dismissal?.attach { [weak alert] in
                guard let alert, alert.window.isVisible else { return }
                NSApp.stopModal(withCode: .cancel)
            }
            completion(alert.runModal())
            return
        }
        dismissal?.attach { [weak window, weak alert] in
            guard let window, let alert, alert.window.sheetParent === window else { return }
            window.endSheet(alert.window, returnCode: .cancel)
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }

    func present(
        _ panel: NSOpenPanel,
        completion: @escaping @MainActor @Sendable (NSApplication.ModalResponse) -> Void
    ) {
        guard let window = hostWindow else {
            completion(panel.runModal())
            return
        }
        panel.beginSheetModal(for: window, completionHandler: completion)
    }
}
