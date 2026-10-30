import Dispatch
import Observation
import UIKit
import UniformTypeIdentifiers
import WebKit

@MainActor
enum MobileBrowserDialogPresenter {
    // Each dialog appears in `window`, the one showing the page that asks,
    // so a page in one iPad window never presents over another; nil, as for a
    // page no window shows, presents over the key window. A `dismissal`
    // closes the alert once its question no longer waits.

    static func presentAlert(
        message: String,
        request: URLRequest,
        in window: UIWindow?,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable () -> Void
    ) {
        let alert = UIAlertController(
            title: "\(sourceLabel(for: request)) says",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion() })
        present(alert, in: window, dismissal: dismissal, fallback: completion)
    }

    static func presentConfirmation(
        message: String,
        request: URLRequest,
        in window: UIWindow?,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let alert = UIAlertController(
            title: "\(sourceLabel(for: request)) says",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(true) })
        present(alert, in: window, dismissal: dismissal) { completion(false) }
    }

    static func presentPrompt(
        message: String,
        defaultText: String?,
        request: URLRequest,
        in window: UIWindow?,
        dismissal: BrowserPromptDismissal? = nil,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) {
        let alert = UIAlertController(
            title: "\(sourceLabel(for: request)) says",
            message: message,
            preferredStyle: .alert
        )
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(nil) })
        alert.addAction(
            UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                completion(alert?.textFields?.first?.text)
            })
        present(alert, in: window, dismissal: dismissal) { completion(nil) }
    }

    /// Keeps the originating web request alive while the person repairs the
    /// app-level permission in Settings, then lets the coordinator recheck it.
    static func recoverGeolocationSystemAuthorization(in window: UIWindow?) async {
        guard
            let settingsURL = URL(
                string: UIApplication.openSettingsURLString
            )
        else { return }
        let shouldOpen = await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Location Access Is Off for Crest",
                message:
                    "iOS is blocking Crest from receiving a location, even when this site is allowed. "
                    + "Turn on Location for Crest in Settings. "
                    + "This request will continue when you return.",
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: "Not Now", style: .cancel) { _ in
                    continuation.resume(returning: false)
                })
            alert.addAction(
                UIAlertAction(title: "Open Settings", style: .default) { _ in
                    continuation.resume(returning: true)
                })
            present(alert, in: window) {
                continuation.resume(returning: false)
            }
        }
        guard shouldOpen,
            await UIApplication.shared.open(settingsURL)
        else { return }
        var observedInactiveApplication =
            UIApplication.shared.applicationState != .active
        while !observedInactiveApplication {
            try? await Task.sleep(for: .milliseconds(100))
            observedInactiveApplication =
                UIApplication.shared.applicationState != .active
        }
        while UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Asks before Crest leaves the browser for another application. Cancelling
    /// is not offered as a saved block, so declining refuses this one hand-off
    /// rather than silently muting the site for good.
    static func presentExternalApplicationPermission(
        origin: SiteOrigin,
        destinationURL: URL,
        spaceName: String,
        in window: UIWindow?
    ) async -> BrowserExternalSchemePromptResponse {
        let scheme = destinationURL.scheme?.lowercased() ?? "link"
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "Open this “\(scheme)” link in another app?",
                message:
                    "\(origin.host) wants to leave Crest and open \(externalDestinationLabel(for: destinationURL)). The choice belongs only to the \(spaceName) Space.",
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    continuation.resume(returning: .cancel)
                })
            alert.addAction(
                UIAlertAction(title: "Open", style: .default) { _ in
                    continuation.resume(returning: .open)
                })
            alert.addAction(
                UIAlertAction(title: "Always Allow", style: .default) { _ in
                    continuation.resume(returning: .openAndRemember)
                })
            present(alert, in: window) {
                continuation.resume(returning: .cancel)
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
        let remainder = url.absoluteString.dropFirst(scheme.count + 1)
        let trimmed = remainder.prefix(while: { $0 != "?" })
        return trimmed.isEmpty ? url.absoluteString : "\(scheme):\(trimmed)"
    }

    static func presentHTTPAuthentication(
        prompt: BrowserHTTPAuthenticationPrompt,
        spaceName: String,
        in window: UIWindow?,
        dismissal: BrowserPromptDismissal? = nil
    ) async -> BrowserHTTPAuthenticationPromptResponse? {
        let descriptor = prompt.descriptor
        var paragraphs: [String] = []
        if let realm = descriptor.realm, !realm.isEmpty {
            paragraphs.append("Realm: \(realm)")
        }
        if prompt.allowsSaving {
            paragraphs.append(
                "This sign-in belongs only to the \(spaceName) Space. Crest saves it only after the site accepts it.")
        } else {
            paragraphs.append(
                "This sign-in belongs only to the \(spaceName) Space and cannot be saved because the connection is not protected by HTTPS."
            )
        }
        if descriptor.previousFailureCount > 0 {
            paragraphs.append("The previous credentials were not accepted.")
        }
        if !descriptor.isSecureTransport {
            paragraphs.append("Warning: this connection is not protected by HTTPS.")
        }

        let alert = UIAlertController(
            title: "Sign in to \(descriptor.source)",
            message: paragraphs.joined(separator: "\n\n"),
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Username"
            field.text = prompt.suggestedUsername
            field.textContentType = .username
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "Password"
            field.isSecureTextEntry = true
            field.textContentType = .password
        }
        return await withCheckedContinuation { continuation in
            // An action or the question's dismissal answers, whichever comes first.
            let answer = AlertAnswer(continuation)
            alert.addAction(
                UIAlertAction(title: "Cancel", style: .cancel) { _ in
                    answer.resume(nil)
                })
            alert.addAction(
                UIAlertAction(title: "Sign In Once", style: .default) { [weak alert] _ in
                    answer.resume(
                        authenticationResponse(
                            from: alert,
                            shouldSave: false
                        ))
                })
            if prompt.allowsSaving {
                alert.addAction(
                    UIAlertAction(title: "Sign In & Save", style: .default) { [weak alert] _ in
                        answer.resume(
                            authenticationResponse(
                                from: alert,
                                shouldSave: true
                            ))
                    })
            }
            dismissal?.attach { answer.resume(nil) }
            present(alert, in: window, dismissal: dismissal) { answer.resume(nil) }
        }
    }

    private static func authenticationResponse(
        from alert: UIAlertController?,
        shouldSave: Bool
    ) -> BrowserHTTPAuthenticationPromptResponse {
        let fields = alert?.textFields ?? []
        return BrowserHTTPAuthenticationPromptResponse(
            username: fields.first?.text ?? "",
            password: fields.dropFirst().first?.text ?? "",
            shouldSave: shouldSave
        )
    }

    static func exportDownloadedFile(
        at url: URL,
        to destination: MobileBrowserFileExportDestination,
        in window: UIWindow?
    ) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        presentFile(at: url, temporaryDirectoryURL: nil, to: destination, in: window)
    }

    static func exportDocument(
        _ data: Data,
        filename: String,
        to destination: MobileBrowserFileExportDestination,
        in window: UIWindow?
    ) async throws {
        let directoryURL = try await Task.detached(priority: .userInitiated) {
            let directoryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CrestPageExports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            try data.write(
                to: directoryURL.appendingPathComponent(filename),
                options: .atomic
            )
            return directoryURL
        }.value
        let fileURL = directoryURL.appendingPathComponent(filename)
        presentFile(
            at: fileURL,
            temporaryDirectoryURL: directoryURL,
            to: destination,
            in: window
        )
    }

    static func presentError(title: String, message: String, in window: UIWindow?) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, in: window, fallback: {})
    }

    private static func present(
        _ alert: UIAlertController,
        in window: UIWindow?,
        dismissal: BrowserPromptDismissal? = nil,
        fallback: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let presenter = topViewController(in: window) else {
            fallback()
            return
        }
        dismissal?.attach { [weak alert] in
            alert?.presentingViewController?.dismiss(animated: true)
        }
        presenter.present(alert, animated: true)
    }

    /// Presents `viewController` over the top view controller of `window`,
    /// or of the key window when it is nil, or calls `fallback` when there
    /// is none to present it over.
    static func present(
        _ viewController: UIViewController,
        in window: UIWindow?,
        fallback: @escaping @MainActor @Sendable () -> Void
    ) {
        guard let presenter = topViewController(in: window) else {
            fallback()
            return
        }
        if let popover = viewController.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.maxY,
                width: 1,
                height: 1
            )
            popover.permittedArrowDirections = []
        }
        presenter.present(viewController, animated: true)
    }

    private static func presentFile(
        at fileURL: URL,
        temporaryDirectoryURL: URL?,
        to destination: MobileBrowserFileExportDestination,
        in window: UIWindow?
    ) {
        destination.download.send(
            fileURL,
            to: MobileBrowserFilePresenter(temporaryDirectoryURL: temporaryDirectoryURL, window: window))
    }

    /// The page's server as a dialog names it, which the core formats: its
    /// host, with the port only when it is not the scheme's default.
    private static func sourceLabel(for request: URLRequest) -> String {
        guard let url = request.url, let host = url.host(), !host.isEmpty else {
            return ProductIdentity.name
        }
        guard let port = url.port else { return host }
        return AuthenticationSource.label(
            host: host, port: port, scheme: url.scheme, emptyHostLabel: ProductIdentity.name)
    }

    /// The top of `window`'s presentation stack, or of the key window's when
    /// `window` is nil. Every scene has a key window, so the key-window scan
    /// may land in another iPad window; `window` is what keeps a page's
    /// dialog in the window that shows the page.
    private static func topViewController(in window: UIWindow?) -> UIViewController? {
        let root = (window ?? keyWindow())?.rootViewController
        var current = root
        while let presented = current?.presentedViewController {
            current = presented
        }
        return current
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { scene in scene.windows }
            .first { window in window.isKeyWindow }
    }
}

/// Resumes an alert's continuation once, with whichever answer comes first:
/// one of its actions, or its question's dismissal.
@MainActor
private final class AlertAnswer<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Value) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
