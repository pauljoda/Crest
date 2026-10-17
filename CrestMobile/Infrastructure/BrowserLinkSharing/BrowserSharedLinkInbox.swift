import Foundation

/// Links the share extension saved because it could not open Crest. Crest
/// opens them, oldest first, the next time one of its windows becomes
/// active.
struct BrowserSharedLinkInbox: @unchecked Sendable {
    // MARK: - Static Variables

    /// The most links the inbox keeps; sharing more drops the oldest.
    static let capacity = 20
    private static let linksKey = "crest.share.saved-links"

    // MARK: - Variables

    let defaults: UserDefaults

    /// The saved links, oldest first.
    var savedLinks: [BrowserSharedLink] {
        guard let data = defaults.data(forKey: Self.linksKey) else { return [] }
        return (try? JSONDecoder().decode([BrowserSharedLink].self, from: data)) ?? []
    }

    // MARK: - Actions - Saving

    /// Keeps `link` for Crest to open, after the links saved before it.
    func save(_ link: BrowserSharedLink) {
        let links = Array((savedLinks + [link]).suffix(Self.capacity))
        guard let data = try? JSONEncoder().encode(links) else { return }
        defaults.set(data, forKey: Self.linksKey)
    }

    // MARK: - Actions - Opening

    /// The saved links, oldest first, which the inbox no longer holds.
    func takeAll() -> [BrowserSharedLink] {
        let links = savedLinks
        if defaults.object(forKey: Self.linksKey) != nil {
            defaults.removeObject(forKey: Self.linksKey)
        }
        return links
    }
}
