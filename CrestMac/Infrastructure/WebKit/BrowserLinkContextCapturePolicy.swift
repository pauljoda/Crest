import Foundation

/// The link a right-click landed on, held for exactly the one web-content
/// context menu that right-click opens.
///
/// macOS `WKUIDelegate` never reports the element under the cursor, so the
/// destination has to come from the page itself. WebKit dispatches the
/// `contextmenu` DOM event in the web content process before that process
/// answers the UI process with the menu's contents, so a report posted from
/// that event always arrives first — no hit test of Crest's own races WebKit's.
///
/// What such a capture must never do is outlive its menu. A right-click on
/// plain text would otherwise inherit the link from the previous right-click,
/// and "Open Link in Split View" would open a page nobody pointed at. Three
/// rules together make that impossible: every report replaces the slot — a
/// right-click that found no link reports exactly that — a menu *takes* the
/// capture instead of reading it, and a token that only ever increases refuses
/// a second take of the same report even if a caller forgets to clear.
struct BrowserLinkContextCapturePolicy: Equatable, Sendable {
    /// The message contract the injected script posts against. A payload from
    /// an older or newer script is discarded rather than guessed at.
    static let contractVersion = 1

    /// Long enough for any real link, short enough that a page cannot park a
    /// megabyte-scale `data:` URL in the slot on every right-click.
    private static let maximumHrefLength = 4_096

    private var pendingURL: URL?
    private var pendingToken = 0
    private var consumedToken = 0

    /// The link a menu opening right now would carry, without consuming it.
    var pendingLink: URL? {
        pendingToken > consumedToken ? pendingURL : nil
    }

    /// Records one `contextmenu` report from the content bridge.
    ///
    /// A malformed payload, a report over plain content, and a destination
    /// Crest would not open in a tab are all the same answer: the slot empties.
    /// Anything else would leave the last good link in place for a menu it has
    /// nothing to do with.
    mutating func record(body: Any) {
        pendingToken += 1
        pendingURL = Self.destination(body: body)
    }

    /// Hands the pending link to the menu now opening and empties the slot.
    mutating func takeLink() -> URL? {
        defer { consumedToken = pendingToken }
        return pendingLink
    }

    /// Drops whatever a closing menu did not use, and whatever a right-click
    /// that never produced a menu left behind.
    mutating func clear() {
        consumedToken = pendingToken
        pendingURL = nil
    }

    private static func destination(body: Any) -> URL? {
        guard let dictionary = body as? [String: Any],
            dictionary["version"] as? Int == contractVersion,
            let href = dictionary["href"] as? String,
            href.count <= maximumHrefLength,
            let url = URL(string: href),
            // The same gate every other link affordance uses, so the menu can
            // never offer a `javascript:` or `data:` destination that the
            // new-tab path would refuse a moment later.
            BrowserExternalURLPolicy.accepts(url)
        else { return nil }
        return url
    }
}
