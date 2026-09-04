import Foundation
import os

/// Records the protocol methods Crest refused, once per method per session.
///
/// A refused command is invisible to everyone but the client that sent it, so
/// without this the only evidence that a domain is worth building is a user
/// reporting that an extension "does not work". One line per method keeps a
/// client that retries in a loop from turning the log into noise.
@MainActor
final class BrowserChromeDebuggerUnsupportedLog {
    private static let log = Logger(
        subsystem: ProductIdentity.serviceNamespace, category: "extension-diagnostics")
    private static let methodLimit = 32

    private var reported: Set<String> = []

    func record(_ method: String, client: BrowserExtensionServiceClientID) {
        guard reported.count < Self.methodLimit, reported.insert(method).inserted else { return }
        Self.log.notice(
            """
            Debugger command unsupported: \
            method=\(method, privacy: .public) client=\(client.rawValue, privacy: .public)
            """)
    }
}
