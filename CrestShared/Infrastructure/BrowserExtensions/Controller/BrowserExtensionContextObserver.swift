import Foundation
import WebKit

@MainActor
final class BrowserExtensionContextObserver {
    private var tokensByContext: [ObjectIdentifier: [NSObjectProtocol]] = [:]

    isolated deinit {
        stopObservingAll()
    }

    func observe(
        _ context: WKWebExtensionContext,
        permissionsDidChange: @escaping @MainActor () -> Void,
        runtimeSummaryDidChange: @escaping @MainActor () -> Void
    ) {
        stopObserving(context)

        let permissionNames: [Notification.Name] = [
            WKWebExtensionContext.permissionsWereGrantedNotification,
            WKWebExtensionContext.permissionsWereDeniedNotification,
            WKWebExtensionContext
                .grantedPermissionsWereRemovedNotification,
            WKWebExtensionContext
                .deniedPermissionsWereRemovedNotification,
            WKWebExtensionContext
                .permissionMatchPatternsWereGrantedNotification,
            WKWebExtensionContext
                .permissionMatchPatternsWereDeniedNotification,
            WKWebExtensionContext
                .grantedPermissionMatchPatternsWereRemovedNotification,
            WKWebExtensionContext
                .deniedPermissionMatchPatternsWereRemovedNotification,
        ]
        var tokens = permissionNames.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: context,
                queue: .main
            ) { _ in
                Task { @MainActor in permissionsDidChange() }
            }
        }
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: WKWebExtensionContext.errorsDidUpdateNotification,
                object: context,
                queue: .main
            ) { _ in
                Task { @MainActor in runtimeSummaryDidChange() }
            }
        )
        // A fault the extension's own JavaScript reported is not in WebKit's
        // error list, so `errorsDidUpdateNotification` never fires for it. The
        // diagnostics log posts its own, keyed by unique identifier because
        // the log holds no context references.
        let contextIdentifier = context.uniqueIdentifier
        tokens.append(
            NotificationCenter.default.addObserver(
                forName: BrowserExtensionDiagnosticsLog
                    .didRecordNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard
                    notification.userInfo?[
                        BrowserExtensionDiagnosticsLog.contextIdentifierKey
                    ] as? String == contextIdentifier
                else {
                    return
                }
                Task { @MainActor in runtimeSummaryDidChange() }
            }
        )
        tokensByContext[ObjectIdentifier(context)] = tokens
    }

    func stopObserving(_ context: WKWebExtensionContext) {
        let key = ObjectIdentifier(context)
        for token in tokensByContext.removeValue(forKey: key) ?? [] {
            NotificationCenter.default.removeObserver(token)
        }
    }

    func stopObservingAll() {
        for tokens in tokensByContext.values {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
        }
        tokensByContext.removeAll()
    }
}
