import Foundation
import os

/// A category of Crest's unified log. The application layer writes through
/// it, so the stores that report a core's refusal name where the message goes
/// without depending on the logging framework. A message is written public,
/// whole, as it reads.
struct DiagnosticLog: Sendable {
    // MARK: - Static Variables

    /// The subsystem every category of Crest's log is written under.
    static let subsystem = ProductIdentity.bundleIdentifier

    static let agents = DiagnosticLog(category: "Agents")
    static let downloads = DiagnosticLog(category: "Downloads")
    /// Why the core refused to preview or apply an import from another
    /// browser.
    static let imports = DiagnosticLog(category: "Import")
    static let links = DiagnosticLog(category: "Links")
    /// Which pages each window shows, the engine told to show or hide a page,
    /// Picture in Picture and what memory pressure takes back. Pages are named
    /// by their identities, never their addresses.
    static let pages = DiagnosticLog(category: "Pages")
    /// Each step through a page's history, from the person's input to the
    /// command the core hands its engine and the history the engine reports,
    /// timed for Instruments.
    static let pageHistory = DiagnosticLog(category: "PageHistory")
    static let popups = DiagnosticLog(category: "Popups")
    /// Why the core could not save the session, or a save outran the wait for
    /// it at quit.
    static let sessionStorage = DiagnosticLog(category: "SessionStorage")
    static let shortcuts = DiagnosticLog(category: "Shortcuts")
    static let sitePermissions = DiagnosticLog(category: "SitePermissions")
    static let windows = DiagnosticLog(category: "Windows")
    /// A page view's host claiming and letting go of it, timed for
    /// Instruments.
    static let surfaceLifecycle = DiagnosticLog(category: "BrowserSurfaceLifecycle")
    /// A WebKit page's view made, shown and torn down, timed for Instruments.
    static let webKitLifecycle = DiagnosticLog(category: "WebKitLifecycle")

    // MARK: - Variables

    /// The category's logger, for code that writes with the logging
    /// framework's own levels and privacy.
    let logger: Logger

    /// The category's signposter, for the intervals Instruments shows.
    var signposter: OSSignposter { OSSignposter(logger: logger) }

    // MARK: - Initializers

    private init(category: String) {
        logger = Logger(subsystem: Self.subsystem, category: category)
    }

    // MARK: - Actions - Describing

    /// How a message names `error`: a rejection by its rule alone, because
    /// what it carries can name an address or a site the log must not keep,
    /// and any other error as it describes itself.
    static func describe(_ error: any Error) -> String {
        guard let rejection = error as? Rejection else { return String(describing: error) }
        return Mirror(reflecting: rejection).children.first?.label ?? String(describing: rejection)
    }

    // MARK: - Actions - Writing

    func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    func notice(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
