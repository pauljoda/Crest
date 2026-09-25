import Foundation

extension AppConfiguration {
    /// A configuration for the device this process runs on, keeping the
    /// session in `storageDirectory`, or in memory when it is nil.
    init(storageDirectory: String?) {
        self.init(storageDirectory: storageDirectory, platform: .current)
    }
}
