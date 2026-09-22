import Foundation

/// Whether an offered — or already downloaded and waiting — update is actually
/// newer than the Crest that is running.
///
/// Sparkle keeps a prepared update in the host bundle's cache, and the next
/// process to start from that bundle resumes it. A build whose
/// `MARKETING_VERSION` has since moved ahead of the cached one is then told it
/// is "Ready to Install" a Crest older than itself, and accepting that would
/// silently downgrade. Sparkle's own comparison is against the bundle's
/// recorded version, so the running version has to be checked here.
enum BrowserSoftwareUpdateVersionPolicy {
    static var runningVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String
    }

    /// Absent or unparseable versions are treated as newer: the guard exists to
    /// catch a stale cache, never to block a legitimate update it cannot read.
    static func isNewer(_ offered: String?, thanRunning running: String?) -> Bool {
        guard
            let offered = offered?.trimmingCharacters(in: .whitespacesAndNewlines),
            !offered.isEmpty,
            let running = running?.trimmingCharacters(in: .whitespacesAndNewlines),
            !running.isEmpty
        else { return true }
        return offered.compare(running, options: .numeric) == .orderedDescending
    }
}
