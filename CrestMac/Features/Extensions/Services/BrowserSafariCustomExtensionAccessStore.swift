import Foundation

enum BrowserSafariCustomExtensionAccessStore {
    private static let bookmarkKey =
        "browser.extensions.safari-custom-directory"

    static func resolve(defaults: UserDefaults? = nil) -> URL? {
        guard let defaults = launchDefaults(defaults),
            let bookmark = defaults.data(forKey: bookmarkKey)
        else {
            return nil
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                try? remember(url, defaults: defaults)
            }
            return url
        } catch {
            defaults.removeObject(forKey: bookmarkKey)
            return nil
        }
    }

    static func remember(
        _ directoryURL: URL,
        defaults: UserDefaults? = nil
    ) throws {
        guard let defaults = launchDefaults(defaults) else { return }
        let bookmark = try directoryURL.bookmarkData(
            options: [
                .withSecurityScope,
                .securityScopeAllowOnlyReadAccess,
            ],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: bookmarkKey)
    }

    static func clear(defaults: UserDefaults? = nil) {
        launchDefaults(defaults)?.removeObject(forKey: bookmarkKey)
    }

    private static func launchDefaults(
        _ explicitDefaults: UserDefaults?
    ) -> UserDefaults? {
        if let explicitDefaults { return explicitDefaults }
        guard !BrowserLaunchIsolationPolicy.requiresIsolation(.current) else {
            return nil
        }
        return .standard
    }
}
