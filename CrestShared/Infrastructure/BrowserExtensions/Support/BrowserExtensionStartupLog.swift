import Foundation
import os

/// Names every gate between launch and a running extension.
///
/// Silence is the failure mode worth instrumenting here. Each gate below can
/// skip its work for an ordinary reason — a private pool, a restore that has
/// already run, a record filed under a Space this session does not carry, an
/// extension the person disabled — and every one of them used to end with no
/// extension log lines at all. That is indistinguishable from a subsystem that
/// never initialized, which is exactly the ambiguity that made one incident
/// unreadable: "no extension ever loaded" and "no extension was asked to load"
/// looked the same from outside.
///
/// Every line is counted and public so a single `log show` names the gate:
///
/// ```
/// log show --last 1h --info --debug --predicate \
///   'subsystem == "com.pauldavis.crest" AND category == "extension-startup"'
/// ```
enum BrowserExtensionStartupLog {
    private static let log = Logger(
        subsystem: "com.pauldavis.crest",
        category: "extension-startup"
    )

    /// A private pool never restores extensions. Recorded so a private window's
    /// silence is not mistaken for the standard pool's.
    static func skippedPrivateBrowsing() {
        log.notice("restore skipped: private browsing pool")
    }

    /// Restoration runs once per launch. A second caller finding the flag
    /// already set is normal; a *first* caller never arriving is not, and only
    /// the presence of this line distinguishes them.
    static func skippedAlreadyRestored() {
        log.notice("restore skipped: already restored this launch")
    }

    static func began(spaceCount: Int, installationCount: Int) {
        log.notice(
            """
            restore begin: \(spaceCount, privacy: .public) space(s), \
            \(installationCount, privacy: .public) installation record(s)
            """
        )
    }

    static func skippedDisabled(extensionID: String) {
        log.notice(
            """
            restore skip \(extensionID, privacy: .public): \
            record is disabled
            """
        )
    }

    /// The quietest gate of all: a record whose Space is not in this session is
    /// dropped by a bare `continue`. It is how a whole extension set can vanish
    /// after the Spaces it was filed under are replaced.
    static func skippedMissingSpace(extensionID: String, spaceID: SpaceID) {
        log.error(
            """
            restore skip \(extensionID, privacy: .public): \
            no Space \(spaceID.rawValue.uuidString, privacy: .public) \
            in this session
            """
        )
    }

    static func loaded(extensionID: String, spaceID: SpaceID) {
        log.notice(
            """
            restore loaded \(extensionID, privacy: .public) \
            in Space \(spaceID.rawValue.uuidString, privacy: .public)
            """
        )
    }

    static func failed(extensionID: String, error: any Error) {
        log.error(
            """
            restore failed \(extensionID, privacy: .public): \
            \(String(describing: error), privacy: .public)
            """
        )
    }

    static func finished(
        installationCount: Int,
        enabled: Int,
        loaded: Int,
        skippedMissingSpace: Int,
        failed: Int
    ) {
        log.notice(
            """
            restore complete: \(installationCount, privacy: .public) record(s), \
            \(enabled, privacy: .public) enabled, \
            \(loaded, privacy: .public) loaded, \
            \(skippedMissingSpace, privacy: .public) skipped (no such Space), \
            \(failed, privacy: .public) failed
            """
        )
    }
}
