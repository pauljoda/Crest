import Foundation

/// A release's page on Crest's site, which lists everything that changed in
/// it, at `/releases/<platform>/<channel>/<version>/`. The site sends the
/// address of a version without a page of its own to the release that holds
/// it, so every version Crest names opens a page.
struct BrowserReleasePage: Equatable, Sendable {
    // MARK: - Types

    /// A release line the site lists, under the platform that ships it.
    struct Channel: Hashable, Sendable {
        static let stable = Channel(platform: "mac", name: "stable")
        static let nightly = Channel(platform: "mac", name: "nightly")
        static let development = Channel(platform: "mac", name: "development")
        static let appStore = Channel(platform: "ios", name: "app-store")
        static let testFlight = Channel(platform: "ios", name: "testflight")

        /// The platform's name in the site's addresses.
        let platform: String
        /// The channel's name in the site's addresses.
        let name: String
    }

    // MARK: - Static Variables

    private static let releases: URL = {
        guard let url = URL(string: "https://crestbrowser.com/releases") else {
            preconditionFailure("Invalid release notes address")
        }
        return url
    }()

    // MARK: - Variables

    let version: String
    let channel: Channel

    var url: URL {
        Self.releases.appending(components: channel.platform, channel.name, version, directoryHint: .isDirectory)
    }

    // MARK: - Actions - This Build

    /// The page of this build's release, on the channel it came from.
    static func current() async -> BrowserReleasePage {
        await BrowserReleasePage(
            version: BrowserAboutBuildInformation.current.version, channel: BrowserPlatformReleaseChannel.current())
    }

    // MARK: - Actions - Launch

    /// Tells the core which release this launch runs, which it keeps as the
    /// one this device launched last. A showcase launch tells it nothing, so
    /// its windows open as seeded.
    @MainActor static func noteLaunch(in core: CrestCore, environment: BrowserLaunchEnvironment) {
        guard !environment.presentsShowcaseSession else { return }
        _ = try? core.send(NoteLaunchRelease(version: BrowserAboutBuildInformation.current.version))
    }

    /// The page of the release this launch follows an update to, for the
    /// first window over the person's own Spaces that asks once it opens;
    /// nil for every other window, and after any other launch.
    @MainActor static func dueAtLaunch(in browser: BrowserStore) async -> BrowserReleasePage? {
        guard browser.family.keepsWindowRecords else { return nil }
        let due = ((try? browser.core.send(TakeReleaseNotes())) ?? []).lazy.compactMap { change -> ReleaseNotesDue? in
            if case .releaseNotesDue(let due) = change { return due }
            return nil
        }.first
        guard let due else { return nil }
        return await BrowserReleasePage(version: due.version, channel: BrowserPlatformReleaseChannel.current())
    }
}
