import Foundation

/// Cadence for re-applying each Space's tab cleanup and stored-data retention
/// policies while a scene is active.
///
/// Cleanup used to run only while a store was being built, so a session that
/// stayed open for days never archived anything. The policies are hour-granular,
/// so a low-frequency sweep keeps up with them, and pinning the cadence here
/// keeps it testable instead of buried in a scene. The core spaces the sweeps
/// that windows ask for together.
enum BrowserCurrentTabCleanupSchedule {
    /// How long an active scene waits between sweeps.
    static let sweepInterval: TimeInterval = 15 * 60
}
