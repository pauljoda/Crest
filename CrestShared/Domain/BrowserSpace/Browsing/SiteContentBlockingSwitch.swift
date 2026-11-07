import Foundation

/// What a page's actions offer for ads and trackers on the site the page
/// shows: to stop blocking them there, or to block them again. It is offered
/// only where the page's Space blocks, for a website; the Space-wide switch
/// lives in the Space's privacy settings.
struct SiteContentBlockingSwitch: Equatable {
    // MARK: - Variables

    let spaceID: UUID
    let origin: SiteOrigin
    /// Whether the Space blocks on the site now.
    let blocks: Bool

    /// What the action says it does.
    var title: LocalizedStringResource {
        blocks ? "Turn Off Blocking on \(origin.displayName)" : "Turn On Blocking on \(origin.displayName)"
    }

    /// What the action sends the core.
    var intent: SetSiteContentBlocking {
        SetSiteContentBlocking(spaceID: spaceID, origin: origin, blocks: !blocks)
    }

    // MARK: - Initializers

    /// The switch for a page of `spaceID` showing `url`, or nil where none is
    /// offered: no page, a page that shows no website, or a Space that blocks
    /// nothing.
    @MainActor
    init?(core: CrestCore, spaceID: UUID?, url: URL?) {
        guard let spaceID, let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
            let origin = SiteOrigin(url: url),
            (try? core.query(ContentBlockingApplies(spaceID: spaceID, origin: nil))) == true
        else { return nil }
        self.spaceID = spaceID
        self.origin = origin
        blocks = (try? core.query(ContentBlockingApplies(spaceID: spaceID, origin: origin))) ?? true
    }
}
