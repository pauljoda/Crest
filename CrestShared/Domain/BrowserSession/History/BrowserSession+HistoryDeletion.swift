import Foundation

/// Targeted history removal.
///
/// Browsing only ever appends, so until now a Space's history could be cleared
/// wholesale but never edited. `chrome.history.deleteUrl` and `deleteRange`
/// need finer removal, and so does any future "forget this site" affordance.
extension BrowserSession {
    /// Removes the entry for `url`, reporting whether one was present.
    ///
    /// The URL is normalized the same way ``recordVisit(url:title:at:)``
    /// normalizes it, so callers can pass the address they navigated to rather
    /// than the stored form.
    @discardableResult
    mutating func removeHistory(for url: URL, in spaceID: SpaceID) -> Bool {
        guard let normalizedURL = BrowserHistoryURL.normalized(url),
            let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else {
            return false
        }

        let originalCount = spaces[spaceIndex].history.count
        spaces[spaceIndex].history.removeAll { $0.url == normalizedURL }
        return spaces[spaceIndex].history.count != originalCount
    }

    /// Removes every entry last visited within `startDate ..< endDate`,
    /// reporting whether anything was removed.
    ///
    /// The window is half-open to match `chrome.history.deleteRange`, and an
    /// entry is judged only by its last visit: Crest keeps no per-visit rows,
    /// so an older visit to a page that was also opened after the window cannot
    /// be removed on its own.
    @discardableResult
    mutating func removeHistory(
        from startDate: Date,
        until endDate: Date,
        in spaceID: SpaceID
    ) -> Bool {
        guard let spaceIndex = spaces.firstIndex(where: { $0.id == spaceID })
        else {
            return false
        }

        let originalCount = spaces[spaceIndex].history.count
        spaces[spaceIndex].history.removeAll { entry in
            entry.lastVisitedAt >= startDate && entry.lastVisitedAt < endDate
        }
        return spaces[spaceIndex].history.count != originalCount
    }
}
