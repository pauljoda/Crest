import Foundation

@MainActor
struct BrowserTransientBrowsingPreferences {
    let archiveLifetime: TimeInterval?
    private let rememberSpaceHandler: (SpaceID, URL) -> Void

    init(
        archiveLifetime: TimeInterval?,
        rememberSpace: @escaping (SpaceID, URL) -> Void
    ) {
        self.archiveLifetime = archiveLifetime
        rememberSpaceHandler = rememberSpace
    }

    func rememberSpace(_ spaceID: SpaceID, for url: URL) {
        rememberSpaceHandler(spaceID, url)
    }

    static let isolated = BrowserTransientBrowsingPreferences(
        archiveLifetime: nil,
        rememberSpace: { _, _ in }
    )
}
