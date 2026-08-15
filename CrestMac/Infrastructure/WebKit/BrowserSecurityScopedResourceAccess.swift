import Foundation
import Security
import WebKit

@MainActor
final class BrowserSecurityScopedResourceAccess {
    let url: URL
    let refreshedBookmark: Data?
    private let isAccessing: Bool

    init(bookmark: Data) throws {
        var isStale = false
        url = try URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        isAccessing = url.startAccessingSecurityScopedResource()
        refreshedBookmark =
            isStale
            ? try? url.bookmarkData(
                options: [
                    .withSecurityScope,
                    .securityScopeAllowOnlyReadAccess,
                ],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            : nil
    }

    deinit {
        if isAccessing {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
