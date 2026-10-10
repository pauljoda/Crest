import CryptoKit
import Foundation

/// Where local tools reach this launch of Crest: a Unix domain socket in
/// Crest's own Application Support directory. A review launch that keeps its
/// session apart keeps its socket apart too, and a launch that keeps nothing
/// on disk offers none.
enum BrowserAutomationEndpoint {
    // MARK: - Static Variables

    /// The longest path a Unix domain socket address holds, less its
    /// terminator.
    static let maximumPathLength = MemoryLayout.size(ofValue: sockaddr_un().sun_path) - 1

    // MARK: - Actions - Paths

    /// The socket's path for `launchEnvironment`, or nil when the launch
    /// offers none or the path would not fit a socket address.
    static func path(for launchEnvironment: BrowserLaunchEnvironment) -> String? {
        let isolationID = launchEnvironment.persistentIsolationID
        guard !launchEnvironment.requiresIsolation || isolationID != nil,
            var directory = try? FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        else { return nil }
        directory.appendPathComponent(ProductIdentity.storageDirectoryName, isDirectory: true)
        let name: String
        if launchEnvironment.requiresIsolation, let isolationID {
            let namespace = SHA256.hash(data: Data(isolationID.utf8)).prefix(8).map { String(format: "%02x", $0) }
            directory.appendPathComponent("Automation", isDirectory: true)
            name = namespace.joined() + ".sock"
        } else {
            name = "Automation.sock"
        }
        let path = directory.appendingPathComponent(name, isDirectory: false).path
        return path.utf8.count <= maximumPathLength ? path : nil
    }
}
