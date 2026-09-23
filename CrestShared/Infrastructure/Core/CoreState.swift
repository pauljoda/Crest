import Foundation
import Observation

/// The Swift read model of the core's state. Views read it directly; only the
/// changes `CrestCore` receives update it, each through its applier in a
/// `CoreState+Area.swift` file.
@MainActor
@Observable
final class CoreState {
    // MARK: - Variables

    /// This run's download records, newest first.
    var downloads: [DownloadState] = []
}
