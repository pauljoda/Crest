import SwiftUI

enum BrowserMacOnboardingTutorial: String {
    case spaces
    case tabs
    case sync

    var eyebrow: LocalizedStringKey {
        switch self {
        case .spaces: "SPACES"
        case .tabs: "TABS"
        case .sync: "PRIVATE SYNC"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .spaces: "Everything in its Space"
        case .tabs: "A place for every tab"
        case .sync: "Yours on every device"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .spaces:
            "Each Space is its own browser, with its own identity, history, accounts, and site data."
        case .tabs:
            "Keep essential sites pinned, save useful pages for later, and leave only active work open."
        case .sync:
            "Crest syncs your setup privately with iCloud while preserving the boundaries between Spaces."
        }
    }

    var primaryTitle: LocalizedStringKey {
        self == .sync ? "Choose Import Options" : "Continue"
    }

    var features: [BrowserMacOnboardingTutorialFeature] {
        switch self {
        case .spaces:
            [
                .init(
                    symbol: "square.grid.2x2.fill",
                    title: "Separate by default",
                    detail: "Cookies, accounts, history, and permissions stay inside their Space."
                ),
                .init(
                    symbol: "paintpalette.fill",
                    title: "Make each one recognizable",
                    detail: "Choose a name, symbol, and appearance before you begin browsing."
                ),
            ]
        case .tabs:
            [
                .init(
                    symbol: "pin.fill",
                    title: "Pinned",
                    detail: "Essentials that are always ready at the top."
                ),
                .init(
                    symbol: "bookmark.fill",
                    title: "Saved",
                    detail: "Pages kept for later without staying open."
                ),
                .init(
                    symbol: "rectangle.stack.fill",
                    title: "Open",
                    detail: "The pages you are actively using now."
                ),
            ]
        case .sync:
            [
                .init(
                    symbol: "icloud.fill",
                    title: "Private iCloud sync",
                    detail: "Your Spaces and tabs follow you without becoming one shared profile."
                ),
                .init(
                    symbol: "square.and.arrow.down.fill",
                    title: "Import here on your Mac",
                    detail: "Bring over browser data only after reviewing exactly what Crest will add."
                ),
            ]
        }
    }
}
