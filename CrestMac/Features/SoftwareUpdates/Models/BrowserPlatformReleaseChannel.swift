import Foundation

/// The release line this build of Crest was packaged for.
enum BrowserPlatformReleaseChannel {
    static func current() async -> BrowserReleasePage.Channel {
        (BrowserSoftwareUpdateChannel.bundled ?? .development).releaseChannel
    }
}
