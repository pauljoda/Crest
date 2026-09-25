import Foundation

/// What the tab surfaces draw from a tab of the read model, in their own
/// vocabulary. Each member reads only the fields it names, so a view that
/// draws one of them redraws only when those fields change.
extension TabStateModel {
    // MARK: - Variables

    /// A tab with neither a page nor native content: the Start Page, which
    /// the sidebar lists nowhere.
    var isStartPage: Bool {
        nativeContent == nil && url == nil
    }

    var isWebPage: Bool {
        nativeContent == nil && url != nil
    }

    /// The address the tab shows, as the platform reads addresses.
    var address: URL? {
        url.flatMap(URL.init(string:))
    }

    /// The native document the tab shows, in the vocabulary the views match.
    var nativeTabContent: BrowserNativeTabContent? {
        nativeContent.map { BrowserNativeTabContent(kind: $0.kind, resourceID: $0.resourceID) }
    }

    /// The emoji the tab wears in place of its icon, if it chose one.
    var emojiIcon: String? {
        BrowserIconSymbol.emoji(from: symbol)
    }

    /// The accent the tab's icon was given, in the vocabulary the views draw.
    var iconTint: BrowserTabIconAccent? {
        iconAccent.map { BrowserTabIconAccent(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    /// Whether a person can replace or return to the address the tab keeps.
    var supportsSavedLocationEditing: Bool {
        placement.isDurable && (savedURL ?? url) != nil
    }
}
